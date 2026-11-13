// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

import { geoDistance, geoGraticule10, geoOrthographic, geoPath, type GeoPath } from "d3-geo";
import { feature } from "topojson-client";
import land from "world-atlas/land-110m.json";
import { brandColour } from "../passages/scene";
import { edgesFrom, gridEdges, kindOf, position, type Edge, type Grid, type RoutesThrough } from "./grid";

/** One grid on the globe, coarse grids drawn with larger nodes. */
export interface ShownGrid {
  spacing: string;
  grid: Grid;
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

/** What the globe draws. */
export interface GridView {
  grids: ShownGrid[];
  mesh: boolean;
  unusable: boolean;
  allEdges: boolean;
  folds: boolean;
  picked?: PickedNode;
}

const topology = land as unknown as Parameters<typeof feature>[0] & { objects: { land: never } };
const landShape = feature(topology, topology.objects.land) as unknown as GeoJSON.FeatureCollection;
const pickRadius = 12;

/** An orthographic globe on a canvas drawing router grids; drag turns it, the wheel zooms, a click picks a node. */
export class GridGlobe {
  private context: CanvasRenderingContext2D;
  private projection = geoOrthographic().rotate([40, -35]).clipAngle(90).precision(0.3);
  private path: GeoPath;
  private zoom = 1;
  private width = 0;
  private height = 0;
  private view: GridView = { grids: [], mesh: true, unusable: true, allEdges: false, folds: true };
  private drag?: { x: number; y: number; rotate: [number, number, number]; moved: boolean };
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
    this.draw();
  }

  /** Turn the globe to face longitude and latitude `[lon, lat]` [deg], at `zoom` if given. */
  centre([lon, lat]: [number, number], zoom?: number) {
    this.projection.rotate([-lon, -lat]);
    if (zoom) this.zoom = zoom;
    this.draw();
  }

  zoomBy(factor: number) {
    this.zoom = Math.max(0.8, Math.min(16, this.zoom * factor));
    this.draw();
  }

  dispose() {
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
    this.draw();
  }

  private visible(point: [number, number]) {
    const [lambda, phi] = this.projection.rotate();
    return geoDistance(point, [-lambda, -phi]) < Math.PI / 2;
  }

  private stroke(lines: [number, number][][], colour: string, width: number, alpha = 1) {
    const context = this.context;
    context.beginPath();
    this.path({ type: "MultiLineString", coordinates: lines });
    context.globalAlpha = alpha;
    context.strokeStyle = colour;
    context.lineWidth = width;
    context.stroke();
    context.globalAlpha = 1;
  }

  private edgeLines(grid: Grid, edges: Edge[]) {
    return edges.map((edge) => [position(grid, edge.from), position(grid, edge.to)]);
  }

  private draw() {
    if (!this.width) return;
    const context = this.context;
    this.projection.scale((Math.min(this.width, this.height) / 2 - 8) * this.zoom).translate([this.width / 2, this.height / 2]);
    context.clearRect(0, 0, this.width, this.height);
    context.beginPath();
    this.path({ type: "Sphere" });
    context.fillStyle = brandColour("sky");
    context.fill();
    this.stroke(geoGraticule10().coordinates as [number, number][][], brandColour("ink"), 0.5, 0.15);
    context.beginPath();
    this.path(landShape);
    context.fillStyle = brandColour("paper-deep");
    context.fill();
    context.strokeStyle = brandColour("ink");
    context.lineWidth = 0.6;
    context.stroke();
    for (const shown of this.view.grids) this.drawGrid(shown);
    if (this.view.picked) this.drawPicked(this.view.picked);
  }

  private drawGrid({ grid, coarse }: ShownGrid) {
    const { mesh, unusable, allEdges, folds } = this.view;
    const ink = brandColour("ink");
    if (mesh) this.stroke(this.meshLines(grid), ink, coarse ? 1 : 0.6, 0.3);
    const edges = allEdges || folds ? gridEdges(grid) : [];
    if (allEdges) this.stroke(this.edgeLines(grid, edges), brandColour("teal"), 0.5, 0.3);
    const radius = (coarse ? 3.2 : 1.7) * Math.min(Math.sqrt(this.zoom), 1.6);
    const colours = { w: brandColour("teal"), c: brandColour("mustard"), x: brandColour("mid") };
    for (let node = 0; node < grid.kind.length; node++) {
      const kind = kindOf(grid, node);
      if (kind === "x" && !unusable) continue;
      const point = position(grid, node);
      if (!this.visible(point)) continue;
      const [x, y] = this.projection(point)!;
      this.context.beginPath();
      this.context.arc(x, y, radius, 0, 2 * Math.PI);
      this.context.fillStyle = colours[kind];
      this.context.fill();
    }
    if (folds) {
      this.stroke(this.rowFoldLines(grid), brandColour("rust"), coarse ? 3 : 2.2);
      this.stroke(this.edgeLines(grid, edges.filter((edge) => edge.backward)), brandColour("rust"), 1.4);
    }
  }

  /** The stage lines across the corridor and the row lines along it. */
  private meshLines(grid: Grid) {
    const lines: [number, number][][] = [];
    for (let stage = 0; stage < grid.stages; stage++)
      lines.push(Array.from({ length: grid.laterals }, (_, lateral) => position(grid, stage * grid.laterals + lateral)));
    for (let lateral = 0; lateral < grid.laterals; lateral++)
      lines.push(Array.from({ length: grid.stages }, (_, stage) => position(grid, stage * grid.laterals + lateral)));
    return lines;
  }

  /** Steps of the row lines between usable nodes that run backwards. */
  private rowFoldLines(grid: Grid) {
    const lines: [number, number][][] = [];
    for (let node = 0; node + grid.laterals < grid.kind.length; node++)
      if (grid.row_backward[node] && kindOf(grid, node) !== "x" && kindOf(grid, node + grid.laterals) !== "x")
        lines.push([position(grid, node), position(grid, node + grid.laterals)]);
    return lines;
  }

  private drawPicked({ spacing, node, routes }: PickedNode) {
    const shown = this.view.grids.find((each) => each.spacing === spacing);
    if (!shown) return;
    const orange = brandColour("orange");
    this.stroke(this.edgeLines(shown.grid, routes.edges), orange, 1, 0.55);
    this.stroke(this.edgeLines(shown.grid, edgesFrom(shown.grid, node)), orange, 3);
    const point = position(shown.grid, node);
    if (!this.visible(point)) return;
    const [x, y] = this.projection(point)!;
    this.context.beginPath();
    this.context.arc(x, y, 7, 0, 2 * Math.PI);
    this.context.strokeStyle = brandColour("rust");
    this.context.lineWidth = 2.5;
    this.context.stroke();
  }

  private nodeAt(x: number, y: number) {
    let best: GridNode | undefined;
    let nearest = pickRadius;
    for (const { spacing, grid } of this.view.grids)
      for (let node = 0; node < grid.kind.length; node++) {
        const point = position(grid, node);
        if ((kindOf(grid, node) === "x" && !this.view.unusable) || !this.visible(point)) continue;
        const [px, py] = this.projection(point)!;
        const distance = Math.hypot(px - x, py - y);
        if (distance < nearest) {
          nearest = distance;
          best = { spacing, node };
        }
      }
    return best;
  }

  private pointerDown = (event: PointerEvent) => {
    this.drag = { x: event.clientX, y: event.clientY, rotate: this.projection.rotate(), moved: false };
    this.canvas.setPointerCapture(event.pointerId);
  };

  private pointerMove = (event: PointerEvent) => {
    if (!this.drag) return;
    const dx = event.clientX - this.drag.x;
    const dy = event.clientY - this.drag.y;
    if (Math.hypot(dx, dy) > 3) this.drag.moved = true;
    const sensitivity = 0.25 / this.zoom;
    const [lambda, phi] = this.drag.rotate;
    this.projection.rotate([lambda + dx * sensitivity, Math.max(-90, Math.min(90, phi - dy * sensitivity))]);
    this.draw();
  };

  private pointerUp = (event: PointerEvent) => {
    if (this.drag && !this.drag.moved) {
      const box = this.canvas.getBoundingClientRect();
      this.onPick(this.nodeAt(event.clientX - box.left, event.clientY - box.top));
    }
    this.drag = undefined;
  };

  private wheel = (event: WheelEvent) => {
    event.preventDefault();
    this.zoomBy(Math.exp(-event.deltaY * 0.0015));
  };
}
