// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

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

/** Directory of the run whose `file` the site shows: `RUN_DIRECTORY` if set, else the newest run's. */
function runDirectory(file: string): string | undefined {
  if (process.env.RUN_DIRECTORY) return resolve(process.env.RUN_DIRECTORY);
  const chosen = newestRun(file);
  return chosen ? join(runs, chosen) : undefined;
}

/** Path of the run file `file` the site shows, if that run holds it. */
function runFile(file: string): string | undefined {
  const directory = runDirectory(file);
  return directory && existsSync(join(directory, file)) ? join(directory, file) : undefined;
}

/** Path of the explorer data the site shows. */
export function explorerPath(): string {
  const path = runFile("explorer.json");
  if (!path) {
    const directory = runDirectory("explorer.json") ?? runs;
    throw new Error(`no explorer.json in ${directory}: run paper(:classes, :explorer; fidelity=:draft)`);
  }
  return path;
}

/** Directory of the routed passages the site shows, if its run holds them. */
export function passagesDirectory(): string | undefined {
  const path = runFile("passages.json");
  return path && dirname(path);
}

/** Path of the router grids the grid page shows, if its run holds them. */
export function gridsPath(): string | undefined {
  return runFile("grids.json");
}
