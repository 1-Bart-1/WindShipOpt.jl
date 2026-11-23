// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { gridsPath } from "../../data";
import { geoOrthographic } from "d3-geo";
import {
  edgesFrom,
  faceGlobe,
  foldCentre,
  formatCount,
  gridCounts,
  gridEdges,
  horizon,
  routesThrough,
  screenPoints,
  unitVectors,
  type Grid,
  type GridData,
} from "./grid";

// Three stages of three rows: one start node, a fan, and the port in the middle of the last stage.
const grid: Grid = {
  stages: 3,
  laterals: 3,
  reach: 1,
  stage_spacing: 90,
  lateral_spacing: 60,
  lat: [0, 0, 0, 100, 100, 100, 200, 200, 200],
  lon: [-100, 0, 100, -100, 0, 100, -100, 0, 100],
  kind: "xwxwwwxwx",
  edges: [0, 0b111, 0, 0b100, 0b010, 0b001, 0, 0, 0],
  backward: [0, 0b100, 0, 0, 0, 0, 0, 0, 0],
  row_backward: [0, 0, 0, 0, 1, 1, 0, 0, 0],
};

describe("the grid page", () => {
  it("reads each edge bit as a step of rows to the next stage", () => {
    expect(edgesFrom(grid, 1).map((edge) => edge.to)).toEqual([3, 4, 5]);
    expect(edgesFrom(grid, 3)).toEqual([{ from: 3, to: 7, backward: false }]);
    expect(edgesFrom(grid, 5).map((edge) => edge.to)).toEqual([7]);
    expect(edgesFrom(grid, 1).filter((edge) => edge.backward).map((edge) => edge.to)).toEqual([5]);
  });

  it("counts the routes through a node and finds every edge on them", () => {
    expect(routesThrough(grid, 1).count).toBe(3);
    const through = routesThrough(grid, 3);
    expect(through.count).toBe(1);
    expect(through.edges.map((edge) => [edge.from, edge.to])).toEqual([[1, 3], [3, 7]]);
    expect(routesThrough(grid, 0).count).toBe(0);
  });

  it("counts nodes, edges and backward steps", () => {
    expect(gridCounts(grid)).toEqual({ usable: 5, unusable: 4, edges: 6, backwardEdges: 1, backwardRowSteps: 1 });
    expect(foldCentre(grid, gridEdges(grid))).toEqual([0.5, 0.5]);
  });

  it("writes huge route counts in powers of ten", () => {
    expect(formatCount(0)).toBe("No");
    expect(formatCount(12345)).toBe("12,345");
    expect(formatCount(3.2e41)).toBe("3.2 × 10^41");
  });

  const globeFacing = ([lon, lat]: [number, number]) => geoOrthographic().rotate([-lon, -lat]).scale(100).translate([400, 300]);

  it("shows a node facing the viewer at the globe's centre and a node a quarter turn east at its right edge", () => {
    const nodes: Grid = { ...grid, lon: [-4000, 5000, 14000], lat: [3000, 0, 0], kind: "www" };
    const screen = screenPoints(3);
    faceGlobe(unitVectors(nodes), globeFacing([-40, 30]), screen);
    expect(screen.x[0]).toBeCloseTo(400);
    expect(screen.y[0]).toBeCloseTo(300);
    expect(screen.facing[0]).toBeCloseTo(1);
    faceGlobe(unitVectors(nodes), globeFacing([-40, 0]), screen);
    expect([screen.x[1], screen.y[1], screen.facing[1]].map((value) => +value.toFixed(9))).toEqual([500, 300, 0]);
    expect(screen.facing[2]).toBeLessThan(0);
  });

  it("cuts a line passing behind the globe where its great circle meets the globe's edge", () => {
    // Two points of the great circle through 0° 45° N and 90° E 0°, which meets the edge at 90° E 0°.
    const nodes: Grid = { ...grid, lon: [8289, 10443], lat: [705, -1400], kind: "ww" };
    const globe = globeFacing([0, 0]);
    const screen = screenPoints(2);
    faceGlobe(unitVectors(nodes), globe, screen);
    const [x, y] = horizon(screen, 0, 1, globe);
    expect(x).toBeCloseTo(500, 1);
    expect(y).toBeCloseTo(300, 1);
  });

  const path = gridsPath();
  it.runIf(path)("lead every exported edge to a usable node of the next stage, and every start to the port", () => {
    const data: GridData = JSON.parse(readFileSync(path!, "utf8"));
    const astray: string[] = [];
    for (const spacing of data.spacings)
      for (const route of data.routes) {
        const each = data.grids[spacing][route.name];
        for (let node = 0; node < each.kind.length; node++)
          for (const edge of edgesFrom(each, node))
            if (Math.floor(edge.to / each.laterals) !== Math.floor(node / each.laterals) + 1 || each.kind[edge.to] === "x")
              astray.push(`${spacing} ${route.name} ${node}→${edge.to}`);
        expect(routesThrough(each, (each.laterals - 1) / 2).count).toBeGreaterThan(0);
      }
    expect(astray).toEqual([]);
  });
});
