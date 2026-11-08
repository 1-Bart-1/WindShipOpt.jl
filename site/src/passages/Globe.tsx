import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import { Line2 } from "three/examples/jsm/lines/Line2.js";
import { LineGeometry } from "three/examples/jsm/lines/LineGeometry.js";
import { LineMaterial } from "three/examples/jsm/lines/LineMaterial.js";
import { feature } from "topojson-client";
import land from "world-atlas/land-110m.json";
import { legEvents, windAt, type Leg, type PassageState, type WindField } from "./passages";

const colour = (name: string) => getComputedStyle(document.documentElement).getPropertyValue(`--brand-${name}`).trim();

/** Unit vector of a latitude and longitude in degrees, on the sphere of the land texture. */
export function surfacePoint(lat: number, lon: number, radius = 1): THREE.Vector3 {
  const phi = THREE.MathUtils.degToRad(lat);
  const lambda = THREE.MathUtils.degToRad(lon);
  return new THREE.Vector3(radius * Math.cos(phi) * Math.cos(lambda), radius * Math.sin(phi), -radius * Math.cos(phi) * Math.sin(lambda));
}

function landTexture(sea: string, ground: string, coast: string): THREE.CanvasTexture {
  const canvas = document.createElement("canvas");
  canvas.width = 2048;
  canvas.height = 1024;
  const context = canvas.getContext("2d")!;
  context.fillStyle = sea;
  context.fillRect(0, 0, 2048, 1024);
  context.fillStyle = ground;
  context.strokeStyle = coast;
  context.lineWidth = 1.2;
  const topology = land as unknown as Parameters<typeof feature>[0] & { objects: { land: never } };
  const world = feature(topology, topology.objects.land) as unknown as { features: { geometry: { type: string; coordinates: number[][][][] } }[] };
  for (const { geometry } of world.features) {
    const polygons = geometry.type === "MultiPolygon" ? geometry.coordinates : [geometry.coordinates as unknown as number[][][]];
    for (const polygon of polygons) {
      context.beginPath();
      for (const ring of polygon) {
        ring.forEach(([lon, lat], i) => {
          const x = ((lon + 180) / 360) * 2048;
          const y = ((90 - lat) / 180) * 1024;
          if (i === 0) context.moveTo(x, y);
          else context.lineTo(x, y);
        });
        context.closePath();
      }
      context.fill();
      context.stroke();
    }
  }
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}

/** A globe with the wind field, the routed tracks of a passage and the ship on them. */
export class GlobeScene {
  private scene = new THREE.Scene();
  private camera: THREE.PerspectiveCamera;
  private renderer: THREE.WebGLRenderer;
  private controls: OrbitControls;
  private track?: Line2;
  private reference?: Line2;
  private events: THREE.Object3D[] = [];
  private ship = new THREE.Group();
  private arrows?: THREE.InstancedMesh;
  private field?: WindField;
  private material: LineMaterial;
  private dummy = new THREE.Object3D();

  constructor(private host: HTMLElement) {
    const { clientWidth, clientHeight } = host;
    this.renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.setSize(clientWidth, clientHeight);
    host.appendChild(this.renderer.domElement);
    this.camera = new THREE.PerspectiveCamera(30, clientWidth / clientHeight, 0.1, 20);
    this.camera.position.set(0, 0, 4.2);
    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.enablePan = false;
    this.controls.minDistance = 1.6;
    this.controls.maxDistance = 6;
    this.controls.enableDamping = true;
    this.controls.dampingFactor = 0.08;
    this.scene.background = new THREE.Color(colour("paper"));
    const sphere = new THREE.Mesh(
      new THREE.SphereGeometry(1, 96, 64),
      new THREE.MeshBasicMaterial({ map: landTexture(colour("sky"), colour("paper-deep"), colour("ink")) }),
    );
    this.scene.add(sphere);
    this.material = new LineMaterial({ color: new THREE.Color(colour("orange")), linewidth: 4, resolution: new THREE.Vector2(clientWidth, clientHeight) });
    const hull = new THREE.Mesh(new THREE.ConeGeometry(0.012, 0.05, 12), new THREE.MeshBasicMaterial({ color: colour("rust") }));
    hull.rotation.x = Math.PI / 2;
    const ring = new THREE.Mesh(new THREE.TorusGeometry(0.026, 0.004, 8, 32), new THREE.MeshBasicMaterial({ color: colour("rust") }));
    this.ship.add(hull, ring);
    this.scene.add(this.ship);
  }

  resize() {
    const { clientWidth, clientHeight } = this.host;
    this.camera.aspect = clientWidth / clientHeight;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(clientWidth, clientHeight);
    this.material.resolution.set(clientWidth, clientHeight);
  }

  private polyline(leg: Leg, material: LineMaterial): Line2 {
    const c = leg.columns;
    const points = c.lat.flatMap((lat, i) => surfacePoint(lat / 100, c.lon[i] / 100, 1.002).toArray());
    const geometry = new LineGeometry();
    geometry.setPositions(points);
    return new Line2(geometry, material);
  }

  showLeg(leg: Leg, reference: Leg | undefined, trackColour: string) {
    for (const old of [this.track, this.reference]) {
      if (old) {
        this.scene.remove(old);
        old.geometry.dispose();
      }
    }
    this.material.color.set(trackColour);
    this.track = this.polyline(leg, this.material);
    this.scene.add(this.track);
    this.reference = undefined;
    if (reference) {
      const dashed = new LineMaterial({ color: new THREE.Color(colour("ink")), linewidth: 1.5, opacity: 0.5, transparent: true, resolution: this.material.resolution });
      this.reference = this.polyline(reference, dashed);
      this.scene.add(this.reference);
    }
    for (const event of this.events) this.scene.remove(event);
    this.events = legEvents(leg).map(({ lat, lon, kind }) => {
      const marker = new THREE.Mesh(
        new THREE.SphereGeometry(kind === 1 ? 0.009 : 0.007, 12, 12),
        new THREE.MeshBasicMaterial({ color: colour(kind === 1 ? "teal" : kind === 3 ? "rust" : "mustard") }),
      );
      marker.position.copy(surfacePoint(lat, lon, 1.004));
      this.scene.add(marker);
      return marker;
    });
    const middle = Math.floor(leg.columns.lat.length / 2);
    const target = surfacePoint(leg.columns.lat[middle] / 100, leg.columns.lon[middle] / 100, this.camera.position.length());
    this.camera.position.copy(target);
    this.controls.update();
  }

  showWinds(field: WindField | undefined) {
    this.field = field;
    if (this.arrows) this.scene.remove(this.arrows);
    this.arrows = undefined;
    if (!field) return;
    const shape = new THREE.Shape([new THREE.Vector2(-0.3, -0.5), new THREE.Vector2(0.3, -0.5), new THREE.Vector2(0, 0.6)]);
    const geometry = new THREE.ShapeGeometry(shape);
    const count = field.nlat * field.nlon;
    this.arrows = new THREE.InstancedMesh(geometry, new THREE.MeshBasicMaterial({ color: colour("ink"), side: THREE.DoubleSide, transparent: true, opacity: 0.55 }), count);
    this.scene.add(this.arrows);
  }

  /** Move the ship to the `state` at absolute time `time`, and the wind field with it. */
  update(state: PassageState, time: number) {
    const position = surfacePoint(state.lat, state.lon, 1.01);
    this.ship.position.copy(position);
    const north = surfacePoint(state.lat + 0.5, state.lon, 1.01).sub(position).normalize();
    const east = position.clone().cross(new THREE.Vector3(0, 1, 0)).normalize().negate();
    const up = position.clone().normalize();
    const heading = THREE.MathUtils.degToRad(state.course);
    const forward = north.multiplyScalar(Math.cos(heading)).add(east.multiplyScalar(Math.sin(heading))).normalize();
    this.ship.matrix.lookAt(new THREE.Vector3(), forward.clone().negate(), up);
    this.ship.quaternion.setFromRotationMatrix(this.ship.matrix);
    if (this.arrows && this.field) this.updateArrows(this.field, time);
  }

  private updateArrows(field: WindField, time: number) {
    const { east, north } = windAt(field, time);
    for (let i = 0; i < field.nlat; i++) {
      for (let j = 0; j < field.nlon; j++) {
        const lat = field.lat0 + i * field.spacing;
        const lon = field.lon0 + j * field.spacing;
        const k = i * field.nlon + j;
        const position = surfacePoint(lat, lon, 1.005);
        const speed = Math.hypot(east[k], north[k]);
        const northward = surfacePoint(lat + 0.5, lon, 1.005).sub(position).normalize();
        const eastward = position.clone().cross(new THREE.Vector3(0, 1, 0)).normalize().negate();
        const heading = northward.multiplyScalar(north[k] || 1e-3).add(eastward.multiplyScalar(east[k] || 1e-3)).normalize();
        this.dummy.position.copy(position);
        this.dummy.up.copy(heading);
        this.dummy.lookAt(position.clone().multiplyScalar(2));
        this.dummy.scale.setScalar(0.01 + 0.0028 * speed);
        this.dummy.updateMatrix();
        this.arrows!.setMatrixAt(k, this.dummy.matrix);
      }
    }
    this.arrows!.instanceMatrix.needsUpdate = true;
  }

  render() {
    this.controls.update();
    this.renderer.render(this.scene, this.camera);
  }

  dispose() {
    this.controls.dispose();
    this.renderer.dispose();
    this.renderer.domElement.remove();
  }
}
