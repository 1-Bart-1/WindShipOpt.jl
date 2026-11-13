// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useMemo, useRef, useState } from "react";
import { loadJson } from "../passages/passages";
import { Select } from "../Select";
import { foldCentre, formatCount, gridCounts, kindOf, edgesFrom, position, routesThrough, type Grid, type GridData } from "./grid";
import { GridGlobe, type GridNode, type PickedNode, type ShownGrid } from "./GridGlobe";

type Shown = "final" | "draft" | "both";
type Layer = "mesh" | "unusable" | "allEdges" | "folds";

const layerLabels: [Layer, string][] = [
  ["folds", "Steps that run backwards"],
  ["mesh", "Stage and row lines"],
  ["unusable", "Unusable nodes"],
  ["allEdges", "Every edge"],
];

const degrees = (angle: number, positive: string, negative: string) =>
  `${Math.abs(angle).toFixed(2)}° ${angle < 0 ? negative : positive}`;

const kindLabels = { w: "open water", c: "water near the coast", x: "unusable" };

/** The router's corridor grids on a globe, from grids.json. */
export function GridPage() {
  const [data, setData] = useState<GridData>();
  const [error, setError] = useState<string>();
  useEffect(() => {
    loadJson<GridData>("grids.json").then(setData).catch((reason) => setError(String(reason)));
  }, []);
  if (error) return <p className="p-8 text-rust">Could not load the grids: {error}. Run paper(:grids; fidelity=:draft).</p>;
  if (!data) return <p className="p-8">Loading the grids…</p>;
  return <Grids data={data} />;
}

function Grids({ data }: { data: GridData }) {
  const [route, setRoute] = useState(data.routes[0].name);
  const [shown, setShown] = useState<Shown>("final");
  const [layers, setLayers] = useState<Record<Layer, boolean>>({ mesh: true, unusable: true, allEdges: false, folds: true });
  const [picked, setPicked] = useState<PickedNode>();
  const canvas = useRef<HTMLCanvasElement>(null);
  const [globe, setGlobe] = useState<GridGlobe>();
  const pickRoute = useRef(route);
  pickRoute.current = route;

  const grids: ShownGrid[] = useMemo(
    () =>
      data.spacings
        .filter((spacing) => shown === "both" || shown === spacing)
        .map((spacing) => ({ spacing, grid: data.grids[spacing][route], coarse: spacing === "draft" }))
        .sort((a, b) => Number(a.coarse) - Number(b.coarse)),
    [data, route, shown],
  );

  useEffect(() => {
    const created = new GridGlobe(canvas.current!, (node?: GridNode) =>
      setPicked(node && { ...node, routes: routesThrough(data.grids[node.spacing][pickRoute.current], node.node) }),
    );
    setGlobe(created);
    return () => created.dispose();
  }, [data]);

  useEffect(() => {
    const grid = data.grids.final[route];
    globe?.centre(position(grid, Math.floor(grid.kind.length / 2)), 1.4);
  }, [globe, data, route]);

  useEffect(() => globe?.show({ grids, ...layers, picked }), [globe, grids, layers, picked]);

  const fold = foldCentre(grids[0].grid);
  return (
    <main className="mx-auto max-w-[1400px] space-y-6 px-4 py-6 md:px-8">
      <header className="space-y-2">
        <a className="label" href="./">Wind ships explorer</a>
        <h1 className="text-4xl leading-[0.9] md:text-6xl">The router's grid</h1>
        <p className="max-w-3xl">
          The weather router searches each passage over a grid of stages along the route, each a row of nodes across
          it. An edge joins a node to nearby rows of the next stage. Drag to turn the globe, scroll to zoom, and click a
          node to see every route from Rotterdam to port through it.
        </p>
      </header>
      <div className="rule" />
      <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_340px]">
        <div className="relative">
          <canvas ref={canvas} className="aspect-square max-h-[calc(100vh-3rem)] w-full cursor-grab touch-none active:cursor-grabbing"
            aria-label="Globe with the router's corridor grid" />
          <div className="absolute right-2 top-2 flex flex-col gap-1">
            <button className="button-outline" aria-label="Zoom in" onClick={() => globe?.zoomBy(1.5)}>+</button>
            <button className="button-outline" aria-label="Zoom out" onClick={() => globe?.zoomBy(1 / 1.5)}>−</button>
          </div>
        </div>
        <aside className="space-y-5">
          <div className="panel space-y-4">
            <Select label="Outbound from Rotterdam to" value={route}
              onChange={(value: string) => { setRoute(value); setPicked(undefined); }}
              options={data.routes.map((entry) => [entry.name, entry.label])} />
            <div className="grid gap-1">
              <span className="label">Grid</span>
              <div className="flex flex-wrap gap-2" role="radiogroup" aria-label="Grid">
                {(["final", "draft", "both"] as Shown[]).map((name) => (
                  <button key={name} role="radio" aria-checked={shown === name} className={shown === name ? "button" : "button-outline"}
                    onClick={() => { setShown(name); setPicked(undefined); }}>
                    {name[0].toUpperCase() + name.slice(1)}
                  </button>
                ))}
              </div>
            </div>
            <div className="grid gap-1.5 text-sm">
              {layerLabels.map(([layer, text]) => (
                <label key={layer} className="flex cursor-pointer items-center gap-2">
                  <input type="checkbox" className="accent-ink" checked={layers[layer]}
                    onChange={(event) => setLayers({ ...layers, [layer]: event.target.checked })} />
                  {text}
                </label>
              ))}
            </div>
            <button className="button w-full disabled:opacity-40" disabled={!fold} onClick={() => fold && globe?.centre(fold, 4)}>
              {fold ? "Go to the steps that run backwards" : "No step runs backwards"}
            </button>
          </div>
          <Legend />
          <Counts data={data} route={route} />
          <Picked picked={picked} data={data} route={route} />
        </aside>
      </div>
      <p className="font-mono text-xs text-ink-light">
        Exported at commit {data.git_commit.slice(0, 7)}; land mask of the weather: {data.weather}.
      </p>
    </main>
  );
}

function Legend() {
  const swatch = (colour: string, round = true) => (
    <i className={`inline-block flex-none ${round ? "h-2.5 w-2.5 rounded-full" : "h-1 w-4"}`} style={{ background: `var(--brand-${colour})` }} />
  );
  return (
    <div className="grid gap-1 text-sm">
      <span className="flex items-center gap-2">{swatch("teal")}Open water</span>
      <span className="flex items-center gap-2">{swatch("mustard")}Water near the coast, where the router charges a penalty</span>
      <span className="flex items-center gap-2">{swatch("mid")}Unusable: land, or the port is out of reach</span>
      <span className="flex items-center gap-2">{swatch("rust", false)}An edge or row step more than 90° off the centre line's course</span>
      <span className="flex items-center gap-2">{swatch("orange", false)}Routes through the picked node; bold: its own edges</span>
    </div>
  );
}

function Counts({ data, route }: { data: GridData; route: string }) {
  const rows = data.spacings.map((spacing) => [spacing, data.grids[spacing][route]] as [string, Grid]);
  const counts = rows.map(([, grid]) => gridCounts(grid));
  const line = (label: string, values: (number | string)[]) => (
    <tr key={label}>
      <th className="py-0.5 pr-2 text-left font-normal">{label}</th>
      {values.map((value, k) => <td key={k} className="text-right">{typeof value === "number" ? value.toLocaleString("en") : value}</td>)}
    </tr>
  );
  return (
    <table className="w-full font-mono text-xs tabular-nums">
      <thead>
        <tr className="border-b border-ink">
          <th />
          {rows.map(([spacing]) => <th key={spacing} className="text-right font-semibold capitalize">{spacing}</th>)}
        </tr>
      </thead>
      <tbody>
        {line("Stage spacing [nmi]", rows.map(([, grid]) => grid.stage_spacing))}
        {line("Row spacing [nmi]", rows.map(([, grid]) => grid.lateral_spacing))}
        {line("Stages × rows", rows.map(([, grid]) => `${grid.stages} × ${grid.laterals}`))}
        {line("Usable nodes", counts.map((each) => each.usable))}
        {line("of them near the coast", counts.map((each) => each.nearCoast))}
        {line("Unusable nodes", counts.map((each) => each.unusable))}
        {line("Edges", counts.map((each) => each.edges))}
        {line("Edges run backwards", counts.map((each) => each.backwardEdges))}
        {line("Row steps run backwards", counts.map((each) => each.backwardRowSteps))}
      </tbody>
    </table>
  );
}

function Picked({ picked, data, route }: { picked?: PickedNode; data: GridData; route: string }) {
  if (!picked) return <p className="text-sm text-ink-light">Click a node on the globe.</p>;
  const grid = data.grids[picked.spacing][route];
  const stage = Math.floor(picked.node / grid.laterals);
  const row = (picked.node % grid.laterals) - (grid.laterals - 1) / 2;
  const [lon, lat] = position(grid, picked.node);
  const onward = edgesFrom(grid, picked.node);
  return (
    <div className="panel space-y-1 font-mono text-xs">
      <div className="label">Picked node</div>
      <div>{picked.spacing} grid, stage {stage + 1} of {grid.stages}, row {row > 0 ? "+" : ""}{row} from the centre line</div>
      <div>{degrees(lat, "N", "S")}, {degrees(lon, "E", "W")}, {kindLabels[kindOf(grid, picked.node)]}</div>
      <div>{onward.length} edges onward, {onward.filter((edge) => edge.backward).length} of them backwards</div>
      <div>{formatCount(picked.routes.count)} routes from Rotterdam to port pass here</div>
      <div>{picked.routes.edges.length.toLocaleString("en")} edges lie on one of them</div>
    </div>
  );
}
