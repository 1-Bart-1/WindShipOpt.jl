// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

import { geoEquirectangular, geoGraticule10, geoOrthographic, geoPath, type GeoPath, type GeoProjection } from "d3-geo";
import { feature } from "topojson-client";
import land from "world-atlas/land-110m.json";
import { brandColour } from "../brand";
import {
  edgesFrom,
  faceGlobe,
  horizon,
  kindOf,
  position,
  screenPoints,
  unitVectors,
  type Edge,
  type Grid,
  type RoutesThrough,
  type ScreenPoints,
  type UnitVectors,
} from "./grid";

/** One grid on the map with its edges, coarse grids drawn with larger nodes. */
export interface ShownGrid {
  spacing: string;
  grid: Grid;
  edges: Edge[];
  coarse: boolean;
}

/** A node of the grid at `spacing`. */
export interface GridNode {
  spacing: string;
  node: number;
}

export interface PickedNode extends GridNode {
  routes: RoutesThrough;
}

/** What the map draws, on a globe or flat. */
export interface GridView {
  grids: ShownGrid[];
  flat: boolean;
  mesh: boolean;
  unusable: boolean;
  allEdges: boolean;
  folds: boolean;
  picked?: PickedNode;
}

/** One shown grid's lines and nodes as lists of node numbers, built once per view. */
interface GridLayer extends ShownGrid {
  meshLines: number[][];
  /** empty unless the view shows every edge */
  edgeLines: number[][];
  rowFolds: number[][];
  backwardEdges: number[][];
  usable: number[];
  unusable: number[];
  sphere: UnitVectors;
  /** where each node lies on the canvas [px], as last projected */
  screen: ScreenPoints;
}

/** The last full drawing and the view it shows, moved and scaled in place during a gesture. */
interface Snapshot {
  image: HTMLCanvasElement;
  facing: [number, number];
  zoom: number;
}

const topology = land as unknown as Parameters<typeof feature>[0] & { objects: { land: never } };
const landShape = feature(topology, topology.objects.land) as unknown as GeoJSON.FeatureCollection;
const graticule = geoGraticule10().coordinates as [number, number][][];
const pickRadius = 12;
const settleDelay = 150; // [ms] after the last wheel event before the map is drawn in full again

/** Each of `edges` as the line through its two nodes. */
const edgeLines = (edges: Edge[]) => edges.map((edge) => [edge.from, edge.to]);

/**
 * Router grids on a canvas, as an orthographic globe or a flat longitude and latitude map;
 * drag turns or pans it, the wheel zooms, a click picks a node.
 */
export class GridMap {
  private context: CanvasRenderingContext2D;
  private globe = geoOrthographic().clipAngle(90).precision(1);
  private plane = geoEquirectangular().precision(1);
  private projection: GeoProjection = this.globe;
  private path: GeoPath;
  private facing: [number, number] = [-40, 35];
  private zoom = 1;
  private width = 0;
  private height = 0;
  private view: GridView = { grids: [], flat: false, mesh: true, unusable: true, allEdges: false, folds: true };
  private layers: GridLayer[] = [];
  private frame = 0;
  private snapshot: Snapshot = { image: document.createElement("canvas"), facing: [0, 0], zoom: 1 };
  private gesture = false;
  private settle = 0;
  private drag?: { x: number; y: number; facing: [number, number]; moved: boolean };
  private observer: ResizeObserver;

  constructor(
    private canvas: HTMLCanvasElement,
    private onPick: (picked: GridNode | undefined) => void,
  ) {
    this.context = canvas.getContext("2d")!;
    this.path = geoPath(this.projection, this.context);
    canvas.addEventListener("pointerdown", this.pointerDown);
    canvas.addEventListener("pointermove", this.pointerMove);
    canvas.addEventListener("pointerup", this.pointerUp);
    canvas.addEventListener("wheel", this.wheel, { passive: false });
    this.observer = new ResizeObserver(() => this.resize());
    this.observer.observe(canvas);
  }

  show(view: GridView) {
    this.view = view;
    this.projection = view.flat ? this.plane : this.globe;
    this.path = geoPath(this.projection, this.context);
    this.layers = view.grids.map((shown) => this.layer(shown));
    this.draw();
  }

  /** Face longitude and latitude `[lon, lat]` [deg], at `zoom` if given. */
  centre(facing: [number, number], zoom?: number) {
    this.facing = facing;
    if (zoom) this.zoom = zoom;
    this.draw();
  }

  zoomBy(factor: number) {
    this.zoom = Math.max(0.8, Math.min(16, this.zoom * factor));
    this.draw();
  }

  dispose() {
    cancelAnimationFrame(this.frame);
    clearTimeout(this.settle);
    this.observer.disconnect();
    this.canvas.removeEventListener("pointerdown", this.pointerDown);
    this.canvas.removeEventListener("pointermove", this.pointerMove);
    this.canvas.removeEventListener("pointerup", this.pointerUp);
    this.canvas.removeEventListener("wheel", this.wheel);
  }

  private resize() {
    const ratio = window.devicePixelRatio || 1;
    this.width = this.canvas.clientWidth;
    this.height = this.canvas.clientHeight;
    this.canvas.width = this.width * ratio;
    this.canvas.height = this.height * ratio;
    this.context.setTransform(ratio, 0, 0, ratio, 0, 0);
    this.render();
  }

  private place() {
    const [lon, lat] = this.facing;
    const centre: [number, number] = [this.width / 2, this.height / 2];
    if (!this.view.flat) {
      this.globe.rotate([-lon, -lat]).scale((Math.min(...centre) - 8) * this.zoom).translate(centre);
      return;
    }
    this.plane.rotate([-lon, 0]).center([0, lat]).scale((this.width / (2 * Math.PI)) * this.zoom).translate(centre);
  }

  /** Stroke the path begun on the canvas. */
  private stroke(colour: string, width: number, alpha = 1) {
    const context = this.context;
    context.globalAlpha = alpha;
    context.strokeStyle = colour;
    context.lineWidth = width;
    context.stroke();
    context.globalAlpha = 1;
  }

  /** Project every node of `layer` once, into its screen points. */
  private project({ grid, sphere, screen }: GridLayer) {
    if (!this.view.flat) return faceGlobe(sphere, this.globe, screen);
    for (let node = 0; node < grid.kind.length; node++) {
      [screen.x[node], screen.y[node]] = this.projection(position(grid, node))!;
      screen.facing[node] = 1;
    }
  }

  /**
   * Stroke the polylines through the nodes of `lines` in `layer`, as one path, cut where they
   * pass the globe's horizon or the flat map's edge.
   */
  private strokeNodes(layer: GridLayer, lines: number[][], colour: string, width: number, alpha = 1) {
    const { screen } = layer;
    const { x, y, facing } = screen;
    const context = this.context;
    context.beginPath();
    for (const line of lines) {
      let penDown = false;
      for (let i = 1; i < line.length; i++) {
        const [from, to] = [line[i - 1], line[i]];
        if (facing[from] <= 0 && facing[to] <= 0) {
          penDown = false;
          continue;
        }
        if (!penDown) context.moveTo(...(facing[from] > 0 ? [x[from], y[from]] as const : horizon(screen, to, from, this.globe)));
        if (this.view.flat) this.acrossEdge(screen, from, to);
        penDown = facing[to] > 0;
        context.lineTo(...(penDown ? [x[to], y[to]] as const : horizon(screen, from, to, this.globe)));
      }
    }
    this.stroke(colour, width, alpha);
  }

  /** Where the flat map's step from node `from` to `to` crosses its edge, draw to it and lift the pen to the other edge. */
  private acrossEdge({ x, y }: ScreenPoints, from: number, to: number) {
    const mapWidth = 2 * Math.PI * this.plane.scale();
    const jump = x[to] - x[from];
    if (Math.abs(jump) <= mapWidth / 2) return;
    const shift = Math.sign(jump) * mapWidth;
    const edge = this.plane.translate()[0] - shift / 2;
    const edgeY = y[from] + ((edge - x[from]) / (jump - shift)) * (y[to] - y[from]);
    this.context.lineTo(edge, edgeY);
    this.context.moveTo(edge + shift, edgeY);
  }

  /**
   * Draw on the next animation frame, once however often it is asked for before then; during a
   * gesture, by moving and scaling the last full drawing where that shows the new view.
   */
  private draw() {
    if (this.frame) return;
    this.frame = requestAnimationFrame(() => {
      this.frame = 0;
      if (this.gesture && this.fromSnapshot()) return;
      this.render();
    });
  }

  /** Show the view by moving and scaling the snapshot; false where a turned globe needs a full drawing. */
  private fromSnapshot() {
    const { image, facing, zoom } = this.snapshot;
    if (!this.view.flat && (facing[0] !== this.facing[0] || facing[1] !== this.facing[1])) return false;
    this.place();
    const [x, y] = this.projection(facing)!;
    const scale = this.zoom / zoom;
    const context = this.context;
    context.clearRect(0, 0, this.width, this.height);
    context.save();
    context.translate(x, y);
    context.scale(scale, scale);
    context.drawImage(image, -this.width / 2, -this.height / 2, this.width, this.height);
    context.restore();
    return true;
  }

  private takeSnapshot() {
    const { image } = this.snapshot;
    image.width = this.canvas.width;
    image.height = this.canvas.height;
    image.getContext("2d")!.drawImage(this.canvas, 0, 0);
    this.snapshot = { image, facing: this.facing, zoom: this.zoom };
  }

  /** Mark a gesture under way, drawn in full `delay` [ms] after its last event if given. */
  private moving(delay?: number) {
    if (!this.gesture) this.takeSnapshot();
    this.gesture = true;
    clearTimeout(this.settle);
    if (delay !== undefined) this.settle = window.setTimeout(() => this.settled(), delay);
  }

  private settled() {
    this.gesture = false;
    this.draw();
  }

  private render() {
    if (!this.width) return;
    const context = this.context;
    this.place();
    context.clearRect(0, 0, this.width, this.height);
    context.beginPath();
    this.path({ type: "Sphere" });
    context.fillStyle = brandColour("sky");
    context.fill();
    context.beginPath();
    this.path({ type: "MultiLineString", coordinates: graticule });
    this.stroke(brandColour("ink"), 0.5, 0.15);
    context.beginPath();
    this.path(landShape);
    context.fillStyle = brandColour("paper-deep");
    context.fill();
    this.stroke(brandColour("ink"), 0.6);
    for (const layer of this.layers) {
      this.project(layer);
      this.drawGrid(layer);
    }
    if (this.view.picked) this.drawPicked(this.view.picked);
  }

  private layer(shown: ShownGrid): GridLayer {
    const { grid, edges } = shown;
    const count = grid.kind.length;
    const nodes = Array.from({ length: count }, (_, node) => node);
    const ofKind = (kind: string) => nodes.filter((node) => kindOf(grid, node) === kind);
    return {
      ...shown,
      meshLines: this.meshLines(grid),
      edgeLines: this.view.allEdges ? edgeLines(edges) : [],
      rowFolds: this.rowFoldLines(grid),
      backwardEdges: edgeLines(edges.filter((edge) => edge.backward)),
      usable: ofKind("w"),
      unusable: ofKind("x"),
      sphere: unitVectors(grid),
      screen: screenPoints(count),
    };
  }

  private drawGrid(layer: GridLayer) {
    const { mesh, unusable, allEdges, folds } = this.view;
    const ink = brandColour("ink");
    if (mesh) this.strokeNodes(layer, layer.meshLines, ink, layer.coarse ? 1 : 0.6, 0.3);
    if (allEdges) this.strokeNodes(layer, layer.edgeLines, brandColour("teal"), 0.5, 0.3);
    const radius = (layer.coarse ? 3.2 : 1.7) * Math.min(Math.sqrt(this.zoom), 1.6);
    this.dots(layer, layer.usable, radius, brandColour("teal"));
    if (unusable) this.dots(layer, layer.unusable, radius, brandColour("mid"));
    if (folds) {
      this.strokeNodes(layer, layer.rowFolds, brandColour("rust"), layer.coarse ? 3 : 2.2);
      this.strokeNodes(layer, layer.backwardEdges, brandColour("rust"), 1.4);
    }
  }

  /** Fill a dot of `radius` [px] at each of the `nodes` of `layer` on the near side, as one path. */
  private dots({ screen: { x, y, facing } }: GridLayer, nodes: number[], radius: number, colour: string) {
    const context = this.context;
    context.beginPath();
    for (const node of nodes) {
      if (facing[node] <= 0) continue;
      context.moveTo(x[node], y[node]);
      context.lineTo(x[node], y[node]);
    }
    context.lineCap = "round";
    this.stroke(colour, 2 * radius);
    context.lineCap = "butt";
  }

  /** The stage lines across the corridor and the row lines along it. */
  private meshLines(grid: Grid) {
    const lines: number[][] = [];
    for (let stage = 0; stage < grid.stages; stage++)
      lines.push(Array.from({ length: grid.laterals }, (_, lateral) => stage * grid.laterals + lateral));
    for (let lateral = 0; lateral < grid.laterals; lateral++)
      lines.push(Array.from({ length: grid.stages }, (_, stage) => stage * grid.laterals + lateral));
    return lines;
  }

  /** Steps of the row lines between usable nodes that run backwards. */
  private rowFoldLines(grid: Grid) {
    const lines: number[][] = [];
    for (let node = 0; node + grid.laterals < grid.kind.length; node++)
      if (grid.row_backward[node] && kindOf(grid, node) !== "x" && kindOf(grid, node + grid.laterals) !== "x")
        lines.push([node, node + grid.laterals]);
    return lines;
  }

  private drawPicked({ spacing, node, routes }: PickedNode) {
    const layer = this.layers.find((each) => each.spacing === spacing);
    if (!layer) return;
    const orange = brandColour("orange");
    this.strokeNodes(layer, edgeLines(routes.edges), orange, 1, 0.55);
    this.strokeNodes(layer, edgeLines(edgesFrom(layer.grid, node)), orange, 3);
    const { x, y, facing } = layer.screen;
    if (facing[node] <= 0) return;
    this.context.beginPath();
    this.context.arc(x[node], y[node], 7, 0, 2 * Math.PI);
    this.stroke(brandColour("rust"), 2.5);
  }

  /** The shown node nearest the canvas position `x`, `y` [px], within the pick radius. */
  private nodeAt(x: number, y: number) {
    let best: GridNode | undefined;
    let nearest = pickRadius;
    this.place();
    for (const layer of this.layers) this.project(layer);
    for (const { spacing, grid, screen } of this.layers)
      for (let node = 0; node < grid.kind.length; node++) {
        if ((kindOf(grid, node) === "x" && !this.view.unusable) || screen.facing[node] <= 0) continue;
        const distance = Math.hypot(screen.x[node] - x, screen.y[node] - y);
        if (distance < nearest) {
          nearest = distance;
          best = { spacing, node };
        }
      }
    return best;
  }

  private pointerDown = (event: PointerEvent) => {
    this.drag = { x: event.clientX, y: event.clientY, facing: this.facing, moved: false };
    this.canvas.setPointerCapture(event.pointerId);
  };

  private pointerMove = (event: PointerEvent) => {
    if (!this.drag) return;
    const dx = event.clientX - this.drag.x;
    const dy = event.clientY - this.drag.y;
    if (Math.hypot(dx, dy) > 3) this.drag.moved = true;
    if (this.drag.moved) this.moving();
    const sensitivity = (this.view.flat ? 360 / this.width : 0.25) / this.zoom;
    const [lon, lat] = this.drag.facing;
    this.centre([lon - dx * sensitivity, Math.max(-90, Math.min(90, lat + dy * sensitivity))]);
  };

  private pointerUp = (event: PointerEvent) => {
    if (this.drag && !this.drag.moved) {
      const box = this.canvas.getBoundingClientRect();
      this.onPick(this.nodeAt(event.clientX - box.left, event.clientY - box.top));
    }
    if (this.drag?.moved) this.settled();
    this.drag = undefined;
  };

  private wheel = (event: WheelEvent) => {
    event.preventDefault();
    this.moving(settleDelay);
    this.zoomBy(Math.exp(-event.deltaY * 0.0015));
  };
}
