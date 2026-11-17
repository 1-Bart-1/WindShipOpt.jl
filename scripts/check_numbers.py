# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"""List each number typed by hand in the paper's result-bearing text that is neither a
generated value nor inside \\stale{studies}{...} or \\given{...}, and exit 1 if there is
one. Run: python3 -I scripts/check_numbers.py [paper directory]"""
import re
import sys
from pathlib import Path

RESULT_FILES = ("sections/abstract.tex", "sections/highlights.tex",
                "sections/results.tex", "sections/certainty.tex",
                "sections/discussion.tex", "sections/industry.tex",
                "sections/conclusions.tex", "sections/trust.tex",
                "extended_abstract.tex")

# Commands whose every argument holds no number of the text: markers, references,
# file names and layout.
SKIPPED = {"stale", "given", "cref", "Cref", "ref", "eqref", "label", "cite", "citep",
           "citet", "citealp", "input", "include", "plot", "includegraphics",
           "studyrun", "url", "begin", "end", "si", "textsubscript", "textsuperscript",
           "hspace", "vspace", "setlength", "addtolength", "cmidrule", "rule",
           "resizebox", "scalebox", "fontsize", "color"}
# Commands with the brace arguments, counted from 0, that hold a unit, a count or a colour.
SKIPPED_ARGUMENTS = {"SI": (1,), "SIrange": (2,), "multicolumn": (0, 1), "href": (0,),
                     "textcolor": (0,)}

COMMAND = re.compile(r"\\([A-Za-z]+)\*?")
NUMBER = re.compile(r"(?<![A-Za-z0-9.])\d[\d,.]*")
DIMENSION = re.compile(r"\s*(pt|em|ex|cm|mm|in|bp|\\(text|line|column)width)\b")
YEAR = re.compile(r"(19|20)\d\d")
FLOAT = re.compile(r"\\begin\{(table|figure|longtable)\*?\}.*?\\end\{\1\*?\}", re.S)
FLOAT_MARKER = re.compile(r"\\stale\{[^}]*\}\{\}")


def group_end(text, start):
    """Index after the brace, bracket or parenthesis group opening at `start`."""
    close = {"{": "}", "[": "]", "(": ")"}[text[start]]
    depth = 0
    for index in range(start, len(text)):
        if text[index] == text[start] and text[index - 1] != "\\":
            depth += 1
        elif text[index] == close and text[index - 1] != "\\":
            depth -= 1
            if depth == 0:
                return index + 1
    return len(text)


def blank(text, start, stop):
    """`text` with the characters from `start` to `stop` blanked, line breaks kept."""
    return text[:start] + re.sub(r"[^\n]", " ", text[start:stop]) + text[stop:]


def arguments(text, index):
    """Spans of the groups in brackets, braces or parentheses that follow `index`
    directly."""
    spans = []
    while index < len(text) and text[index] in "[{(":
        stop = group_end(text, index)
        spans.append((index, stop))
        index = stop
    return spans


def masked(text):
    """`text` with comments, the preamble, floats marked whole by \\stale{studies}{}, units,
    subscripts, superscripts and the arguments of `SKIPPED` and `SKIPPED_ARGUMENTS`
    blanked: what is left is the typed text whose numbers count."""
    text = re.sub(r"(?<!\\)%[^\n]*", lambda match: " " * len(match.group()), text)
    text = blank(text, 0, max(text.find("\\begin{document}"), 0))
    for match in FLOAT.finditer(text):
        if FLOAT_MARKER.search(match.group()):
            text = blank(text, match.start(), match.end())
    text = re.sub(r"[_^](\{[^}]*\}|\\?[A-Za-z0-9]+)",
                  lambda match: " " * len(match.group()), text)
    for match in reversed(list(COMMAND.finditer(text))):
        name = match.group(1)
        spans = arguments(text, match.end())
        braces = [span for span in spans if text[span[0]] == "{"]
        skipped = [span for span in spans if text[span[0]] in "[("]
        if name in SKIPPED:
            skipped = spans + [(match.start(), match.end())]
        elif name in SKIPPED_ARGUMENTS:
            skipped += [braces[i] for i in SKIPPED_ARGUMENTS[name] if i < len(braces)]
        for start, stop in skipped:
            text = blank(text, start, stop)
    return text


def hand_typed(text):
    """Line number and text of each number typed by hand in LaTeX source `text`."""
    plain = masked(text)
    found = []
    for match in NUMBER.finditer(plain):
        number = match.group().rstrip(".,")
        if YEAR.fullmatch(number) or DIMENSION.match(plain, match.end()):
            continue
        line = plain.count("\n", 0, match.start()) + 1
        found.append((line, number))
    return found


def problems(paper):
    """One line per hand-typed number in the `RESULT_FILES` of directory `paper`."""
    lines = []
    for name in RESULT_FILES:
        for line, number in hand_typed((paper / name).read_text()):
            lines.append(f"paper/{name}:{line}: {number} typed by hand: generate it, "
                         "or mark it \\stale{<study>}{...} or \\given{...}")
    return lines


if __name__ == "__main__":
    paper = Path(__file__).parent.parent / "paper"
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else paper
    found = problems(root)
    print("\n".join(found))
    print(f"{len(found)} result numbers typed by hand outside a marker", file=sys.stderr)
    sys.exit(1 if found else 0)
