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

const interpolate = (from: number, to: number, share: number) => from + share * (to - from);

/** The shortest interpolation between two angles in degrees. */
export function interpolateAngle(from: number, to: number, share: number): number {
  const turned = ((((to - from) % 360) + 540) % 360) - 180;
  return from + share * turned;
}

export interface PassageState {
  hours: number;
  sample: number;
  lat: number;
  lon: number;
  course: number;
  windEast: number;
  windNorth: number;
  /** Recorded at the last sample; the panels draw the same held values. */
  speed: number;
  thrust: number;
  power: number;
  apparentWind: number;
  /** Apparent wind off the bow [deg], positive from starboard. */
  apparentAngle: number;
  /** Whether the kite is up, held from the sample it launched at to the one it landed at. */
  flying: boolean;
  chord?: number;
  /** Held at the last sample, as `speed`. */
  lift?: number;
  spin?: number;
  /** Azimuths, elevations, nose angles and nose pitches [deg] of the recorded cycle, or undefined where none flies. */
  pattern?: { azimuth: number[]; elevation: number[]; nose: number[]; pitch: number[]; period: number };
}

function patternOf(raw: number[] | null | undefined): PassageState["pattern"] {
  if (!raw) return undefined;
  const n = (raw.length - 1) / 4;
  const inDegrees = (tenths: number) => tenths / 10;
  const block = (k: number) => raw.slice(k * n, (k + 1) * n).map(inDegrees);
  return { azimuth: block(0), elevation: block(1), nose: block(2), pitch: block(3), period: raw[4 * n] / 10 };
}

function blendPattern(from: PassageState["pattern"], to: PassageState["pattern"], share: number): PassageState["pattern"] {
  if (!from || !to) return from ?? to;
  if ((from.period === 0) !== (to.period === 0)) return share < 0.5 ? from : to;
  return {
    azimuth: from.azimuth.map((angle, i) => interpolateAngle(angle, to.azimuth[i], share)),
    elevation: from.elevation.map((angle, i) => interpolate(angle, to.elevation[i], share)),
    nose: from.nose.map((angle, i) => interpolateAngle(angle, to.nose[i], share)),
    pitch: from.pitch.map((angle, i) => interpolate(angle, to.pitch[i], share)),
    period: interpolate(from.period, to.period, share),
  };
}

/** The recorded state of `leg` at `hours` since it left: position, wind and the rig's pose interpolated between samples, the recorded numbers held. */
export function stateAt(leg: Leg, hours: number): PassageState {
  const columns = leg.columns;
  const [i, share] = sampleAt(columns.t, hours);
  const j = Math.min(i + 1, columns.t.length - 1);
  const at = (column: number[]) => interpolate(column[i], column[j], share);
  const { chord, lift, spin, pattern } = columns.trim;
  return {
    hours,
    sample: i,
    lat: at(columns.lat) / 100,
    lon: at(columns.lon) / 100,
    course: interpolateAngle(columns.course[i], columns.course[j], share),
    windEast: at(columns.east) / 10,
    windNorth: at(columns.north) / 10,
    speed: columns.speed[i] / 10,
    thrust: columns.thrust[i] / 10,
    power: columns.power[i] / 100,
    apparentWind: at(columns.apparent_wind) / 10,
    apparentAngle: interpolateAngle(columns.apparent_angle[i], columns.apparent_angle[j], share),
    flying: columns.flying[i] > 0,
    chord: chord && interpolateAngle(chord[i], chord[j], share),
    lift: lift && lift[i] / 100,
    spin: spin && spin[i] / 100,
    pattern: pattern && blendPattern(patternOf(pattern[i]), patternOf(pattern[j]), share),
  };
}

/** Length [days] of the time axis that carries `leg` and, where given, `baseline`. */
export const passageDays = (leg: Leg, baseline?: Leg) =>
  Math.max(...[leg, baseline].filter((each): each is Leg => each !== undefined).map((each) => each.columns.t[each.columns.t.length - 1])) / 240;

/** Launch, landing and forced-landing events of `leg`, with where they happened. */
export function legEvents(leg: Leg): { hours: number; lat: number; lon: number; kind: number }[] {
  const columns = leg.columns;
  return columns.event.flatMap((kind, i) =>
    kind === 0 ? [] : [{ hours: columns.t[i] / 10, lat: columns.lat[i] / 100, lon: columns.lon[i] / 100, kind }],
  );
}

/** The wind field at absolute time `hours` [h], interpolated linearly between frames, `[east, north]` per grid cell [m/s]. */
export function windAt(field: WindField, hours: number): { east: number[]; north: number[] } {
  const position = (hours - field.start) / field.hours;
  const low = Math.max(Math.min(Math.floor(position), field.east.length - 1), 0);
  const high = Math.min(low + 1, field.east.length - 1);
  const share = Math.min(Math.max(position - low, 0), 1);
  const blend = (frames: number[][]) => frames[low].map((value, i) => interpolate(value, frames[high][i], share) / 10);
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
    if (this.hours >= this.duration) this.playing = false;
    this.notify();
  }

  /** Pause if playing, else play on from the cursor, or from the start once at the end. */
  toggle() {
    if (!this.playing && this.hours >= this.duration) this.hours = 0;
    this.playing = !this.playing;
    this.notify();
  }

  private notify() {
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

/** Name of the brand colour of each rig. */
export const RIG_BRAND: Record<PassageDesign["rig"], string> = {
  none: "ink",
  kite: "orange",
  wings: "teal",
  rotors: "rust",
};

/** CSS value drawing `rig` in its brand colour. */
export const rigColour = (rig: PassageDesign["rig"]) => `var(--brand-${RIG_BRAND[rig]})`;
