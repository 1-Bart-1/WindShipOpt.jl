"""Tests of scripts/check_sources.py. Run: python3 test/test_check_sources.py"""
import hashlib
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
from check_sources import problems

HEADER = "key,doi,file,sha256,status\n"
CONTENT = b"full text"
HASH = hashlib.sha256(CONTENT).hexdigest()


class CheckSources(unittest.TestCase):
    def check(self, rows, tex=r"\citep[p.~3]{held, other} \citet{held}"):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "sections").mkdir()
            (root / "sections" / "a.tex").write_text(tex)
            (root / "sources.csv").write_text(HEADER + rows)
            (root / "held.pdf").write_bytes(CONTENT)
            return problems(root, root)

    def test_clean_index_passes(self):
        rows = f"held,,held.pdf,{HASH},read_in_full\nother,,held.pdf,{HASH},read_in_full\n"
        self.assertEqual(self.check(rows), [])

    def test_cited_key_without_row_fails(self):
        found = self.check(f"held,,held.pdf,{HASH},read_in_full\n")
        self.assertEqual(found, ["other: cited but has no row"])

    def test_cited_key_not_read_in_full_fails(self):
        for status in ("partial", "abstract_only", "held_unread"):
            rows = f"held,,held.pdf,{HASH},{status}\nother,,held.pdf,{HASH},read_in_full\n"
            self.assertEqual(self.check(rows), [f"held: cited but {status}"])

    def test_uncited_unread_source_passes(self):
        rows = f"held,,held.pdf,{HASH},read_in_full\nother,,held.pdf,{HASH},read_in_full\nspare,,,,missing\n"
        self.assertEqual(self.check(rows), [])

    def test_changed_file_fails(self):
        rows = f"held,,held.pdf,{'0' * 64},read_in_full\nother,,held.pdf,{HASH},read_in_full\n"
        self.assertEqual(self.check(rows), ["held: held.pdf does not match its sha256"])

    def test_file_not_held_fails(self):
        rows = f"held,,gone.pdf,{HASH},read_in_full\nother,,held.pdf,{HASH},read_in_full\n"
        self.assertEqual(len(self.check(rows)), 1)

    def test_commented_citation_is_not_a_citation(self):
        rows = f"held,,held.pdf,{HASH},read_in_full\n"
        self.assertEqual(self.check(rows, r"\cite{held} % \cite{other}"), [])


if __name__ == "__main__":
    unittest.main()
