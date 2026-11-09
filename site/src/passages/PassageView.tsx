// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useMemo, useRef, useState } from "react";
import { GlobeScene } from "./Globe";
import { Panels } from "./Panels";
import { ShipScene } from "./ShipScene";
import {
  findLeg,
  loadJson,
  RIG_COLOURS,
  RIG_LABELS,
  stateAt,
  Timeline,
  type Leg,
  type PassageDesign,
  type PassageIndex,
  type PassageState,
  type RoutePassages,
  type RouteWinds,
} from "./passages";

const rigOrder: PassageDesign["rig"][] = ["none", "kite", "wings", "rotors"];

/** Routed passages on a globe, with the ship and its rig, on one time cursor. */
export function PassageView() {
  const [index, setIndex] = useState<PassageIndex>();
  useEffect(() => {
    loadJson<PassageIndex>("passages.json").then(setIndex).catch(() => undefined);
  }, []);
  if (!index) return null;
  return <Passages index={index} />;
}

function Passages({ index }: { index: PassageIndex }) {
  const [route, setRoute] = useState(0);
  const [rig, setRig] = useState<PassageDesign["rig"]>("kite");
  const [size, setSize] = useState(0);
  const [departure, setDeparture] = useState(0);
  const [direction, setDirection] = useState<Leg["direction"]>("out");
  const [passages, setPassages] = useState<RoutePassages>();
  const [winds, setWinds] = useState<RouteWinds>();
  const [playing, setPlaying] = useState(false);
  const [deckView, setDeckView] = useState(false);
  const timeline = useRef(new Timeline()).current;

  useEffect(() => {
    const name = index.routes[route].name;
    setPassages(undefined);
    loadJson<RoutePassages>(`passages-${name}.json`).then(setPassages).catch(() => undefined);
    loadJson<RouteWinds>(`winds-${name}.json`).then(setWinds).catch(() => setWinds(undefined));
  }, [index, route]);

  const designs = useMemo(() => index.designs.map((design, k) => ({ ...design, index: k })), [index]);
  const sizes = designs.filter((design) => design.rig === rig);
  const design = sizes[Math.min(size, sizes.length - 1)];
  const baselineDesign = designs.find((candidate) => candidate.rig === "none");
  const leg = passages && design ? findLeg(passages, design.index, direction, departure) : undefined;
  const unsailed = passages !== undefined && !leg;
  const baseline = passages && baselineDesign && rig !== "none" ? findLeg(passages, baselineDesign.index, direction, departure) : undefined;
  const field = winds?.winds[departure] ?? undefined;

  useEffect(() => {
    timeline.duration = leg ? leg.duration : 1;
    timeline.set(0);
  }, [leg, timeline]);

  return (
    <section className="space-y-6" aria-label="Routed passages">
      <header className="flex items-center gap-4">
        <span className="label">The routes</span>
        <span className="rule flex-1" />
      </header>
      <p className="max-w-3xl">
        Each passage is the one the router found for this ship and rig, with its speed, thrust, fuel power and the
        rig's trim recorded at every point it sailed. Drag the time cursor or press play.
      </p>
      <div className="grid gap-4 md:grid-cols-[minmax(0,2fr)_minmax(0,3fr)]">
        <div className="space-y-4">
          <div className="panel space-y-3">
            <Select label="Route from Rotterdam to" value={route} onChange={setRoute}
              options={index.routes.map((entry, k) => [k, entry.label])} />
            <div className="flex flex-wrap gap-2" role="radiogroup" aria-label="Rig">
              {rigOrder.filter((name) => designs.some((entry) => entry.rig === name)).map((name) => (
                <button key={name} role="radio" aria-checked={rig === name}
                  className={rig === name ? "button" : "button-outline"}
                  onClick={() => { setRig(name); setSize(0); }}>{RIG_LABELS[name]}</button>
              ))}
            </div>
            {rig !== "none" && (
              <Stepper label={`${RIG_LABELS[rig]} area`} value={design ? `${design.area.toLocaleString("en")} m²` : "–"}
                index={Math.min(size, sizes.length - 1)} last={sizes.length - 1} onChange={setSize} />
            )}
            <Stepper label="Departure" value={index.departures[departure].label}
              index={departure} last={index.departures.length - 1} onChange={setDeparture} />
            <Select label="Direction" value={direction} onChange={(value) => setDirection(value as Leg["direction"])}
              options={[["out", `Rotterdam → ${index.routes[route].label}`], ["back", `${index.routes[route].label} → Rotterdam`]]} />
            <Transport timeline={timeline} playing={playing} setPlaying={setPlaying} leg={leg} />
          </div>
          {!passages && <p>Loading the routed passages…</p>}
          {unsailed && <p>This ship could not sail this route at this departure.</p>}
          {leg && design && <ReadOut leg={leg} design={design} timeline={timeline} />}
        </div>
        <div className="space-y-4">
          <div className="grid gap-4 lg:grid-cols-2">
            <SceneFrame title="Passage" aspect="aspect-square" unsailed={unsailed}>
              <GlobeCanvas leg={leg} baseline={baseline} colour={RIG_COLOURS[rig]} field={field} timeline={timeline} />
            </SceneFrame>
            <SceneFrame title="Ship and rig" aspect="aspect-square" unsailed={unsailed}
              action={rig === "kite" && !unsailed ? <button className="button-outline" onClick={() => setDeckView(!deckView)}>{deckView ? "Whole kite" : "On deck"}</button> : undefined}>
              {design && <ShipCanvas design={design} deckView={deckView} leg={leg} timeline={timeline} />}
            </SceneFrame>
          </div>
          {leg && <div className="panel"><Panels leg={leg} baseline={baseline} colour={RIG_COLOURS[rig]} timeline={timeline} /></div>}
        </div>
      </div>
    </section>
  );
}

function Select({ label, value, options, onChange }: { label: string; value: string | number; options: [string | number, string][]; onChange: (value: never) => void }) {
  return (
    <label className="grid gap-1">
      <span className="label">{label}</span>
      <select className="rounded-[14px] border-2 border-ink bg-paper px-3 py-1.5" value={value}
        onChange={(event) => { const raw = event.target.value; const numeric = Number(raw); onChange((Number.isNaN(numeric) ? raw : numeric) as never); }}>
        {options.map(([key, text]) => <option key={key} value={key}>{text}</option>)}
      </select>
    </label>
  );
}

function Stepper({ label, value, index, last, onChange }: { label: string; value: string; index: number; last: number; onChange: (value: number) => void }) {
  return (
    <label className="grid gap-1">
      <span className="label">{label}</span>
      <input className="slider" type="range" min={0} max={last} step={1} value={index} onChange={(event) => onChange(Number(event.target.value))} />
      <span className="font-mono text-sm">{value}</span>
    </label>
  );
}

function Transport({ timeline, playing, setPlaying, leg }: { timeline: Timeline; playing: boolean; setPlaying: (value: boolean) => void; leg: Leg | undefined }) {
  const [hours, setHours] = useState(0);
  const [rate, setRate] = useState(timeline.rate);
  useEffect(() => { const stop = timeline.subscribe(() => setHours(timeline.hours)); return () => { stop(); }; }, [timeline]);
  useEffect(() => {
    timeline.playing = playing;
  }, [playing, timeline]);
  const day = Math.floor(hours / 24);
  return (
    <div className="grid gap-1">
      <span className="label">Time</span>
      <input className="slider" type="range" min={0} max={leg ? leg.duration : 1} step={1} value={hours} disabled={!leg}
        onChange={(event) => timeline.set(Number(event.target.value))} />
      <div className="flex items-center justify-between gap-3">
        <button className="button" disabled={!leg} onClick={() => setPlaying(!playing)}>{playing ? "Pause" : "Play"}</button>
        <span className="font-mono text-sm">day {day}, {Math.floor(hours - day * 24)} h</span>
        <button className="button-outline" onClick={() => { timeline.rate = timeline.rate === 8 ? 24 : timeline.rate === 24 ? 2 : 8; setRate(timeline.rate); }}>{rate} h/s</button>
      </div>
    </div>
  );
}

function SceneFrame({ title, aspect, unsailed, action, children }: { title: string; aspect: string; unsailed: boolean; action?: React.ReactNode; children: React.ReactNode }) {
  return (
    <div className="panel relative overflow-hidden p-0">
      <div className="absolute left-3 top-2 z-10 flex items-center gap-3">
        <span className="label rounded bg-paper px-1">{title}</span>
        {action}
      </div>
      <div className={`${aspect} w-full ${unsailed ? "invisible" : ""}`}>{children}</div>
    </div>
  );
}

function GlobeCanvas({ leg, baseline, colour, field, timeline }: { leg?: Leg; baseline?: Leg; colour: string; field?: RouteWinds["winds"][number]; timeline: Timeline }) {
  const host = useRef<HTMLDivElement>(null);
  const scene = useRef<GlobeScene>(undefined);
  useEffect(() => {
    scene.current = new GlobeScene(host.current!);
    const observer = new ResizeObserver(() => scene.current?.resize());
    observer.observe(host.current!);
    return () => { observer.disconnect(); scene.current?.dispose(); scene.current = undefined; };
  }, []);
  useEffect(() => {
    if (!leg) return;
    const resolved = getComputedStyle(document.documentElement).getPropertyValue(colour.replace(/var\((.*)\)/, "$1")).trim() || colour;
    scene.current?.showLeg(leg, baseline, resolved);
    update();
  }, [leg, baseline, colour]);
  useEffect(() => { scene.current?.showWinds(field ?? undefined); update(); }, [field]);
  useEffect(() => {
    let frame = 0;
    const loop = () => { scene.current?.render(); frame = requestAnimationFrame(loop); };
    loop();
    const stop = timeline.subscribe(update);
    return () => { cancelAnimationFrame(frame); stop(); };
  }, [timeline, leg]);
  function update() {
    if (!leg || !scene.current) return;
    const state = stateAt(leg, timeline.hours);
    scene.current.update(state, leg.start + state.hours);
  }
  return <div ref={host} className="h-full w-full" />;
}

function ShipCanvas({ design, deckView, leg, timeline }: { design: PassageDesign; deckView: boolean; leg?: Leg; timeline: Timeline }) {
  const host = useRef<HTMLDivElement>(null);
  const scene = useRef<ShipScene>(undefined);
  useEffect(() => {
    scene.current = new ShipScene(host.current!);
    const observer = new ResizeObserver(() => scene.current?.resize());
    observer.observe(host.current!);
    return () => { observer.disconnect(); scene.current?.dispose(); scene.current = undefined; };
  }, []);
  useEffect(() => { scene.current?.showDesign(design, deckView); }, [design, deckView]);
  useEffect(() => {
    let frame = 0;
    let previous = performance.now();
    const loop = (now: number) => {
      const dt = Math.min((now - previous) / 1000, 0.1);
      previous = now;
      if (timeline.playing && leg) timeline.set(timeline.hours + dt * timeline.rate);
      if (leg && timeline.hours >= leg.duration) timeline.playing = false;
      if (leg && scene.current) scene.current.update(stateAt(leg, timeline.hours), dt);
      scene.current?.render();
      frame = requestAnimationFrame(loop);
    };
    frame = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(frame);
  }, [timeline, leg]);
  return <div ref={host} className="h-full w-full" />;
}

function ReadOut({ leg, design, timeline }: { leg: Leg; design: PassageDesign; timeline: Timeline }) {
  const [state, setState] = useState<PassageState>(() => stateAt(leg, timeline.hours));
  useEffect(() => {
    let timer = 0;
    const refresh = () => { timer = window.setTimeout(() => { setState(stateAt(leg, timeline.hours)); timer = 0; }, 120); };
    setState(stateAt(leg, timeline.hours));
    const stop = timeline.subscribe(() => { if (!timer) refresh(); });
    return () => { stop(); clearTimeout(timer); };
  }, [leg, timeline]);
  const wind = Math.hypot(state.windEast, state.windNorth);
  const rows: [string, string][] = [
    ["Position", `${state.lat.toFixed(1)}°, ${state.lon.toFixed(1)}°`],
    ["Speed", `${state.speed.toFixed(1)} kn`],
    ["Wind at 10 m", `${wind.toFixed(1)} m/s`],
    ["Rig thrust", `${state.thrust.toFixed(0)} kN`],
    ["Fuel power", `${state.power.toFixed(1)} MW`],
  ];
  if (design.rig === "wings") rows.push(["Sail chord", `${state.chord?.toFixed(0)}° off the bow, lift ${state.lift?.toFixed(2)}`]);
  if (design.rig === "rotors") rows.push(["Spin ratio", `${Math.abs(state.spin ?? 0).toFixed(2)}`]);
  if (design.rig === "kite") rows.push(["Kite", state.flying ? (state.pattern ? `flying, pattern ${state.pattern.period.toFixed(0)} s` : "flying") : "stowed"]);
  return (
    <dl className="panel grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
      {rows.map(([name, value]) => (
        <div key={name} className="contents">
          <dt>{name}</dt>
          <dd className="text-right font-mono">{value}</dd>
        </div>
      ))}
    </dl>
  );
}
