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
      control("e_methanol_price", "e-methanol price", "USD/GJ", 15, 150, 1),
      control("hydrogen_price", "Liquid hydrogen price", "USD/kg", 1, 15, 0.1),
      control("carbon_price", "Carbon price", "USD/t CO₂", 0, 300, 5),
      percent("carbon_coverage", "Share of VLSFO emissions priced", 100, 5),
    ],
  },
  {
    title: "Kite goals",
    controls: [
      control("canopy_life", "Canopy life", "flight h", 250, 16000, 250),
      control("canopy_making_cost_per_area", "Canopy making cost", "USD/m²", 10, 200, 1),
      control("canopy_cloth_base_price", "Cloth base price", "USD/m²", 1, 20, 0.5),
      control("canopy_cloth_price_per_weight", "Cloth price per weight", "USD/g", 0.005, 0.06, 0.001),
      control("tether_price", "Tether price", "USD/kg", 20, 300, 5),
      control("tether_lifetime", "Tether life", "flight h", 1000, 40000, 500),
      control("kite_cycle_crew_cost", "Crew cost per launch", "USD", 0, 500, 10),
      percent("kite_cycle_damage_probability", "Canopy torn per launch", 2, 0.01),
      percent("kite_cycle_loss_probability", "Kite lost per launch", 1, 0.005),
      percent("kite_forced_landing_loss_probability", "Kite lost per forced landing", 20, 0.1),
      control("kite_lifetime", "Kite hardware life", "years", 5, 30, 1),
    ],
  },
  {
    title: "Rig service and price",
    controls: [
      percent("kite_out_of_service", "Kite out of service", 50, 0.5),
      percent("wing_out_of_service", "Wing out of service", 50, 0.5),
      percent("rotor_out_of_service", "Rotor out of service", 50, 0.5),
      control("kite_crash_rate", "Kite crashes", "per kite·year", 0, 5, 0.05),
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
export const exactInputs = ["kite_crash_rate", "wing_loss_rate", "rotor_loss_rate"];

/** The inputs of the canopy price; each has a counterpart `<name>_today` as built today. */
export const canopyPriceInputs = [
  "canopy_making_cost_per_area",
  "canopy_cloth_base_price",
  "canopy_cloth_price_per_weight",
];
