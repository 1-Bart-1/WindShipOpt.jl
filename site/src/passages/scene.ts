// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

import type * as THREE from "three";

/** The CSS value of the brand colour `name`. */
export const brandColour = (name: string) =>
  getComputedStyle(document.documentElement).getPropertyValue(`--brand-${name}`).trim();

/** Free the GPU buffers of `root` and of everything under it. */
export function disposeTree(root: THREE.Object3D) {
  root.traverse((object) => {
    const { geometry, material } = object as THREE.Mesh;
    geometry?.dispose();
    for (const each of [material].flat()) {
      (each as THREE.MeshBasicMaterial | undefined)?.map?.dispose();
      each?.dispose();
    }
    (object as THREE.InstancedMesh).dispose?.();
  });
}
