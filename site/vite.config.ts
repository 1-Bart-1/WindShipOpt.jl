// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

import { readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig, type Plugin } from "vite";
import { explorerPath, gridsPath, passagesDirectory } from "./data";

/** Serves the run file `name` found at `path()` in development and emits it in a build, when there is one. */
function runFile(name: string, path: () => string | undefined): Plugin {
  return {
    name: `run-file-${name}`,
    configureServer(server) {
      server.middlewares.use(`/${name}`, (_request, response, next) => {
        const file = path();
        if (!file) return next();
        response.setHeader("Content-Type", "application/json");
        response.end(readFileSync(file));
      });
    },
    generateBundle() {
      const file = path();
      if (file) this.emitFile({ type: "asset", fileName: name, source: readFileSync(file) });
    },
  };
}

const passageFile = /^(passages(-[\w]+)?|winds-[\w]+)\.json$/;

/** Serves the routed passages in development and emits them in a build, when a run has them. */
function passagesData(): Plugin {
  return {
    name: "passages-data",
    configureServer(server) {
      server.middlewares.use((request, response, next) => {
        const directory = passagesDirectory();
        const name = request.url?.split("?")[0].slice(1) ?? "";
        if (!directory || !passageFile.test(name)) return next();
        response.setHeader("Content-Type", "application/json");
        response.end(readFileSync(join(directory, name)));
      });
    },
    generateBundle() {
      const directory = passagesDirectory();
      if (!directory) return;
      for (const name of readdirSync(directory).filter((file) => passageFile.test(file)))
        this.emitFile({ type: "asset", fileName: name, source: readFileSync(join(directory, name)) });
    },
  };
}

export default defineConfig({
  base: "./",
  plugins: [
    react(),
    tailwindcss(),
    runFile("explorer.json", explorerPath),
    runFile("grids.json", gridsPath),
    passagesData(),
  ],
  build: {
    rollupOptions: {
      input: { explorer: resolve(import.meta.dirname, "index.html"), grid: resolve(import.meta.dirname, "grid.html") },
    },
  },
});
