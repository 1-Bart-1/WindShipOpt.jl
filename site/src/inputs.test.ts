// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

import { expect, test } from "vitest";
import type { ExplorerData } from "./explorer";
import { changedInputs, todayInputs } from "./inputs";

test("the goals at what is known today move each goal to its value today and nothing else", () => {
  const input = (value: number, today: number) => ({ value, low: 0, high: 2 * value, unit: "-", today });
  const data = { inputs: { canopy_life: input(3000, 1200), vlsfo_price: input(15, 15) } } as unknown as ExplorerData;
  expect(todayInputs(data)).toEqual({ canopy_life: 1200 });
  expect(changedInputs(data, todayInputs(data))).toEqual(["canopy_life"]);
});
