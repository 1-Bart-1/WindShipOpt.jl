# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"""Tests of scripts/check_sources.py. Run: python3 test/test_check_sources.py"""
import hashlib
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
from check_sources import NOTE_TABLES, PAPER, free_text_sources, problems

HEADER = "key,doi,file,sha256,status\n"
CONTENT = b"full text"
HASH = hashlib.sha256(CONTENT).hexdigest()


HELD = f"held,,held.pdf,{HASH},read_in_full\n"
OTHER = f"other,,held.pdf,{HASH},read_in_full\n"


class CheckSources(unittest.TestCase):
    def check(self, rows, tex=r"\citep[p.~3]{held, other} \citet{held}", note=""):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "sections").mkdir()
            (root / "sections" / "a.tex").write_text(tex)
            for table in NOTE_TABLES:
                (root / "sections" / table).write_text(note)
            (root / "sources.csv").write_text(HEADER + rows)
            (root / "held.pdf").write_bytes(CONTENT)
            return problems(root, root)

    def test_clean_index_passes(self):
        self.assertEqual(self.check(HELD + OTHER), [])

    def test_cited_key_without_row_fails(self):
        self.assertEqual(self.check(HELD), ["other: cited but has no row"])

    def test_cited_key_not_read_in_full_fails(self):
        for status in ("partial", "abstract_only", "held_unread"):
            rows = f"held,,held.pdf,{HASH},{status}\n" + OTHER
            self.assertEqual(self.check(rows), [f"held: cited but {status}"])

    def test_uncited_unread_source_passes(self):
        self.assertEqual(self.check(HELD + OTHER + "spare,,,,missing\n"), [])

    def test_changed_file_fails(self):
        rows = f"held,,held.pdf,{'0' * 64},read_in_full\n" + OTHER
        self.assertEqual(self.check(rows), ["held: held.pdf does not match its sha256"])

    def test_file_not_held_fails(self):
        found = self.check(f"held,,gone.pdf,{HASH},read_in_full\n" + OTHER)
        self.assertEqual(len(found), 1)
        self.assertIn("held: gone.pdf is not in ", found[0])

    def test_status_claiming_a_held_file_needs_one(self):
        for status in ("read_in_full", "held_unread"):
            found = self.check(HELD + OTHER + f"spare,,,,{status}\n")
            self.assertEqual(found, [f"spare: status {status} names no file"])

    def test_source_without_a_file_may_be_partly_known(self):
        for status in ("partial", "abstract_only", "missing"):
            self.assertEqual(self.check(HELD + OTHER + f"spare,,,,{status}\n"), [])

    def test_missing_source_names_no_file(self):
        found = self.check(HELD + OTHER + f"spare,,held.pdf,{HASH},missing\n")
        self.assertEqual(found, ["spare: status missing but names held.pdf"])

    def test_unknown_status_fails(self):
        found = self.check(HELD + OTHER + "spare,,,,skimmed\n")
        self.assertEqual(found, ["spare: unknown status 'skimmed'"])

    def test_duplicate_row_fails(self):
        self.assertEqual(self.check(HELD + OTHER + OTHER), ["other: more than one row"])

    def test_table_citation_of_unread_source_fails(self):
        tex = r"(\citealp[Ch. 2]{held}; \citealp{other}) \citet{held}"
        rows = HELD + f"other,,held.pdf,{HASH},held_unread\n"
        self.assertEqual(self.check(rows, tex), ["other: cited but held_unread"])

    def test_commented_citation_is_not_a_citation(self):
        self.assertEqual(self.check(HELD, r"\cite{held} % \cite{other}"), [])

    def test_source_named_in_words_in_a_note_fails(self):
        for words in ("Smith et al. (2020)", "Smith 2020", r"Smith \& Jones, 2020a",
                      "the maker's 2024 datasheet"):
            note = f"x & Price per kW from {words}, 5 \\% margin. \\\\"
            found = self.check(HELD + OTHER, note=note)
            self.assertEqual(len(found), len(NOTE_TABLES), words)
            self.assertIn("names a source without its key", found[0])

    def test_dates_and_years_beside_a_key_pass(self):
        note = (r"Price on 23 Oct 2026 (\citealp[p. 7]{held}), Norsepower's 2019 prices "
                r"(\citealp{other}), the 2025 wage scale, Brent in 2025 (\citealp{held}).")
        self.assertEqual(self.check(HELD + OTHER, note=note), [])

    def test_notes_of_the_paper_name_every_source_by_key(self):
        self.assertEqual(free_text_sources(PAPER / "sections"), [])


if __name__ == "__main__":
    unittest.main()
