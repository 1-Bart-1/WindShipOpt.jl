# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"""Tests of scripts/check_highlights.py. Run: python3 test/test_check_highlights.py"""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
from check_highlights import problems, rendered


def paper(test, numbers, highlights):
    """Paper directory of `numbers` and `highlights`, removed when `test` ends."""
    directory = tempfile.TemporaryDirectory()
    test.addCleanup(directory.cleanup)
    root = Path(directory.name)
    (root / "sections").mkdir()
    (root / "sections" / "numbers.tex").write_text(numbers)
    (root / "sections" / "highlights.tex").write_text(highlights)
    return root


class CheckHighlights(unittest.TestCase):
    def test_generated_values_and_markers_render_as_printed(self):
        macros = {"NumSaving": "\\tbd{12}", "NumAdvice": "\\tbd{On e-ammonia: kite.}"}
        self.assertEqual(rendered("\\stale{classes}{\\NumAdvice{}}", macros),
                         "On e-ammonia: kite.")
        self.assertEqual(rendered("Saves \\NumSaving\\,\\% of CO$_2$.", macros),
                         "Saves 12 % of CO2.")
        self.assertEqual(rendered("A \\SI{\\num{1300}}{m} ship.", macros), "A 1300 m ship.")

    def test_a_highlight_over_the_limit_is_listed(self):
        numbers = ("\\newcommand{\\NumHighlightLimit}{20}\n"
                   "\\newcommand{\\NumAdvice}{\\tbd{Use the kite on every ship type.}}\n")
        root = paper(self, numbers,
                     "% header\n\\item Short.\n\\item \\stale{a}{\\NumAdvice{}}\n")
        self.assertEqual(problems(root), ["32 characters, the journal allows 20: "
                                          "Use the kite on every ship type."])

    def test_a_highlight_using_an_undefined_value_is_listed(self):
        root = paper(self, "\\newcommand{\\NumHighlightLimit}{85}\n",
                     "\\item \\NumMissing{}.\n")
        self.assertEqual(problems(root),
                         ["\\NumMissing is not in sections/numbers.tex: \\NumMissing{}."])


if __name__ == "__main__":
    unittest.main()
