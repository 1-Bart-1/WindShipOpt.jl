// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import type { PassageDesign, PassageState } from "./passages";
import { brandColour } from "../brand";
import { disposeTree, towardsEdge } from "./scene";

const flat = (name: string, options: THREE.MeshBasicMaterialParameters = {}) =>
  new THREE.MeshBasicMaterial({ color: brandColour(name), ...options });

/** Ink outlines over a mesh's edges. */
function outlined(mesh: THREE.Mesh): THREE.Group {
  const group = new THREE.Group();
  const lines = new THREE.LineSegments(new THREE.EdgesGeometry(mesh.geometry, 25), new THREE.LineBasicMaterial({ color: brandColour("ink") }));
  group.add(mesh, lines);
  return group;
}

/** A hull with a pointed bow, its deck at `freeboard` above the water line. */
function hullMesh(design: PassageDesign, freeboard: number): THREE.Group {
  const halfLength = design.length / 2;
  const halfBeam = design.beam / 2;
  const shape = new THREE.Shape();
  shape.moveTo(-halfLength, -halfBeam);
  shape.lineTo(halfLength * 0.55, -halfBeam);
  shape.quadraticCurveTo(halfLength * 0.9, -halfBeam * 0.6, halfLength, 0);
  shape.quadraticCurveTo(halfLength * 0.9, halfBeam * 0.6, halfLength * 0.55, halfBeam);
  shape.lineTo(-halfLength, halfBeam);
  shape.closePath();
  const geometry = new THREE.ExtrudeGeometry(shape, { depth: freeboard + design.draft, bevelEnabled: false, curveSegments: 16 });
  geometry.rotateX(-Math.PI / 2);
  geometry.translate(0, -design.draft, 0);
  const group = new THREE.Group();
  group.add(outlined(new THREE.Mesh(geometry, flat("rust"))));
  const deck = new THREE.Mesh(new THREE.ShapeGeometry(shape), flat("paper"));
  deck.rotation.x = -Math.PI / 2;
  deck.position.y = freeboard + 0.05;
  group.add(deck);
  const house = new THREE.Mesh(new THREE.BoxGeometry(design.length * 0.1, design.length * 0.08, design.beam * 0.85), flat("paper"));
  house.position.set(-halfLength * 0.82, freeboard + design.length * 0.04, 0);
  group.add(outlined(house));
  return group;
}

/** The ship carrying its rig on the water, with a kite on its tether where it flies. */
export class ShipScene {
  private scene = new THREE.Scene();
  private camera: THREE.PerspectiveCamera;
  private renderer: THREE.WebGLRenderer;
  private controls: OrbitControls;
  private root = new THREE.Group();
  private wings: THREE.Object3D[] = [];
  private rotors: THREE.Object3D[] = [];
  private kite?: THREE.Group;
  private bundle?: THREE.Object3D;
  private tether?: THREE.Line;
  private loop?: THREE.Line;
  private design?: PassageDesign;
  private streaks: { line: THREE.Line; offset: number }[] = [];
  private cycle = 0;
  private spinAngle = 0;

  constructor(private host: HTMLElement) {
    const { clientWidth, clientHeight } = host;
    this.renderer = new THREE.WebGLRenderer({ antialias: true });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.setSize(clientWidth, clientHeight);
    host.appendChild(this.renderer.domElement);
    this.camera = new THREE.PerspectiveCamera(36, clientWidth / clientHeight, 1, 20000);
    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.enablePan = false;
    this.controls.enableDamping = true;
    this.scene.background = new THREE.Color(brandColour("sky"));
    const water = new THREE.Mesh(new THREE.CircleGeometry(16000, 64),
      new THREE.MeshBasicMaterial({ color: new THREE.Color(brandColour("teal-light")).lerp(new THREE.Color(brandColour("sky")), 0.45) }));
    water.rotation.x = -Math.PI / 2;
    this.scene.add(water, this.root);
  }

  resize() {
    const { clientWidth, clientHeight } = this.host;
    this.camera.aspect = clientWidth / clientHeight;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(clientWidth, clientHeight);
  }

  /** Rebuild the ship and rig of `design`, looking at the deck if `deckView`, else the whole system. */
  showDesign(design: PassageDesign, deckView: boolean) {
    this.design = design;
    disposeTree(this.root);
    this.root.clear();
    this.wings = [];
    this.rotors = [];
    this.kite = undefined;
    this.bundle = undefined;
    this.tether = undefined;
    this.loop = undefined;
    const freeboard = Math.max(design.depth - design.draft, 1);
    this.root.add(hullMesh(design, freeboard));
    if (design.rig === "wings") {
      for (const position of design.positions!) this.addWing(design, position);
    } else if (design.rig === "rotors") {
      for (const position of design.positions!) this.addRotor(design, position);
    } else if (design.rig === "kite") {
      this.addKite(design);
    }
    this.addStreaks(design);
    this.frame(design, deckView);
  }

  private frame(design: PassageDesign, deckView: boolean) {
    const tether = design.rig === "kite" && !deckView ? design.tether_length! : 0;
    const top = tether > 0 ? tether * 0.38 : (design.height ?? design.length * 0.12) * 0.55;
    const reach = tether > 0 ? tether * 2.3 : Math.max(design.length * 1.6, (design.height ?? 0) * 2.4);
    this.controls.target.set(0, top, 0);
    this.camera.position.set(-reach * 0.72, top + reach * 0.18, reach * 0.68);
    this.controls.minDistance = design.length * 0.35;
    this.controls.maxDistance = reach * 4;
    this.controls.update();
  }

  private addWing(design: PassageDesign, position: number) {
    const shape = new THREE.Shape();
    const halfWidth = design.width! / 2;
    const thickness = design.width! * 0.1;
    shape.moveTo(-halfWidth, 0);
    shape.quadraticCurveTo(0, thickness * 1.4, halfWidth, 0);
    shape.quadraticCurveTo(0, -thickness * 1.4, -halfWidth, 0);
    const geometry = new THREE.ExtrudeGeometry(shape, { depth: design.height!, bevelEnabled: false, curveSegments: 12 });
    geometry.rotateX(-Math.PI / 2);
    const wing = outlined(new THREE.Mesh(geometry, flat("paper")));
    wing.position.set(position, design.foot_height!, 0);
    this.root.add(wing);
    this.wings.push(wing);
  }

  private addRotor(design: PassageDesign, position: number) {
    const radius = design.diameter! / 2;
    const body = new THREE.Mesh(new THREE.CylinderGeometry(radius, radius, design.height!, 32), flat("paper"));
    const rotor = new THREE.Group();
    rotor.add(outlined(body));
    const cap = new THREE.Mesh(new THREE.CylinderGeometry(radius * 1.25, radius * 1.25, design.height! * 0.012, 32), flat("ink"));
    cap.position.y = design.height! / 2;
    const stripe = new THREE.Mesh(new THREE.BoxGeometry(radius * 0.18, design.height!, radius * 0.06), flat("ink"));
    stripe.position.set(radius * 0.99, 0, 0);
    rotor.add(cap, stripe);
    rotor.position.set(position, design.foot_height! + design.height! / 2, 0);
    this.root.add(rotor);
    this.rotors.push(rotor);
  }

  private addKite(design: PassageDesign) {
    const span = design.span!;
    const chord = design.area / span;
    const segments = 14;
    const positions: number[] = [];
    const indices: number[] = [];
    for (let i = 0; i <= segments; i++) {
      const station = -1 + (2 * i) / segments;
      const x = (station * span) / 2;
      const y = -0.25 * span * station * station;
      positions.push(x, y, -chord / 2, x, y, chord / 2);
      if (i < segments) indices.push(2 * i, 2 * i + 1, 2 * i + 2, 2 * i + 1, 2 * i + 3, 2 * i + 2);
    }
    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));
    geometry.setIndex(indices);
    this.kite = outlined(new THREE.Mesh(geometry, flat("orange", { side: THREE.DoubleSide })));
    this.root.add(this.kite);
    const bundle = new THREE.Mesh(new THREE.SphereGeometry(design.beam * 0.22, 16, 16), flat("orange"));
    bundle.scale.y = 0.5;
    bundle.position.set(design.attach_position!, design.attach_height! + 2, 0);
    this.bundle = bundle;
    this.root.add(bundle);
    const mast = new THREE.Mesh(new THREE.CylinderGeometry(0.4, 0.6, design.attach_height!, 8), flat("ink"));
    mast.position.set(design.attach_position!, design.attach_height! / 2, 0);
    this.root.add(mast);
    this.tether = new THREE.Line(new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(), new THREE.Vector3()]), new THREE.LineBasicMaterial({ color: brandColour("ink") }));
    this.root.add(this.tether);
    this.loop = new THREE.LineLoop(new THREE.BufferGeometry(), new THREE.LineDashedMaterial({ color: brandColour("orange"), dashSize: design.tether_length! * 0.02, gapSize: design.tether_length! * 0.02 }));
    this.root.add(this.loop);
  }

  private addStreaks(design: PassageDesign) {
    this.streaks = [];
    const material = new THREE.LineBasicMaterial({ color: brandColour("paper"), transparent: true, opacity: 0.8 });
    const reach = design.rig === "kite" ? design.tether_length! : design.length * 2;
    for (let i = 0; i < 40; i++) {
      const line = new THREE.Line(new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(), new THREE.Vector3(reach * 0.06, 0, 0)]), material);
      line.position.set((Math.random() - 0.5) * 2 * reach, Math.random() * reach * 0.6 + 3, (Math.random() - 0.5) * 2 * reach);
      this.root.add(line);
      this.streaks.push({ line, offset: Math.random() * 10 });
    }
  }

  /** Draw the rig at the recorded `state`; `dt` [s] of animation advances the spin and the pattern cycle. */
  update(state: PassageState, dt: number) {
    const design = this.design;
    if (!design) return;
    for (const wing of this.wings) wing.rotation.y = -THREE.MathUtils.degToRad(state.chord ?? 0);
    this.spinAngle += dt * (state.spin ?? 0) * 3;
    for (const rotor of this.rotors) rotor.rotation.y = -this.spinAngle;
    this.updateKite(state, dt);
    this.updateStreaks(state, dt);
  }

  private kitePosition(design: PassageDesign, azimuth: number, elevation: number) {
    const azimuthRadians = THREE.MathUtils.degToRad(azimuth);
    const elevationRadians = THREE.MathUtils.degToRad(elevation);
    const length = design.tether_length!;
    return new THREE.Vector3(
      design.attach_position! + length * Math.cos(elevationRadians) * Math.cos(azimuthRadians),
      design.attach_height! + length * Math.sin(elevationRadians),
      length * Math.cos(elevationRadians) * Math.sin(azimuthRadians),
    );
  }

  private updateKite(state: PassageState, dt: number) {
    const design = this.design!;
    if (!this.kite) return;
    const { pattern } = state;
    const flying = Boolean(pattern) && state.flying;
    this.kite.visible = flying;
    this.bundle!.visible = !flying;
    this.tether!.visible = flying;
    const still = pattern?.period === 0;
    this.loop!.visible = flying && !still;
    if (!pattern || !flying) return;
    const count = pattern.azimuth.length;
    this.cycle = (this.cycle + (dt * count) / Math.max(pattern.period / 6, 3)) % count;
    const low = Math.floor(this.cycle);
    const share = this.cycle - low;
    const high = (low + 1) % count;
    const azimuth = pattern.azimuth[low] + share * (((pattern.azimuth[high] - pattern.azimuth[low] + 540) % 360) - 180);
    const elevation = pattern.elevation[low] + share * (pattern.elevation[high] - pattern.elevation[low]);
    const position = this.kitePosition(design, azimuth, elevation);
    const ahead = this.kitePosition(design, pattern.azimuth[high], pattern.elevation[high]);
    const anchor = new THREE.Vector3(design.attach_position!, design.attach_height!, 0);
    this.kite.position.copy(position);
    const radial = position.clone().sub(anchor).normalize();
    const step = ahead.sub(position);
    const motion = still || step.lengthSq() < 1e-6 ? towardsEdge(radial, state.apparentAngle) : step.normalize();
    const along = new THREE.Vector3().crossVectors(radial, motion).normalize();
    const basis = new THREE.Matrix4().makeBasis(along, radial, motion.clone().cross(along).negate());
    this.kite.quaternion.setFromRotationMatrix(basis);
    this.tether!.geometry.setFromPoints([anchor, position]);
    this.loop!.geometry.setFromPoints(pattern.azimuth.map((angle, i) => this.kitePosition(design, angle, pattern.elevation[i])));
    this.loop!.computeLineDistances();
  }

  private updateStreaks(state: PassageState, dt: number) {
    const design = this.design!;
    const reach = design.rig === "kite" ? design.tether_length! : design.length * 2;
    const angle = THREE.MathUtils.degToRad(state.apparentAngle);
    const direction = new THREE.Vector3(-Math.cos(angle), 0, -Math.sin(angle));
    const step = direction.clone().multiplyScalar(dt * reach * 0.15 * (0.5 + state.apparentWind / 20));
    for (const streak of this.streaks) {
      streak.line.position.add(step);
      streak.line.lookAt(streak.line.position.clone().add(direction));
      streak.line.rotateY(-Math.PI / 2);
      if (streak.line.position.length() > reach * 1.4) {
        streak.line.position.copy(direction.clone().multiplyScalar(-reach * 1.2).add(new THREE.Vector3(direction.z * (Math.random() - 0.5) * reach * 1.6, Math.random() * reach * 0.6 + 3, -direction.x * (Math.random() - 0.5) * reach * 1.6)));
      }
    }
  }

  render() {
    this.controls.update();
    this.renderer.render(this.scene, this.camera);
  }

  dispose() {
    disposeTree(this.scene);
    this.controls.dispose();
    this.renderer.dispose();
    this.renderer.domElement.remove();
  }
}
