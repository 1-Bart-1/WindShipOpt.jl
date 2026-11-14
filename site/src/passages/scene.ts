// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

import * as THREE from "three";

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

/** Unit direction at the kite's unit `radial` towards the wind window's edge: upwind along the tether sphere, for an apparent wind `angle` [deg] off the bow. */
export function towardsEdge(radial: THREE.Vector3, angle: number): THREE.Vector3 {
  const radians = THREE.MathUtils.degToRad(angle);
  const downwind = new THREE.Vector3(-Math.cos(radians), 0, -Math.sin(radians));
  return radial.clone().multiplyScalar(downwind.dot(radial)).sub(downwind).normalize();
}
