// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";

const runs = resolve(import.meta.dirname, "..", "output", "runs");

/** Fidelity of the run in `directory`, from its run.toml. */
function fidelity(directory: string): string | undefined {
  const record = join(runs, directory, "run.toml");
  if (!existsSync(record)) return undefined;
  return readFileSync(record, "utf8").match(/^fidelity = "(\w+)"/m)?.[1];
}

/**
 * Path of the explorer data the site shows: `EXPLORER_JSON` if set, else the newest
 * explorer.json of a final run, else the newest of a draft run.
 */
export function explorerPath(): string {
  if (process.env.EXPLORER_JSON) return resolve(process.env.EXPLORER_JSON);
  const found = existsSync(runs)
    ? readdirSync(runs)
        .sort()
        .reverse()
        .filter((directory) => existsSync(join(runs, directory, "explorer.json")))
    : [];
  const chosen =
    found.find((directory) => fidelity(directory) === "final") ??
    found.find((directory) => fidelity(directory) === "draft");
  if (!chosen)
    throw new Error(`no explorer.json in ${runs}: run paper(:classes, :explorer; fidelity=:draft)`);
  return join(runs, chosen, "explorer.json");
}
