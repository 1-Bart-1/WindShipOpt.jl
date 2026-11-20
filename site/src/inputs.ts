// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

import type { ExplorerData } from "./explorer";

/** How the explorer shows one input of the model: label, scale and slider range. */
export type InputControl = {
  name: string;
  label: string;
  unit: string;
  /** shown value per model value */
  scale: number;
  min: number;
  max: number;
  step: number;
};

const control = (
  name: string,
  label: string,
  unit: string,
  min: number,
  max: number,
  step: number,
  scale = 1,
): InputControl => ({ name, label, unit, scale, min, max, step });

const percent = (name: string, label: string, max: number, step: number) =>
  control(name, label, "%", 0, max, step, 100);

/** The inputs a reader changes, in groups. */
export const inputGroups: { title: string; controls: InputControl[] }[] = [
  {
    title: "Fuel and carbon",
    controls: [
      control("vlsfo_price", "VLSFO price", "USD/GJ", 5, 40, 0.5),
      control("e_ammonia_price", "e-ammonia price", "USD/GJ", 15, 150, 1),
      control("carbon_price", "Carbon price", "USD/t CO₂", 0, 300, 5),
    ],
  },
  {
    title: "Kite goals",
    controls: [
      control("canopy_life", "Canopy life", "flight h", 250, 16000, 250),
      control("canopy_structure_cost", "Canopy fabric cost per flat m², as surveyed", "EUR/m²", 20, 150, 1),
      control("canopy_cloth_price_per_weight", "Cloth price per weight", "USD/g", 0.005, 0.06, 0.001),
      control("tether_price", "Tether price", "USD/kg", 20, 300, 5),
      control("tether_lifetime", "Tether life", "flight h", 1000, 40000, 500),
      control("kite_cycle_crew_cost", "Crew cost per launch", "USD", 0, 500, 10),
      percent("kite_launch_loss_probability", "Kite lost per launch", 1, 0.001),
      control("kite_lifetime", "Kite hardware life", "years", 5, 30, 1),
    ],
  },
  {
    title: "Rig service and price",
    controls: [
      percent("kite_out_of_service", "Kite out of service", 50, 0.5),
      percent("wing_out_of_service", "Wing out of service", 50, 0.5),
      percent("rotor_out_of_service", "Rotor out of service", 50, 0.5),
      control("wing_loss_rate", "Wings lost", "per wing·year", 0, 2, 0.02),
      control("rotor_loss_rate", "Rotors lost", "per rotor·year", 0, 2, 0.02),
      control("market_price_factor", "Market price over cost", "×", 1, 3.5, 0.05),
      control("wing_lifetime", "Wing life", "years", 10, 40, 1),
      control("rotor_lifetime", "Rotor life", "years", 10, 40, 1),
    ],
  },
  {
    title: "Money and time",
    controls: [
      percent("discount_rate", "Discount rate", 20, 0.5),
      percent("availability", "Share of the year in trade", 100, 1),
    ],
  },
];

/** Inputs whose change the explorer shows without any routing error. */
export const exactInputs = ["wing_loss_rate", "rotor_loss_rate"];

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
