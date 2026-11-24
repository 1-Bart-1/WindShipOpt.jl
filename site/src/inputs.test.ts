// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

import { expect, test } from "vitest";
import type { ExplorerData } from "./explorer";
import { changedInputs, inputRange, offeredControls, todayInputs, type InputControl } from "./inputs";

test("the goals at what is known today move each goal to its value today and nothing else", () => {
  const input = (value: number, today: number) => ({ value, low: 0, high: 2 * value, unit: "-", today });
  const data = { inputs: { canopy_life: input(3000, 1200), vlsfo_price: input(15, 15) } } as unknown as ExplorerData;
  expect(todayInputs(data)).toEqual({ canopy_life: 1200 });
  expect(changedInputs(data, todayInputs(data))).toEqual(["canopy_life"]);
});

test("a slider spans the input's range in the paper with its value today, a price that shifts the speed only a moderate change", () => {
  const input = { value: 40, low: 30, high: 80, unit: "USD/GJ", today: 20 };
  const control: InputControl = { name: "price", label: "Price", unit: "USD/GJ", scale: 1, step: 1 };
  expect(inputRange(input, control)).toEqual([20, 80]);
  expect(inputRange(input, { ...control, moderate: true })).toEqual([28, 52]);
  const loss = { value: 0, low: 0, high: 0, unit: "1/year", today: 0 };
  expect(inputRange(loss, { ...control, max: 1 })).toEqual([0, 1]);
});

test("an input the paper gives one value, with none known today, has no slider", () => {
  const input = (value: number, low: number, high: number, today: number) => ({ value, low, high, unit: "-", today });
  const data = { inputs: { canopy_life: input(3000, 1500, 4000, 1500), market_price_factor: input(2, 2, 2, 2),
    kite_out_of_service: input(0.03, 0.03, 0.03, 0.15), wing_loss_rate: input(0, 0, 0, 0) } } as unknown as ExplorerData;
  const control = (name: string, max?: number): InputControl => ({ name, label: name, unit: "-", scale: 1, step: 1, max });
  const offered = offeredControls(data, [control("canopy_life"), control("market_price_factor"),
    control("kite_out_of_service"), control("wing_loss_rate", 1)]);
  expect(offered.map((control) => control.name)).toEqual(["canopy_life", "kite_out_of_service", "wing_loss_rate"]);
});
