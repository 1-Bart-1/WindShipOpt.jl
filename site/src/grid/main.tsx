// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

import "../brand";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { GridPage } from "./GridPage";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <GridPage />
  </StrictMode>,
);
