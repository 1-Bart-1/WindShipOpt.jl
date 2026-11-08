// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useMemo, useRef, useEffect } from "react";
import type { Leg, Timeline } from "./passages";

const width = 640;
const panelHeight = 80;
const margin = { left: 44, right: 8, top: 6, bottom: 22 };

interface Series {
  key: "speed" | "thrust" | "power";
  title: string;
  unit: string;
  scale: number;
}

const series: Series[] = [
  { key: "speed", title: "Speed through the water", unit: "kn", scale: 10 },
  { key: "thrust", title: "Rig thrust", unit: "kN", scale: 10 },
  { key: "power", title: "Fuel power", unit: "MW", scale: 100 },
];

const niceStep = (range: number) => {
  const raw = range / 3;
  const power = 10 ** Math.floor(Math.log10(raw));
  const normal = raw / power;
  return (normal < 1.5 ? 1 : normal < 3 ? 2 : normal < 7 ? 5 : 10) * power;
};

/** Step path of recorded values, held from each sample to the next. */
function stepPath(times: number[], values: number[], xOf: (t: number) => number, yOf: (v: number) => number) {
  const parts = [`M${xOf(times[0])},${yOf(values[0])}`];
  for (let i = 1; i < values.length; i++) {
    parts.push(`H${xOf(times[i])}`, `V${yOf(values[i])}`);
  }
  return parts.join("");
}

/** Speed, thrust and fuel power along a passage, with a draggable cursor; `baseline` is the ship without a rig. */
export function Panels({ leg, baseline, colour, timeline }: { leg: Leg; baseline?: Leg; colour: string; timeline: Timeline }) {
  const cursors = useRef<SVGLineElement[]>([]);
  const days = leg.columns.t[leg.columns.t.length - 1] / 240;
  const plots = useMemo(() => series.map((entry) => {
    const plotHeight = panelHeight - margin.top - margin.bottom;
    const values = leg.columns[entry.key].map((v) => v / entry.scale);
    const reference = baseline?.columns[entry.key].map((v) => v / entry.scale);
    const all = reference ? values.concat(reference) : values;
    const low = Math.min(0, ...all);
    const high = Math.max(...all) * 1.05 || 1;
    const step = niceStep(high - low);
    const ticks = Array.from({ length: Math.ceil(high / step) + 1 }, (_, i) => i * step).filter((v) => v <= high);
    const yOf = (v: number) => margin.top + plotHeight * (1 - (v - low) / (high - low));
    const xOf = (t: number) => margin.left + (width - margin.left - margin.right) * (t / (days * 240));
    return { entry, values, reference, yOf, xOf, ticks };
  }), [leg, baseline, days]);

  useEffect(() => {
    const move = () => {
      for (const cursor of cursors.current) {
        const x = margin.left + (width - margin.left - margin.right) * (timeline.hours / (days * 24));
        cursor.setAttribute("x1", String(x));
        cursor.setAttribute("x2", String(x));
      }
    };
    move();
    const stop = timeline.subscribe(move);
    return () => { stop(); };
  }, [timeline, days]);

  const scrub = (event: React.PointerEvent<SVGSVGElement>) => {
    if (event.buttons === 0) return;
    const box = event.currentTarget.getBoundingClientRect();
    const x = ((event.clientX - box.left) / box.width) * width;
    const share = (x - margin.left) / (width - margin.left - margin.right);
    timeline.set(share * days * 24);
  };

  return (
    <div className="grid gap-1">
      {plots.map(({ entry, values, reference, yOf, xOf, ticks }, row) => (
        <figure key={entry.key}>
          <figcaption className="label">{entry.title} [{entry.unit}]</figcaption>
          <svg viewBox={`0 0 ${width} ${panelHeight}`} className="block w-full select-none touch-pan-y"
            onPointerDown={scrub} onPointerMove={scrub}>
            {ticks.map((tick) => (
              <g key={tick}>
                <line x1={margin.left} x2={width - margin.right} y1={yOf(tick)} y2={yOf(tick)} stroke="var(--brand-ink)" strokeOpacity={0.14} />
                <text x={margin.left - 5} y={yOf(tick) + 3} textAnchor="end" className="font-mono fill-ink" fontSize={9}>{tick.toLocaleString("en", { maximumFractionDigits: 1 })}</text>
              </g>
            ))}
            {reference && baseline && (
              <path d={stepPath(baseline.columns.t, reference, xOf, yOf)} fill="none" stroke="var(--brand-ink)" strokeOpacity={0.4} strokeWidth={1.5} strokeDasharray="3 3" />
            )}
            <path d={stepPath(leg.columns.t, values, xOf, yOf)} fill="none" stroke={colour} strokeWidth={2} />
            <line ref={(node) => { if (node) cursors.current[row] = node; }} y1={margin.top} y2={panelHeight - margin.bottom} stroke="var(--brand-rust)" strokeWidth={1.5} />
            {row === 2 && Array.from({ length: Math.floor(days / 2) + 1 }, (_, i) => i * 2).map((day) => (
              <text key={day} x={xOf(day * 240)} y={panelHeight - 8} textAnchor="middle" className="font-mono fill-ink" fontSize={9}>{day}</text>
            ))}
          </svg>
        </figure>
      ))}
      <p className="text-right font-mono text-xs">days since leaving port</p>
    </div>
  );
}
