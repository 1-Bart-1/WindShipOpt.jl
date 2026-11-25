// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

/** The first seven characters of commit `hash`, linked to that commit on GitHub. */
export function Commit({ hash }: { hash: string }) {
  return (
    <a className="underline" href={`https://github.com/1-Bart-1/WindShipOpt.jl/commit/${hash}`}>
      {hash.slice(0, 7)}
    </a>
  );
}
