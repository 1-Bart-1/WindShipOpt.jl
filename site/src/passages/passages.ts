// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

/** One rig on a passage: the ship's hull and, where carried, the rig's geometry. */
export interface PassageDesign {
  rig: "none" | "kite" | "wings" | "rotors";
  area: number;
  length: number;
  beam: number;
  draft: number;
  depth: number;
  count?: number;
  height?: number;
  foot_height?: number;
  width?: number;
  diameter?: number;
  positions?: number[];
  span?: number;
  tether_length?: number;
  attach_height?: number;
  attach_position?: number;
}

export interface PassageIndex {
  fidelity: string;
  git_commit: string;
  weather: string;
  routes: { name: string; label: string }[];
  departures: { hours: number; label: string }[];
  designs: PassageDesign[];
  pattern_samples: number;
  port_hours: number;
}

/** Columns of a leg, one value per point the router sailed, in the units of passages_data.jl. */
export interface LegColumns {
  t: number[];
  lat: number[];
  lon: number[];
  course: number[];
  east: number[];
  north: number[];
  speed: number[];
  thrust: number[];
  power: number[];
  apparent_wind: number[];
  apparent_angle: number[];
  flying: number[];
  event: number[];
  trim: { chord?: number[]; lift?: number[]; spin?: number[]; pattern?: (number[] | null)[] };
}

export interface Leg {
  design: number;
  direction: "out" | "back";
  departure: number;
  start: number;
  duration: number;
  fuel_energy: number;
  nodes: [number, number][];
  columns: LegColumns;
}

export interface RoutePassages {
  route: string;
  legs: Leg[];
}

export interface WindField {
  start: number;
  lat0: number;
  lon0: number;
  spacing: number;
  nlat: number;
  nlon: number;
  hours: number;
  east: number[][];
  north: number[][];
}

export interface RouteWinds {
  route: string;
  winds: (WindField | null)[];
}

export async function loadJson<T>(path: string): Promise<T> {
  const response = await fetch(path);
  if (!response.ok) throw new Error(`${path}: ${response.status}`);
  return (await response.json()) as T;
}

/** The legs of `route`'s file for one design, direction and departure number; undefined if not routed. */
export const findLeg = (passages: RoutePassages, design: number, direction: Leg["direction"], departure: number) =>
  passages.legs.find((leg) => leg.design === design && leg.direction === direction && leg.departure === departure);

/** Index of the last sample of `column` at or before `hours`, and the share of the way to the next. */
export function sampleAt(column: number[], hours: number): [number, number] {
  const tenths = hours * 10;
  let low = 0;
  let high = column.length - 1;
  if (tenths <= column[0]) return [0, 0];
  if (tenths >= column[high]) return [high, 0];
  while (high - low > 1) {
    const middle = (low + high) >> 1;
    if (column[middle] <= tenths) low = middle;
    else high = middle;
  }
  return [low, (tenths - column[low]) / (column[high] - column[low])];
}

const interpolate = (a: number, b: number, share: number) => a + share * (b - a);

/** The shortest interpolation between two angles in degrees. */
export function interpolateAngle(a: number, b: number, share: number): number {
  const turned = ((((b - a) % 360) + 540) % 360) - 180;
  return a + share * turned;
}

export interface PassageState {
  hours: number;
  sample: number;
  lat: number;
  lon: number;
  course: number;
  windEast: number;
  windNorth: number;
  speed: number;
  thrust: number;
  power: number;
  apparentWind: number;
  apparentAngle: number;
  flying: boolean;
  /** How far the kite is out on its tether, 0 stowed to 1 flying. */
  aloft: number;
  chord?: number;
  lift?: number;
  spin?: number;
  /** Azimuths and elevations [deg] of the recorded cycle, or undefined where none flies. */
  pattern?: { azimuth: number[]; elevation: number[]; period: number };
}

function patternOf(raw: number[] | null | undefined): PassageState["pattern"] {
  if (!raw) return undefined;
  const n = (raw.length - 1) / 2;
  return { azimuth: raw.slice(0, n).map((v) => v / 10), elevation: raw.slice(n, 2 * n).map((v) => v / 10), period: raw[2 * n] / 10 };
}

function blendPattern(a: PassageState["pattern"], b: PassageState["pattern"], share: number): PassageState["pattern"] {
  if (!a || !b) return a ?? b;
  return {
    azimuth: a.azimuth.map((v, i) => interpolateAngle(v, b.azimuth[i], share)),
    elevation: a.elevation.map((v, i) => interpolate(v, b.elevation[i], share)),
    period: interpolate(a.period, b.period, share),
  };
}

/** The recorded state of `leg` at `hours` since it left, continuous values interpolated between samples. */
export function stateAt(leg: Leg, hours: number): PassageState {
  const c = leg.columns;
  const [i, share] = sampleAt(c.t, hours);
  const j = Math.min(i + 1, c.t.length - 1);
  const at = (column: number[]) => interpolate(column[i], column[j], share);
  const flyingHere = c.flying[i] > 0;
  const flyingNext = c.flying[j] > 0;
  return {
    hours,
    sample: i,
    lat: at(c.lat) / 100,
    lon: at(c.lon) / 100,
    course: interpolateAngle(c.course[i], c.course[j], share),
    windEast: at(c.east) / 10,
    windNorth: at(c.north) / 10,
    speed: at(c.speed) / 10,
    thrust: at(c.thrust) / 10,
    power: at(c.power) / 100,
    apparentWind: at(c.apparent_wind) / 10,
    apparentAngle: interpolateAngle(c.apparent_angle[i], c.apparent_angle[j], share),
    flying: flyingHere,
    aloft: flyingHere === flyingNext ? (flyingHere ? 1 : 0) : flyingHere ? 1 - share : share,
    chord: c.trim.chord && interpolateAngle(c.trim.chord[i], c.trim.chord[j], share),
    lift: c.trim.lift && at(c.trim.lift) / 100,
    spin: c.trim.spin && at(c.trim.spin) / 100,
    pattern: c.trim.pattern && blendPattern(patternOf(c.trim.pattern[i]), patternOf(c.trim.pattern[j]), share),
  };
}

/** Launch, landing and forced-landing events of `leg`, with where they happened. */
export function legEvents(leg: Leg): { hours: number; lat: number; lon: number; kind: number }[] {
  const c = leg.columns;
  return c.event.flatMap((kind, i) =>
    kind === 0 ? [] : [{ hours: c.t[i] / 10, lat: c.lat[i] / 100, lon: c.lon[i] / 100, kind }],
  );
}

/** The wind field at absolute time `hours` [h], interpolated linearly between frames, `[east, north]` per grid cell [m/s]. */
export function windAt(field: WindField, hours: number): { east: number[]; north: number[] } {
  const position = (hours - field.start) / field.hours;
  const low = Math.max(Math.min(Math.floor(position), field.east.length - 1), 0);
  const high = Math.min(low + 1, field.east.length - 1);
  const share = Math.min(Math.max(position - low, 0), 1);
  const blend = (frames: number[][]) => frames[low].map((v, i) => interpolate(v, frames[high][i], share) / 10);
  return { east: blend(field.east), north: blend(field.north) };
}

/** A time cursor shared by the linked views of a passage. */
export class Timeline {
  hours = 0;
  duration = 1;
  playing = false;
  /** Hours of passage per second of animation. */
  rate = 8;
  private listeners = new Set<() => void>();

  set(hours: number) {
    this.hours = Math.min(Math.max(hours, 0), this.duration);
    this.listeners.forEach((listener) => listener());
  }

  subscribe(listener: () => void) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }
}

export const RIG_LABELS: Record<PassageDesign["rig"], string> = {
  none: "No rig",
  kite: "Towing kite",
  wings: "Wing sails",
  rotors: "Flettner rotors",
};

/** Colours of the brand by rig, as CSS custom properties. */
export const RIG_COLOURS: Record<PassageDesign["rig"], string> = {
  none: "var(--brand-ink)",
  kite: "var(--brand-orange)",
  wings: "var(--brand-teal)",
  rotors: "var(--brand-rust)",
};
