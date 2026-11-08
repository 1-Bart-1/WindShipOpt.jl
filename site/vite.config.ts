// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

import { readFileSync } from "node:fs";
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig, type Plugin } from "vite";
import { explorerPath } from "./data";

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

export default defineConfig({
  base: "./",
  plugins: [react(), tailwindcss(), explorerData()],
});
