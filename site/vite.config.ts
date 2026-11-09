// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig, type Plugin } from "vite";
import { explorerPath, passagesDirectory } from "./data";

/** Serves the explorer data at /explorer.json in development and emits it in a build. */
function explorerData(): Plugin {
  return {
    name: "explorer-data",
    configureServer(server) {
      server.middlewares.use("/explorer.json", (_request, response) => {
        response.setHeader("Content-Type", "application/json");
        response.end(readFileSync(explorerPath()));
      });
    },
    generateBundle() {
      this.emitFile({ type: "asset", fileName: "explorer.json", source: readFileSync(explorerPath()) });
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
  plugins: [react(), tailwindcss(), explorerData(), passagesData()],
});
