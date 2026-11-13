// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

import * as THREE from "three";
import { describe, expect, it } from "vitest";
import { kiteAttitude, spherePosition } from "./ShipScene";

const axis = (x: number, y: number, z: number, attitude: THREE.Quaternion) => new THREE.Vector3(x, y, z).applyQuaternion(attitude);

describe("the kite drawn on its tether", () => {
  for (const [azimuth, elevation, nose] of [[-40, 20, 0], [-150, 15, 80], [30, 60, -120], [10, 5, 170]]) {
    it(`turns its back to the tether and its nose to the recorded flight direction at ${azimuth}°, ${elevation}°, nose ${nose}°`, () => {
      const attitude = kiteAttitude(azimuth, elevation, nose);
      const radial = spherePosition(azimuth, elevation);
      const back = axis(0, 1, 0, attitude);
      const chord = axis(0, 0, 1, attitude);
      expect(back.distanceTo(radial)).toBeLessThan(1e-9);
      const risingElevation = spherePosition(azimuth, elevation + 90);
      const risingAzimuth = spherePosition(azimuth + 90, 0);
      expect(THREE.MathUtils.radToDeg(Math.atan2(chord.dot(risingAzimuth), chord.dot(risingElevation)))).toBeCloseTo(nose, 6);
      expect(axis(1, 0, 0, attitude).cross(back).distanceTo(chord)).toBeLessThan(1e-9);
    });
  }
});
