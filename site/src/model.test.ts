// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

import { readFileSync } from "node:fs";
import { expect, test } from "vitest";
import { explorerPath } from "../data";
import { evaluated, inputValues, type ExplorerData } from "./explorer";
import { changedInputs, inputGroups, resetInputs } from "./inputs";
import { evaluate, type RecordedNode } from "./recording";

const data: ExplorerData = JSON.parse(readFileSync(explorerPath(), "utf8"));
const gap = (shown: number, model: number) => Math.abs(shown - model) / Math.abs(model);

test("an operation is evaluated on its operands, an input at its base unless given", () => {
  const nodes: RecordedNode[] = [["input", "price", 2], ["constant", 3], ["*", 0, 1], ["-", 2], ["^", 0, 1]];
  expect([...evaluate(nodes, {})]).toEqual([2, 3, 6, -6, 8]);
  expect([...evaluate(nodes, { price: 4 })]).toEqual([4, 3, 12, -12, 64]);
});

test("the site gives the model's cost of every design at the paper's inputs", () => {
  const values = evaluated(data, inputValues(data, {}, 1));
  const worst = Math.max(...data.designs.map((design) => gap(values[design.nodes.cost], design.cost)));
  expect(worst).toBeLessThan(1e-12);
});

test("the site gives the model's canopy price at the paper's inputs", () => {
  const values = evaluated(data, inputValues(data, {}, 1));
  expect(gap(values[data.canopy_price.node], data.canopy_price.value)).toBeLessThan(1e-12);
});

test("the site gives the model's cost at changed inputs on the routes of the paper's", () => {
  expect(data.checks.length).toBeGreaterThan(0);
  for (const check of data.checks) {
    const values = evaluated(data, inputValues(data, check.changes, check.cargo_factor));
    expect(gap(values[data.designs[check.design].nodes.cost], check.recosted), check.label).toBeLessThan(1e-12);
  }
}, 120_000);

test("resetting each input, or all at once, gives back exactly the paper's inputs", () => {
  const names = inputGroups.flatMap((group) => group.controls.map((control) => control.name));
  const moved = Object.fromEntries(names.map((name) => [name, 1.5 * data.inputs[name].value + 0.01]));
  expect(changedInputs(data, moved)).toEqual(names);
  const paper = evaluated(data, inputValues(data, {}, 1));
  let changes = moved;
  for (const name of names) changes = resetInputs(changes, [name]);
  expect(changedInputs(data, changes)).toEqual([]);
  expect(evaluated(data, inputValues(data, changes, 1))).toEqual(paper);
  expect(evaluated(data, inputValues(data, resetInputs(moved, names), 1))).toEqual(paper);
});
