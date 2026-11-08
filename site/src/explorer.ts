import { evaluate, type RecordedNode } from "./recording";

export type Input = { value: number; low: number; high: number; unit: string };

export type Design = {
  class: number;
  route: number;
  drive: string;
  rig: string;
  area: number;
  units: number;
  /** cost per tonne-km [USD] the model computed */
  cost: number;
  /**
   * recorded nodes of the cost per tonne-km [USD] and the savings [%]; null where the ship
   * without a rig to save against cannot sail the route
   */
  nodes: { cost: number; saving: number | null; ammonia_saving: number | null; vlsfo_saving: number | null };
};

export type Check = {
  design: number;
  label: string;
  changes: Record<string, number>;
  cargo_factor: number;
  /** cost per tonne-km [USD] on the base routes, by the model */
  recosted: number;
  /** cost per tonne-km [USD] with the voyages routed again */
  rerouted: number;
};

/** The explorer data the Julia model exports: explorer.json. */
export type ExplorerData = {
  fidelity: string;
  git_commit: string;
  departures: number;
  weather: string;
  inputs: Record<string, Input>;
  classes: { name: string; type: string; deadweight: number }[];
  routes: { name: string; label: string }[];
  /** recorded node of the canopy price [USD/m²], with its value the model computed */
  canopy_price: { node: number; value: number };
  designs: Design[];
  nodes: RecordedNode[];
  checks: Check[];
};

export const rigs = ["wings", "rotors", "kite"] as const;
export const drives = ["vlsfo", "ammonia"] as const;

/** Name of the recorded input of the cargo value of class `name`. */
export const cargoInput = (name: string) => `cargo_value:${name}`;

/**
 * Values by input name: `changes`, with each class's cargo value at `cargoFactor` times its
 * base.
 */
export function inputValues(
  data: ExplorerData,
  changes: Record<string, number>,
  cargoFactor: number,
): Record<string, number> {
  const values = { ...changes };
  for (const { name } of data.classes)
    values[cargoInput(name)] = cargoFactor * data.inputs[cargoInput(name)].value;
  return values;
}

/** A design with its cost and savings at the reader's inputs. */
export type Outcome = {
  design: Design;
  cost: number;
  saving: number;
  ammoniaSaving: number;
  vlsfoSaving: number;
};

/** Value of `node` in the evaluated recording `values`, NaN for no node. */
const valueAt = (values: Float64Array, node: number | null) => (node === null ? NaN : values[node]);

/** Every design's outcome at the evaluated recording `values`. */
export const outcomes = (data: ExplorerData, values: Float64Array): Outcome[] =>
  data.designs.map((design) => ({
    design,
    cost: values[design.nodes.cost],
    saving: valueAt(values, design.nodes.saving),
    ammoniaSaving: valueAt(values, design.nodes.ammonia_saving),
    vlsfoSaving: valueAt(values, design.nodes.vlsfo_saving),
  }));

/** Evaluated recording of `data` at the input `values`. */
export const evaluated = (data: ExplorerData, values: Record<string, number>) =>
  evaluate(data.nodes, values);

/**
 * The ship without a rig and the cheapest design of each rig of class `ship` on `route`
 * with `drive`, by rig name; a rig with no feasible design is missing.
 */
export function bestDesigns(
  all: Outcome[],
  ship: number,
  route: number,
  drive: string,
): Map<string, Outcome> {
  const best = new Map<string, Outcome>();
  for (const outcome of all) {
    const { design } = outcome;
    if (design.class !== ship || design.route !== route || design.drive !== drive) continue;
    const current = best.get(design.rig);
    if (!current || outcome.cost < current.cost) best.set(design.rig, outcome);
  }
  return best;
}

/** The rig whose best design costs least among `best`, or undefined without one. */
export function bestRig(best: Map<string, Outcome>): string | undefined {
  let chosen: string | undefined;
  for (const rig of rigs)
    if (best.has(rig) && (!chosen || best.get(rig)!.cost < best.get(chosen)!.cost)) chosen = rig;
  return chosen;
}
