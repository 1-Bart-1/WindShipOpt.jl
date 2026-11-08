import { readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { passagesDirectory } from "../../data";
import { findLeg, interpolateAngle, legEvents, sampleAt, stateAt, windAt, type Leg, type WindField } from "./passages";

const leg: Leg = {
  design: 1,
  direction: "out",
  departure: 0,
  start: 100,
  duration: 12,
  fuel_energy: 1,
  nodes: [[10, -5], [12, -7]],
  columns: {
    t: [0, 60, 120],
    lat: [1000, 1100, 1200],
    lon: [-500, -600, -700],
    course: [350, 10, 20],
    east: [10, 20, 30],
    north: [0, 0, 0],
    speed: [100, 110, 120],
    thrust: [500, 600, 700],
    power: [1000, 900, 800],
    apparent_wind: [100, 100, 100],
    apparent_angle: [-170, 170, 160],
    flying: [0, 1, 1],
    event: [0, 1, 0],
    trim: { pattern: [null, [10, 20, 30, 40, 50], [30, 40, 50, 60, 70]] },
  },
};

describe("a passage replayed at a time", () => {
  it("finds the sample before the time and the share of the way to the next", () => {
    expect(sampleAt(leg.columns.t, 0)).toEqual([0, 0]);
    expect(sampleAt(leg.columns.t, 3)).toEqual([0, 0.5]);
    expect(sampleAt(leg.columns.t, 6)).toEqual([1, 0]);
    expect(sampleAt(leg.columns.t, 12)).toEqual([2, 0]);
    expect(sampleAt(leg.columns.t, 99)).toEqual([2, 0]);
  });

  it("interpolates angles the short way round", () => {
    expect(interpolateAngle(350, 10, 0.5)).toBeCloseTo(360);
    expect(interpolateAngle(-170, 170, 0.5)).toBeCloseTo(-180);
  });

  it("shows the recorded state exactly at a sample", () => {
    const state = stateAt(leg, 6);
    expect(state.lat).toBe(11);
    expect(state.lon).toBe(-6);
    expect(state.speed).toBe(11);
    expect(state.thrust).toBe(60);
    expect(state.power).toBe(9);
    expect(state.flying).toBe(true);
    expect(state.aloft).toBe(1);
    expect(state.pattern?.azimuth).toEqual([1, 2]);
    expect(state.pattern?.elevation).toEqual([3, 4]);
    expect(state.pattern?.period).toBe(5);
  });

  it("raises the kite between the stowed sample and the launched one", () => {
    expect(stateAt(leg, 3).aloft).toBe(0.5);
    expect(stateAt(leg, 0).aloft).toBe(0);
  });

  it("lists the launches where the run launched", () => {
    expect(legEvents(leg)).toEqual([{ hours: 6, lat: 11, lon: -6, kind: 1 }]);
  });

  it("finds a leg by design, direction and departure", () => {
    expect(findLeg({ route: "x", legs: [leg] }, 1, "out", 0)).toBe(leg);
    expect(findLeg({ route: "x", legs: [leg] }, 1, "back", 0)).toBeUndefined();
  });
});

describe("the exported wind field", () => {
  const field: WindField = { start: 0, lat0: 0, lon0: 0, spacing: 5, nlat: 1, nlon: 1, hours: 12, east: [[10], [20]], north: [[0], [40]] };
  it("is interpolated between frames and clamped to them", () => {
    expect(windAt(field, 6)).toEqual({ east: [1.5], north: [2] });
    expect(windAt(field, -1)).toEqual({ east: [1], north: [0] });
    expect(windAt(field, 99)).toEqual({ east: [2], north: [4] });
  });
});

describe("the passage files", () => {
  const directory = passagesDirectory();
  it.runIf(directory)("fit a static site", () => {
    const files = readdirSync(directory!).filter((name) => /^(passages|winds)-.*\.json$/.test(name));
    expect(files.length).toBeGreaterThan(0);
    const bytes = (name: string) => statSync(join(directory!, name)).size;
    for (const name of files) expect(bytes(name)).toBeLessThan(3_500_000);
    expect(files.reduce((total, name) => total + bytes(name), 0)).toBeLessThan(25_000_000);
  });
});
