// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

import { readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { passagesDirectory } from "../../data";
import * as THREE from "three";
import { findLeg, interpolateAngle, legEvents, passageDays, sampleAt, stateAt, Timeline, windAt, type Leg, type WindField } from "./passages";
import { disposeTree } from "./scene";

const leg: Leg = {
  design: 1,
  direction: "out",
  departure: 0,
  start: 100,
  duration: 12,
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
    expect(state.pattern?.azimuth).toEqual([1, 2]);
    expect(state.pattern?.elevation).toEqual([3, 4]);
    expect(state.pattern?.period).toBe(5);
  });

  it("keeps the kite stowed until the sample it launched at", () => {
    expect(stateAt(leg, 3).flying).toBe(false);
    expect(stateAt(leg, 5.9).flying).toBe(false);
    expect(stateAt(leg, 6).flying).toBe(true);
  });

  it("holds speed, thrust, power and the rig's numbers at the recorded sample between samples", () => {
    const wings: Leg = { ...leg, columns: { ...leg.columns, trim: { chord: [0, 20, 40], lift: [100, 150, 200], spin: [10, 20, 30] } } };
    const state = stateAt(wings, 3);
    expect([state.speed, state.thrust, state.power]).toEqual([10, 50, 10]);
    expect([state.lift, state.spin]).toEqual([1, 0.1]);
  });

  it("lists the launches where the run launched", () => {
    expect(legEvents(leg)).toEqual([{ hours: 6, lat: 11, lon: -6, kind: 1 }]);
  });

  it("finds a leg by design, direction and departure", () => {
    expect(findLeg({ route: "x", legs: [leg] }, 1, "out", 0)).toBe(leg);
    expect(findLeg({ route: "x", legs: [leg] }, 1, "back", 0)).toBeUndefined();
  });
});

describe("the time cursor", () => {
  it("stops at the end of the passage and plays again from the start", () => {
    const timeline = new Timeline();
    timeline.duration = 10;
    timeline.toggle();
    expect(timeline.playing).toBe(true);
    timeline.set(10);
    expect(timeline.playing).toBe(false);
    expect(timeline.hours).toBe(10);
    timeline.toggle();
    expect(timeline.playing).toBe(true);
    expect(timeline.hours).toBe(0);
  });
});

describe("the panels' time axis", () => {
  it("spans the longer of the passage and its baseline", () => {
    const baseline = { ...leg, columns: { ...leg.columns, t: [0, 60, 480] } };
    expect(passageDays(leg, baseline)).toBe(2);
    expect(passageDays(baseline, leg)).toBe(2);
    expect(passageDays(leg)).toBe(0.5);
  });
});

describe("the three.js scene helpers", () => {
  it("disposes the geometry and material of everything under an object", () => {
    const geometry = new THREE.BufferGeometry();
    const material = new THREE.MeshBasicMaterial();
    let disposed = 0;
    geometry.addEventListener("dispose", () => disposed++);
    material.addEventListener("dispose", () => disposed++);
    const root = new THREE.Group();
    root.add(new THREE.Mesh(geometry, material));
    disposeTree(root);
    expect(disposed).toBe(2);
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
