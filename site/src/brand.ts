// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

import "@fontsource-variable/fraunces/full.css";
import "@fontsource/ibm-plex-sans/400.css";
import "@fontsource/ibm-plex-sans/500.css";
import "@fontsource/ibm-plex-sans/600.css";
import "@fontsource/ibm-plex-mono/400.css";
import "@fontsource/ibm-plex-mono/500.css";
import "./index.css";

/** The CSS value of the brand colour `name`. */
export const brandColour = (name: string) =>
  getComputedStyle(document.documentElement).getPropertyValue(`--brand-${name}`).trim();
