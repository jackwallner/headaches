#!/usr/bin/env python3
"""Audit current fastlane metadata for all locales.

Reports, per locale:
  - char counts for name / subtitle / keywords
  - cross-field duplicate words (name<->subtitle<->keyword)
  - flags: title/subtitle < 24 (Latin), keywords < 94 (Latin)

CJK/complex-script locales are flagged separately since character-count
minimums do not map across scripts (a CJK char carries far more meaning).
"""
from __future__ import annotations

import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
META = ROOT / "fastlane/metadata"

# Locales whose keyword field is space-delimited word tokens (Latin/Cyrillic/etc.)
# vs. CJK where we don't apply the 94-char minimum.
CJK = {"ja", "ko", "zh-Hans", "zh-Hant"}

NAME_MIN = 24
SUB_MIN = 24
KW_MIN = 94
NAME_MAX = 30
SUB_MAX = 30
KW_MAX = 100

STOP = {"&", "and", "y", "e", "i", "und", "et", "a", "o", "de", "un", "una",
        "con", "un", "il", "la", "le", "les", "the", "un", "ett", "en", "med",
        "og", "és", "i", "ir", "й", "и"}


def tokens(text: str) -> list[str]:
    text = text.lower()
    # split on whitespace, commas, and common separators
    raw = re.split(r"[\s,·・、，&/|]+", text)
    out = []
    for w in raw:
        w = w.strip("-–—·:;.()[]!?\"'")
        if len(w) >= 2 and w not in STOP:
            out.append(w)
    return out


def read(loc: str, field: str) -> str:
    p = META / loc / f"{field}.txt"
    return p.read_text(encoding="utf-8").strip() if p.exists() else ""


def find_dupes(name: str, sub: str, kw: str) -> list[str]:
    """Words appearing in more than one field (exact token match)."""
    n = set(tokens(name))
    s = set(tokens(sub))
    # keyword field is comma-delimited tokens
    k = set(t.strip().lower() for t in kw.split(",") if t.strip())
    dupes = []
    for w in sorted(n & s):
        dupes.append(f"name~sub:{w}")
    for w in sorted(n & k):
        dupes.append(f"name~kw:{w}")
    for w in sorted(s & k):
        dupes.append(f"sub~kw:{w}")
    return dupes


def main() -> None:
    locales = sorted(p.name for p in META.iterdir()
                     if p.is_dir() and (p / "name.txt").exists())
    print(f"{'locale':8} {'nm':>3} {'sub':>3} {'kw':>4}  flags / dupes")
    print("-" * 72)
    n_fail = 0
    for loc in locales:
        name, sub, kw = read(loc, "name"), read(loc, "subtitle"), read(loc, "keywords")
        ln, ls, lk = len(name), len(sub), len(kw)
        flags = []
        is_cjk = loc in CJK
        if not is_cjk:
            if ln < NAME_MIN:
                flags.append(f"NAME<{NAME_MIN}")
            if ls < SUB_MIN:
                flags.append(f"SUB<{SUB_MIN}")
            if lk < KW_MIN:
                flags.append(f"KW<{KW_MIN}")
        if ln > NAME_MAX:
            flags.append("NAME>30")
        if ls > SUB_MAX:
            flags.append("SUB>30")
        if lk > KW_MAX:
            flags.append("KW>100")
        dupes = find_dupes(name, sub, kw)
        tag = "CJK " if is_cjk else ""
        marker = ""
        if flags or dupes:
            marker = "  <<"
            n_fail += 1
        print(f"{loc:8} {ln:>3} {ls:>3} {lk:>4}  {tag}{' '.join(flags)}"
              f"{'  DUPES=' + ','.join(dupes) if dupes else ''}{marker}")
    print("-" * 72)
    print(f"{n_fail} locale(s) need attention out of {len(locales)}")


if __name__ == "__main__":
    main()
