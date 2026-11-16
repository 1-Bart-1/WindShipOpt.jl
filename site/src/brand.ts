// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

/** The CSS value of the brand colour `name`. */
export const brandColour = (name: string) =>
  getComputedStyle(document.documentElement).getPropertyValue(`--brand-${name}`).trim();
