# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"""Tests of scripts/check_numbers.py. Run: python3 test/test_check_numbers.py"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
from check_numbers import hand_typed


def numbers(tex):
    return [number for _, number in hand_typed(tex)]


class CheckNumbers(unittest.TestCase):
    def test_hand_typed_result_is_listed(self):
        self.assertEqual(hand_typed("Intro.\nThe kite saves 23\\,\\% and leads by 1.5."),
                         [(2, "23"), (2, "1.5")])

    def test_number_in_tbd_or_colour_is_still_listed(self):
        tex = "saves \\tbd{5 to 8}\\,\\%, \\textcolor{red}{up to \\num{15000}}"
        self.assertEqual(numbers(tex), ["5", "8", "15000"])

    def test_stale_study_result_and_given_cover_their_text(self):
        tex = ("\\stale{classes,routes}{The kite saves 23\\,\\%} on the "
               "\\given{\\SI{140}{m}} ship over \\given{12} departures; "
               "\\studyresult{tow_point}{the bow costs 0.02 points}.")
        self.assertEqual(numbers(tex), [])

    def test_only_an_empty_marker_covers_a_whole_float(self):
        tex = ("\\begin{table}\\caption{\\stale{convergence}{} Error.}\n"
               "\\begin{tabular}{lr} Kite & 1.2 \\\\ \\end{tabular}\\end{table}\n"
               "\\begin{table}\\caption{Error.} 3.4 \\end{table}\n"
               "\\begin{table}\\caption{\\stale{routes}{Up to 2 points.}} 5.6 \\end{table}\n"
               "\\begin{table}\\caption{\\studyresult{tow_point}{} Saving.} 7.8 \\end{table}")
        self.assertEqual(hand_typed(tex), [(3, "3.4"), (4, "5.6")])

    def test_generated_values_references_and_layout_pass(self):
        tex = ("% 99 in a comment\n\\NumSavingOilKite\\,\\% in \\cref{tab:a2} "
               "\\citep[p.~3]{b1} CO$_2$ in 2050, \\SI{3}{m^2}\\\\[1ex] "
               "\\includegraphics[width=0.8\\textwidth]{f1} \\studyrun{forecast_live} "
               "\\cmidrule(lr){3-5}")
        self.assertEqual(numbers(tex), ["3"])

    def test_preamble_passes(self):
        tex = "\\definecolor{a}{RGB}{1,2,3}\n\\begin{document}\n4 rigs"
        self.assertEqual(hand_typed(tex), [(3, "4")])


if __name__ == "__main__":
    unittest.main()
