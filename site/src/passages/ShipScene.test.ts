// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

import * as THREE from "three";
import { describe, expect, it } from "vitest";
import { kiteAttitude, spherePosition } from "./ShipScene";

const axis = (x: number, y: number, z: number, attitude: THREE.Quaternion) => new THREE.Vector3(x, y, z).applyQuaternion(attitude);
const degrees = THREE.MathUtils.radToDeg;

describe("the kite drawn on its tether", () => {
  for (const [azimuth, elevation, nose, pitch] of [[-40, 20, 0, 0], [-150, 15, 80, 12], [30, 60, -120, -5], [10, 5, 170, 30]]) {
    it(`points its nose as recorded and lies square to it at ${azimuth}°, ${elevation}°, nose ${nose}°, pitch ${pitch}°`, () => {
      const attitude = kiteAttitude(azimuth, elevation, nose, pitch);
      const radial = spherePosition(azimuth, elevation);
      const back = axis(0, 1, 0, attitude);
      const chord = axis(0, 0, 1, attitude);
      const risingElevation = spherePosition(azimuth, elevation + 90);
      const risingAzimuth = spherePosition(azimuth + 90, 0);
      expect(degrees(Math.atan2(chord.dot(risingAzimuth), chord.dot(risingElevation)))).toBeCloseTo(nose, 6);
      expect(degrees(Math.asin(chord.dot(radial)))).toBeCloseTo(pitch, 6);
      expect(degrees(back.angleTo(radial))).toBeCloseTo(Math.abs(pitch), 6);
      expect(axis(1, 0, 0, attitude).cross(back).distanceTo(chord)).toBeLessThan(1e-9);
    });
  }
});
