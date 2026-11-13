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

/** Newest run holding `file`: of a final run if there is one, else of a draft run. */
function newestRun(file: string): string | undefined {
  const found = existsSync(runs)
    ? readdirSync(runs)
        .sort()
        .reverse()
        .filter((directory) => existsSync(join(runs, directory, file)))
    : [];
  return (
    found.find((directory) => fidelity(directory) === "final") ??
    found.find((directory) => fidelity(directory) === "draft")
  );
}

/**
 * Path of the explorer data the site shows: `EXPLORER_JSON` if set, else the newest
 * explorer.json of a final run, else the newest of a draft run.
 */
export function explorerPath(): string {
  if (process.env.EXPLORER_JSON) return resolve(process.env.EXPLORER_JSON);
  const chosen = newestRun("explorer.json");
  if (!chosen)
    throw new Error(`no explorer.json in ${runs}: run paper(:classes, :explorer; fidelity=:draft)`);
  return join(runs, chosen, "explorer.json");
}

/**
 * Directory of the routed passages the site shows: `PASSAGES_DIRECTORY` if set, else the newest
 * run with a passages.json, final before draft; undefined if there is none.
 */
export function passagesDirectory(): string | undefined {
  if (process.env.PASSAGES_DIRECTORY) return resolve(process.env.PASSAGES_DIRECTORY);
  const chosen = newestRun("passages.json");
  return chosen ? join(runs, chosen) : undefined;
}

/**
 * Path of the router grids the grid page shows: `GRIDS_JSON` if set, else the newest
 * grids.json of a final run, else of a draft run; undefined if there is none.
 */
export function gridsPath(): string | undefined {
  if (process.env.GRIDS_JSON) return resolve(process.env.GRIDS_JSON);
  const chosen = newestRun("grids.json");
  return chosen ? join(runs, chosen, "grids.json") : undefined;
}
