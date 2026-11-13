// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

/**
 * One outbound corridor of grids.json. Nodes run stage after stage, `laterals` per stage;
 * bit k of `edges` is the edge to row `lateral + k - reach` of the next stage, and of
 * `backward` that edge running more than 90° off the course of the centre line.
 */
export interface Grid {
  stages: number;
  laterals: number;
  reach: number;
  stage_spacing: number;
  lateral_spacing: number;
  lat: number[];
  lon: number[];
  kind: string;
  edges: number[];
  backward: number[];
  row_backward: number[];
}

/** grids.json: the grid of every route at each spacing, keyed by spacing and route name. */
export interface GridData {
  git_commit: string;
  weather: string;
  routes: { name: string; label: string }[];
  spacings: string[];
  grids: Record<string, Record<string, Grid>>;
}

/** Open water, water near the coast, or unusable. */
export type NodeKind = "w" | "c" | "x";

/** An edge from node `from` to node `to` of the next stage. */
export interface Edge {
  from: number;
  to: number;
  backward: boolean;
}

/** Longitude and latitude [deg] of `node`. */
export const position = (grid: Grid, node: number): [number, number] => [grid.lon[node] / 100, grid.lat[node] / 100];

/** The kind of `node`. */
export const kindOf = (grid: Grid, node: number) => grid.kind[node] as NodeKind;

/** The edges the router may take from `node` to the next stage. */
export function edgesFrom(grid: Grid, node: number): Edge[] {
  const result: Edge[] = [];
  for (let step = 0; step <= 2 * grid.reach; step++) {
    if (!(grid.edges[node] & (1 << step))) continue;
    const to = node + grid.laterals + step - grid.reach;
    result.push({ from: node, to, backward: (grid.backward[node] & (1 << step)) !== 0 });
  }
  return result;
}

/** Every edge of `grid`. */
export const gridEdges = (grid: Grid): Edge[] => grid.edges.flatMap((_, node) => edgesFrom(grid, node));

/** Number of paths from each node with `seed` to every node downstream, over the stages from `first` to `last`. */
function pathsForward(grid: Grid, seed: (node: number) => boolean, first: number, last: number): Float64Array {
  const counts = new Float64Array(grid.kind.length);
  for (let node = first * grid.laterals; node < (first + 1) * grid.laterals; node++) if (seed(node)) counts[node] = 1;
  for (let node = first * grid.laterals; node < last * grid.laterals; node++) {
    if (!counts[node]) continue;
    for (const edge of edgesFrom(grid, node)) counts[edge.to] += counts[node];
  }
  return counts;
}

/** Number of paths from every node upstream to the nodes with `seed`, over the stages from `first` to `last`. */
function pathsBackward(grid: Grid, seed: (node: number) => boolean, first: number, last: number): Float64Array {
  const counts = new Float64Array(grid.kind.length);
  for (let node = last * grid.laterals; node < (last + 1) * grid.laterals; node++) if (seed(node)) counts[node] = 1;
  for (let node = last * grid.laterals - 1; node >= first * grid.laterals; node--)
    for (const edge of edgesFrom(grid, node)) counts[node] += counts[edge.to];
  return counts;
}

export interface RoutesThrough {
  /** Number of routes from the first stage to the port that pass through the node. */
  count: number;
  /** Every edge on at least one of them. */
  edges: Edge[];
}

/** The routes from the start of `grid` to its port through `node`. */
export function routesThrough(grid: Grid, node: number): RoutesThrough {
  const stage = Math.floor(node / grid.laterals);
  const last = grid.stages - 1;
  const usable = (each: number) => kindOf(grid, each) !== "x";
  const fromStart = pathsForward(grid, usable, 0, stage);
  const toNode = pathsBackward(grid, (each) => each === node, 0, stage);
  const fromNode = pathsForward(grid, (each) => each === node, stage, last);
  const toPort = pathsBackward(grid, usable, stage, last);
  const edges: Edge[] = [];
  const firstOfStage = stage * grid.laterals;
  for (let each = 0; each < last * grid.laterals; each++) {
    const before = each < firstOfStage && fromStart[each] > 0;
    const after = each >= firstOfStage && fromNode[each] > 0;
    if (!before && !after) continue;
    for (const edge of edgesFrom(grid, each)) if (before ? toNode[edge.to] > 0 : toPort[edge.to] > 0) edges.push(edge);
  }
  return { count: fromStart[node] * toPort[node], edges };
}

export interface GridCounts {
  usable: number;
  nearCoast: number;
  unusable: number;
  edges: number;
  backwardEdges: number;
  backwardRowSteps: number;
}

/** Node and edge counts of `grid`; row steps count only between usable nodes. */
export function gridCounts(grid: Grid): GridCounts {
  const counts = { usable: 0, nearCoast: 0, unusable: 0, edges: 0, backwardEdges: 0, backwardRowSteps: 0 };
  for (let node = 0; node < grid.kind.length; node++) {
    const kind = kindOf(grid, node);
    if (kind === "x") counts.unusable++;
    else counts.usable++;
    if (kind === "c") counts.nearCoast++;
    for (const edge of edgesFrom(grid, node)) {
      counts.edges++;
      if (edge.backward) counts.backwardEdges++;
    }
    const next = node + grid.laterals;
    if (grid.row_backward[node] && kind !== "x" && next < grid.kind.length && kindOf(grid, next) !== "x") counts.backwardRowSteps++;
  }
  return counts;
}

/** Longitude and latitude [deg] at the middle of the backward ones of `edges` of `grid`, or undefined if there are none. */
export function foldCentre(grid: Grid, edges: Edge[]): [number, number] | undefined {
  const ends = edges.filter((edge) => edge.backward).flatMap((edge) => [edge.from, edge.to]);
  if (ends.length === 0) return undefined;
  const mean = (values: number[]) => values.reduce((sum, value) => sum + value, 0) / values.length;
  return [mean(ends.map((node) => position(grid, node)[0])), mean(ends.map((node) => position(grid, node)[1]))];
}

/** `count` routes in words: a plain number below a million, else in powers of ten. */
export function formatCount(count: number): string {
  if (count === 0) return "No";
  if (count < 1e6) return Math.round(count).toLocaleString("en");
  const exponent = Math.floor(Math.log10(count));
  return `${(count / 10 ** exponent).toFixed(1)} × 10^${exponent}`;
}
