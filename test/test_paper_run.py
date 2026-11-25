# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"""Tests of scripts/paper_run.py. Run: python3 test/test_paper_run.py"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
from paper_run import results_run

COMMIT = "770761c42391458d077c2ace9ccab85eb606de94"


def named(macro, fidelity, commit):
    """Definition of `\\Num<macro>` naming the run at `fidelity` of `commit`."""
    return f"\\newcommand{{\\Num{macro}}}{{the {fidelity} run at commit \\commit{{{commit}}}}}"


class ResultsRun(unittest.TestCase):
    def test_the_results_run_gives_its_commit_and_fidelity(self):
        numbers = "\n".join(["\\newcommand{\\NumHighlightLimit}{85}",
                             named("ResultsRun", "final", COMMIT),
                             named("CombinationRun", "draft", "0" * 40)])
        self.assertEqual(results_run(numbers), (COMMIT, "final"))

    def test_a_run_named_by_a_short_commit_is_no_run(self):
        numbers = ("\\newcommand{\\NumResultsRun}"
                   "{run 2026-11-20T2000 at final fidelity, commit 770761c}")
        self.assertIsNone(results_run(numbers))


if __name__ == "__main__":
    unittest.main()
