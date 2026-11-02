#!/usr/bin/env python3
"""Check paper/sources.csv against the citations in paper/sections and the held files.

Usage: scripts/check_sources.py [source_dir], where source_dir defaults to
/var/lib/windship/literature_pdfs. Prints each problem and exits 1 if there are any.
"""
import csv
import hashlib
import re
import sys
from pathlib import Path

PAPER = Path(__file__).resolve().parent.parent / "paper"
SOURCE_DIR = Path("/var/lib/windship/literature_pdfs")
STATUSES = {"read_in_full", "partial", "abstract_only", "held_unread", "missing"}
CITE = re.compile(r"\\[A-Za-z]*cite[A-Za-z]*\*?(?:\[[^\]]*\])*\{([^}]*)\}")
COMMENT = re.compile(r"(?<!\\)%.*")


def cited_keys(sections):
    """The keys cited in the .tex files of `sections`, ignoring LaTeX comments."""
    keys = set()
    for tex in sections.glob("*.tex"):
        text = COMMENT.sub("", tex.read_text(encoding="utf-8"))
        for group in CITE.findall(text):
            keys.update(key.strip() for key in group.split(",") if key.strip())
    return keys


def row_problems(row, source_dir):
    """What is wrong with one row of the index, checking a held file against its hash."""
    key, name, status = row["key"], row["file"], row["status"]
    if status not in STATUSES:
        return [f"{key}: unknown status {status!r}"]
    if not name:
        return [f"{key}: status {status} names no file"] if status == "held_unread" else []
    if status == "missing":
        return [f"{key}: status missing but names {name}"]
    path = source_dir / name
    if not path.is_file():
        return [f"{key}: {name} is not in {source_dir}"]
    if hashlib.sha256(path.read_bytes()).hexdigest() != row["sha256"]:
        return [f"{key}: {name} does not match its sha256"]
    return []


def problems(paper, source_dir):
    """Every way the index in `paper` disagrees with its citations and with `source_dir`."""
    with (paper / "sources.csv").open(newline="", encoding="utf-8") as index:
        rows = list(csv.DictReader(index))
    found = [line for row in rows for line in row_problems(row, source_dir)]
    status_of = {}
    for row in rows:
        if row["key"] in status_of:
            found.append(f"{row['key']}: more than one row")
        status_of[row["key"]] = row["status"]
    for key in sorted(cited_keys(paper / "sections")):
        if key not in status_of:
            found.append(f"{key}: cited but has no row")
        elif status_of[key] != "read_in_full":
            found.append(f"{key}: cited but {status_of[key]}")
    return found


def main():
    source_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else SOURCE_DIR
    if not source_dir.is_dir():
        sys.exit(f"no source directory at {source_dir}")
    found = problems(PAPER, source_dir)
    print("\n".join(found) if found else "sources.csv: all clear")
    sys.exit(1 if found else 0)


if __name__ == "__main__":
    main()
