// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useMemo, useState } from "react";
import {
  bestDesigns,
  bestRig,
  drives,
  evaluated,
  inputValues,
  outcomes,
  rigs,
  type ExplorerData,
  type Outcome,
} from "./explorer";
import { canopyPriceInputs, exactInputs, inputGroups, type InputControl } from "./inputs";
import { rigColour, RIG_LABELS, type PassageDesign } from "./passages/passages";
import { PassageView } from "./passages/PassageView";

const driveLabels: Record<string, string> = {
  vlsfo: "fuel oil (VLSFO)",
  ammonia: "e-ammonia",
};

const formatted = (value: number, digits = 1) =>
  Number.isFinite(value) ? value.toLocaleString("en", { maximumFractionDigits: digits }) : "–";

export default function App() {
  const [data, setData] = useState<ExplorerData>();
  const [error, setError] = useState<string>();
  useEffect(() => {
    fetch("explorer.json")
      .then((response) => response.json())
      .then(setData)
      .catch((reason) => setError(String(reason)));
  }, []);
  if (error) return <p className="p-8 text-rust">Could not load the explorer data: {error}</p>;
  if (!data) return <p className="p-8">Loading the model…</p>;
  return <Explorer data={data} />;
}

function Explorer({ data }: { data: ExplorerData }) {
  const [ship, setShip] = useState(0);
  const [route, setRoute] = useState(0);
  const [drive, setDrive] = useState<string>("ammonia");
  const [changes, setChanges] = useState<Record<string, number>>({});
  const [cargoFactor, setCargoFactor] = useState(1);
  const values = useMemo(
    () => evaluated(data, inputValues(data, changes, cargoFactor)),
    [data, changes, cargoFactor],
  );
  const all = useMemo(() => outcomes(data, values), [data, values]);
  const best = bestDesigns(all, ship, route, drive);
  const change = (name: string, value: number) => setChanges({ ...changes, [name]: value });
  const setCanopy = (suffix: string) =>
    setChanges({
      ...changes,
      ...Object.fromEntries(canopyPriceInputs.map((name) => [name, data.inputs[name + suffix].value])),
    });

  return (
    <main className="mx-auto max-w-[1120px] space-y-10 px-5 py-8 md:px-8">
      <header className="space-y-2">
        <h1 className="text-5xl md:text-7xl leading-[0.9]">Towing kites, wing sails and Flettner rotors on cargo ships</h1>
        <p className="text-ink">
          Pick a ship, a route and a fuel, change the inputs, and see what each rig saves at its best size.
          Results read: if each rig reaches these goals, it saves this much.
        </p>
        <a className="label" href="grid.html">The router's grid</a>
        {data.fidelity !== "final" && (
          <p className="rounded-[14px] bg-mustard/30 px-3 py-2 text-sm text-ink">
            Draft results ({data.fidelity} run, commit {data.git_commit.slice(0, 7)}): coarser routing than the
            paper's final numbers.
          </p>
        )}
      </header>

      <section className="flex flex-wrap gap-4">
        <Choice label="Ship" value={ship} onChange={setShip}
          options={data.classes.map((entry, k) => [k, `${entry.name} (${formatted(entry.deadweight, 0)} t)`])} />
        <Choice label="Route from Rotterdam to" value={route} onChange={setRoute}
          options={data.routes.map((entry, k) => [k, entry.label])} />
        <Choice label="Fuel" value={drive} onChange={setDrive}
          options={drives.map((name) => [name, driveLabels[name]])} />
      </section>

      <PassageView />

      <Results best={best} drive={drive} />

      <section className="grid gap-6 md:grid-cols-2">
        {inputGroups.map((group) => (
          <fieldset key={group.title} className="space-y-3 rounded-[14px] border-2 border-ink bg-paper p-5">
            <legend className="px-1 font-semibold">{group.title}</legend>
            {group.title === "Kite goals" && (
              <p className="text-sm text-ink">
                Canopy price {formatted(values[data.canopy_price.node], 0)} USD/m².{" "}
                <button className="underline" onClick={() => setCanopy("")}>Goal</button>{" · "}
                <button className="underline" onClick={() => setCanopy("_today")}>As built today</button>
              </p>
            )}
            {group.controls.map((control) => (
              <Slider key={control.name} control={control}
                value={changes[control.name] ?? data.inputs[control.name].value}
                base={data.inputs[control.name].value} onChange={(value) => change(control.name, value)} />
            ))}
            {group.title === "Money and time" && (
              <Slider
                control={{ name: "cargo", label: `Cargo value (base ${formatted(data.inputs[`cargo_value:${data.classes[ship].name}`].value, 0)} USD/t)`, unit: "% of base", scale: 100, min: 25, max: 400, step: 5 }}
                value={cargoFactor} base={1} onChange={setCargoFactor} />
            )}
          </fieldset>
        ))}
      </section>
      <button className="rounded-[14px] bg-ink px-3 py-1 text-white"
        onClick={() => { setChanges({}); setCargoFactor(1); }}>
        Back to the paper's inputs
      </button>

      <WinnerMap data={data} all={all} drive={drive} onPick={(k, j) => { setShip(k); setRoute(j); }} />
      <Accuracy data={data} />
    </main>
  );
}

function Choice<T extends string | number>(props: {
  label: string;
  value: T;
  onChange: (value: T) => void;
  options: [T, string][];
}) {
  return (
    <label className="flex flex-col text-sm">
      <span className="text-ink">{props.label}</span>
      <select className="rounded-[14px] border border-ink bg-paper px-2 py-1" value={String(props.value)}
        onChange={(event) => {
          const chosen = props.options.find(([value]) => String(value) === event.target.value);
          if (chosen) props.onChange(chosen[0]);
        }}>
        {props.options.map(([value, text]) => <option key={String(value)} value={String(value)}>{text}</option>)}
      </select>
    </label>
  );
}

function Slider(props: { control: InputControl; value: number; base: number; onChange: (value: number) => void }) {
  const { control } = props;
  const shown = props.value * control.scale;
  return (
    <label className="block text-sm">
      <span className="flex justify-between">
        <span>{control.label}</span>
        <span className={props.value === props.base ? "text-ink-light" : "font-semibold"}>
          {formatted(shown, 3)} {control.unit}
        </span>
      </span>
      <input type="range" className="w-full" min={control.min} max={control.max} step={control.step}
        value={shown} onChange={(event) => props.onChange(Number(event.target.value) / control.scale)} />
    </label>
  );
}

function Results({ best, drive }: { best: Map<string, Outcome>; drive: string }) {
  const winner = bestRig(best);
  const bare = best.get("none");
  const ownFuel = drive !== "ammonia" && drive !== "vlsfo";
  return (
    <section className="overflow-x-auto rounded-[14px] border-2 border-ink bg-paper p-5">
      <table className="w-full text-sm">
        <thead className="text-left text-ink">
          <tr>
            <th className="py-1">Rig</th>
            <th>Best size</th>
            <th className="text-right">Cost [USD per 1000 t·km]</th>
            {ownFuel && <th className="text-right">Saves against the same ship on {driveLabels[drive]}</th>}
            <th className="text-right">{ownFuel ? "on" : "Saves against the same ship on"} e-ammonia</th>
            <th className="text-right">on fuel oil</th>
          </tr>
        </thead>
        <tbody>
          {bare && (
            <tr className="border-t border-ink/20">
              <td className="py-1">No rig</td>
              <td />
              <td className="text-right">{formatted(1000 * bare.cost, 3)}</td>
              {ownFuel && <td className="text-right">–</td>}
              <td className="text-right">{formatted(bare.ammoniaSaving)} %</td>
              <td className="text-right">{formatted(bare.vlsfoSaving)} %</td>
            </tr>
          )}
          {rigs.map((rig) => {
            const outcome = best.get(rig);
            const wins = rig === winner && outcome && outcome.saving > 0;
            return (
              <tr key={rig} className={`border-t border-ink/20 ${wins ? "bg-teal/15 font-semibold" : ""}`}>
                <td className="py-1">
                  <span className="mr-2 inline-block h-3 w-3 rounded-sm" style={{ background: rigColour(rig as PassageDesign["rig"]) }} />
                  {RIG_LABELS[rig as PassageDesign["rig"]]}{wins ? " — best" : ""}
                </td>
                {outcome ? (
                  <>
                    <td>{formatted(outcome.design.area, 0)} m² in {outcome.design.units} unit{outcome.design.units === 1 ? "" : "s"}</td>
                    <td className="text-right">{formatted(1000 * outcome.cost, 3)}</td>
                    {ownFuel && <td className="text-right">{formatted(outcome.saving)} %</td>}
                    <td className="text-right">{formatted(outcome.ammoniaSaving)} %</td>
                    <td className="text-right">{formatted(outcome.vlsfoSaving)} %</td>
                  </>
                ) : (
                  <td colSpan={ownFuel ? 5 : 4} className="text-ink-light">no feasible design</td>
                )}
              </tr>
            );
          })}
        </tbody>
      </table>
      <p className="mt-2 text-xs text-ink-light">
        Each rig at the size that costs least at these inputs, among the sizes the study routed. A saving is the
        drop in cost per tonne-km against the ship without a rig.
      </p>
    </section>
  );
}

function WinnerMap(props: { data: ExplorerData; all: Outcome[]; drive: string; onPick: (ship: number, route: number) => void }) {
  const { data } = props;
  return (
    <section className="space-y-2">
      <h2 className="text-lg font-semibold">Best rig per ship and route on {driveLabels[props.drive]}</h2>
      <div className="overflow-x-auto">
        <table className="text-xs">
          <thead>
            <tr>
              <th />
              {data.routes.map((route) => <th key={route.name} className="px-1 font-normal">{route.label}</th>)}
            </tr>
          </thead>
          <tbody>
            {data.classes.map((entry, k) => (
              <tr key={entry.name}>
                <td className="pr-2 text-right">{entry.name}</td>
                {data.routes.map((route, j) => {
                  const best = bestDesigns(props.all, k, j, props.drive);
                  const winner = bestRig(best);
                  const saving = winner ? best.get(winner)!.saving : NaN;
                  const shown = winner && saving > 0;
                  return (
                    <td key={route.name} className="h-8 w-20 cursor-pointer text-center text-white"
                      title={shown ? `${RIG_LABELS[winner as PassageDesign["rig"]]} saves ${formatted(saving)} %` : "no rig pays"}
                      style={{ background: shown ? rigColour(winner as PassageDesign["rig"]) : "var(--brand-mid)", opacity: shown ? 0.35 + (0.65 * Math.min(saving, 40)) / 40 : 0.5 }}
                      onClick={() => props.onPick(k, j)}>
                      {Number.isFinite(saving) ? Math.round(saving) : "–"}
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="text-xs text-ink-light">
        Saving of the best rig in %, coloured by rig; grey where no rig pays. Click a cell to pick that ship and route.
      </p>
    </section>
  );
}

function Accuracy({ data }: { data: ExplorerData }) {
  const rows = useMemo(() => {
    const byLabel = new Map<string, number>();
    for (const check of data.checks) {
      const values = evaluated(data, inputValues(data, check.changes, check.cargo_factor));
      const shown = values[data.designs[check.design].nodes.cost];
      const drift = (100 * Math.abs(shown - check.rerouted)) / check.rerouted;
      byLabel.set(check.label, Math.max(byLabel.get(check.label) ?? 0, drift));
    }
    return [...byLabel];
  }, [data]);
  return (
    <section className="space-y-2 text-sm">
      <h2 className="text-lg font-semibold">How far to trust a change</h2>
      <p className="text-ink">
        The explorer keeps each design's voyages as the model routed them at the paper's inputs and recomputes
        their cost with the model's own cost formulas. Crash and loss rates do not steer the router, so they are
        exact ({exactInputs.length} inputs). Every other input also changes how the ship is routed; the table gives the
        largest gap between the explorer and a full rerun of the model for {new Set(data.checks.map((check) => check.design)).size} designs.
      </p>
      <table className="text-sm">
        <tbody>
          {rows.map(([label, drift]) => (
            <tr key={label} className="border-t border-ink/20">
              <td className="py-1 pr-4">{label}</td>
              <td className="text-right">{formatted(drift, 2)} % of the cost</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}
