// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

import "./brand";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
