// SPDX-FileCopyrightText: 2026 Bart van de Lint
// SPDX-License-Identifier: AGPL-3.0-or-later

/** A run's commit, as a link to it on GitHub, shown by its short hash. */
export function CommitLink({ commit }: { commit: string }) {
  return (
    <a className="underline" href={`https://github.com/1-Bart-1/WindShipOpt.jl/commit/${commit}`}>
      {commit.slice(0, 7)}
    </a>
  );
}
