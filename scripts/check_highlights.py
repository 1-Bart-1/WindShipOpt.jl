# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"""List each highlight of the paper longer than the journal allows, `\\NumHighlightLimit`
characters as rendered with the generated values of sections/numbers.tex put in, and exit 1
if there is one.
Run: python3 -I scripts/check_highlights.py [paper directory]"""
import re
import sys
from pathlib import Path

DEFINITION = re.compile(r"\\newcommand\{\\(Num[A-Za-z]+)\}\{(.*)\}$")
WRAPPER = re.compile(r"\\(?:tbd|given|textbf|emph)\{([^{}]*)\}"
                     r"|\\stale\{[^{}]*\}\{([^{}]*)\}")
SYMBOLS = (("\\,", " "), ("\\%", "%"), ("\\ ", " "), ("~", " "), ("--", "-"), ("{}", ""),
           ("$", ""), ("_", ""))


def values(paper):
    """Text of each generated `\\Num...` macro of `paper`, keyed by its name."""
    found = {}
    for line in (paper / "sections" / "numbers.tex").read_text().splitlines():
        match = DEFINITION.match(line)
        if match:
            found[match.group(1)] = match.group(2)
    return found


def rendered(tex, macros):
    """Plain text of LaTeX `tex` as it prints, the `macros` put in."""
    text = re.sub(r"\\(Num[A-Za-z]+)(\{\})?", lambda match: macros[match.group(1)], tex)
    while WRAPPER.search(text):
        text = WRAPPER.sub(lambda match: match.group(1) or match.group(2) or "", text)
    for symbol, printed in SYMBOLS:
        text = text.replace(symbol, printed)
    return text.strip()


def problems(paper):
    """One line per highlight of directory `paper` longer than the journal allows."""
    macros = values(paper)
    limit = int(macros["NumHighlightLimit"])
    lines = []
    for line in (paper / "sections" / "highlights.tex").read_text().splitlines():
        if not line.startswith("\\item "):
            continue
        text = rendered(line[len("\\item "):], macros)
        if len(text) > limit:
            lines.append(f"{len(text)} characters, the journal allows {limit}: {text}")
    return lines


if __name__ == "__main__":
    paper = Path(__file__).parent.parent / "paper"
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else paper
    found = problems(root)
    print("\n".join(found))
    print(f"{len(found)} highlights longer than the journal allows", file=sys.stderr)
    sys.exit(1 if found else 0)
