// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

import type { ExplorerData, Input } from "./explorer";

/** How the explorer shows one input of the model: label, unit, scale and slider step. */
export type InputControl = {
  name: string;
  label: string;
  unit: string;
  /** shown value per model value */
  scale: number;
  step: number;
  /** whether the slider keeps to a moderate change, as for a price that shifts the ship's speed */
  moderate?: boolean;
  /** upper end [model units] for an input whose range in the paper is its value alone */
  max?: number;
};

const control = (name: string, label: string, unit: string, step: number, scale = 1,
  options: { moderate?: boolean; max?: number } = {}): InputControl =>
  ({ name, label, unit, scale, step, ...options });

const percent = (name: string, label: string, step: number) => control(name, label, "%", step, 100);

/** Largest change of an input that shifts the ship's speed, as a share of its paper value. */
export const moderateChange = 0.3;

/**
 * Slider range [model units] of `input`: its range in the paper with its value known today,
 * kept within the moderate change where the control asks for it.
 */
export function inputRange(input: Input, control: InputControl): [number, number] {
  let low = Math.min(input.low, input.today, input.value);
  let high = Math.max(input.high, input.today, input.value, control.max ?? -Infinity);
  if (control.moderate) {
    low = Math.max(low, (1 - moderateChange) * input.value);
    high = Math.min(high, (1 + moderateChange) * input.value);
  }
  return [low, high];
}

/** The inputs a reader changes, in groups. */
export const inputGroups: { title: string; controls: InputControl[] }[] = [
  {
    title: "Fuel and carbon",
    controls: [
      control("vlsfo_price", "VLSFO price", "USD/GJ", 0.5, 1, { moderate: true }),
      control("e_ammonia_price", "e-ammonia price", "USD/GJ", 1, 1, { moderate: true }),
      control("carbon_price", "Carbon price", "USD/t CO₂", 5, 1, { moderate: true }),
    ],
  },
  {
    title: "Kite goals",
    controls: [
      control("canopy_life", "Canopy life", "flight h", 250),
      control("canopy_structure_cost", "Canopy fabric and bridle cost per flat m², as surveyed", "EUR/m²", 1),
      control("canopy_cloth_price_per_weight", "Cloth price per weight", "USD/g", 0.001),
      control("tether_price", "Tether price", "USD/kg", 5),
      control("tether_lifetime", "Tether life", "flight h", 500),
      control("kite_cycle_crew_cost", "Crew cost per launch", "USD", 10),
      percent("kite_launch_loss_probability", "Kite lost per launch", 0.001),
      control("kite_lifetime", "Kite hardware life", "years", 1),
    ],
  },
  {
    title: "Rig service and price",
    controls: [
      percent("kite_out_of_service", "Kite out of service", 0.5),
      percent("wing_out_of_service", "Wing out of service", 0.5),
      percent("rotor_out_of_service", "Rotor out of service", 0.5),
      percent("suction_out_of_service", "Suction sail out of service", 0.5),
      control("wing_loss_rate", "Wings or suction sails lost", "per unit·year", 0.02, 1, { max: 1 }),
      control("rotor_loss_rate", "Rotors lost", "per rotor·year", 0.02, 1, { max: 1 }),
      control("market_price_factor", "Market price over cost", "×", 0.05),
      control("wing_lifetime", "Wing life", "years", 1),
      control("rotor_lifetime", "Rotor life", "years", 1),
      control("suction_lifetime", "Suction sail life", "years", 1),
    ],
  },
  {
    title: "Money and time",
    controls: [
      percent("discount_rate", "Discount rate", 0.5),
      percent("availability", "Share of the year in trade", 1),
    ],
  },
];

/** Whether `value` differs from the paper's `base` by more than rounding. */
export const differs = (value: number, base: number) =>
  Math.abs(value - base) > 1e-9 * Math.max(1, Math.abs(base));

/** Names in `changes` whose value differs from the paper's, in the order of `changes`. */
export const changedInputs = (data: ExplorerData, changes: Record<string, number>) =>
  Object.keys(changes).filter((name) => differs(changes[name], data.inputs[name].value));

/** The factor on each ship's cargo value that the paper uses. */
export const paperCargoFactor = 1;

/** How many inputs, the cargo value's factor among them, differ from the paper's. */
export const changedCount = (data: ExplorerData, changes: Record<string, number>, cargoFactor: number) =>
  changedInputs(data, changes).length + (differs(cargoFactor, paperCargoFactor) ? 1 : 0);

/** Each goal at its value known today, by name: the changes that show what a rig saves today. */
export const todayInputs = (data: ExplorerData) =>
  Object.fromEntries(Object.entries(data.inputs)
    .filter(([, input]) => differs(input.today, input.value))
    .map(([name, input]) => [name, input.today]));

/** `changes` without `names`, which then take the paper's values. */
export const resetInputs = (changes: Record<string, number>, names: string[]) =>
  Object.fromEntries(Object.entries(changes).filter(([name]) => !names.includes(name)));
