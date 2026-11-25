# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"""Print the full commit and the fidelity of the run the paper's results come from,
`\\NumResultsRun` of sections/numbers.tex, and exit 1 if it names none.
Run: python3 -I scripts/paper_run.py [paper directory]"""
import re
import sys
from pathlib import Path

RESULTS_RUN = re.compile(r"\\newcommand\{\\NumResultsRun\}"
                         r"\{the (draft|final) run at commit \\commit\{([0-9a-f]{40})\}\}$")


def results_run(numbers):
    """Commit and fidelity of the run `\\NumResultsRun` names in `numbers`, or None."""
    for line in numbers.splitlines():
        match = RESULTS_RUN.match(line)
        if match:
            return match.group(2), match.group(1)
    return None


if __name__ == "__main__":
    default = Path(__file__).parent.parent / "paper"
    paper = Path(sys.argv[1]) if len(sys.argv) > 1 else default
    run = results_run((paper / "sections" / "numbers.tex").read_text())
    if run is None:
        sys.exit("sections/numbers.tex names no results run as "
                 "`the <fidelity> run at commit \\commit{<full hash>}`")
    print(*run)
