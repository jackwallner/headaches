#!/usr/bin/env python3
"""Validate Google Play listing copy under android/play-assets/metadata/android.

Checks every locale folder for Play's limits (title 30, short 80, full 4000),
the house rules (no em dashes, no prices, no Apple wording, no promo words in
the title) and the required closing lines. Exit 1 on any failure.

Usage: scripts/validate-play-listing.py [--root DIR]
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "android/play-assets/metadata/android"
LIMITS = {"title.txt": 30, "short_description.txt": 80, "full_description.txt": 4000}
# Play language codes accepted by the Publishing API (fastlane supply list).
PLAY_LANGS = set(
    "af am ar az-AZ be bg bn-BD ca cs-CZ da-DK de-DE el-GR en-AU en-CA en-GB en-IN "
    "en-SG en-US en-ZA es-419 es-ES es-US et eu-ES fa fi-FI fil fr-CA fr-FR gl-ES "
    "hi-IN hr hu-HU hy-AM id is-IS it-IT iw-IL ja-JP ka-GE km-KH kn-IN ko-KR ky-KG "
    "lo-LA lt lv mk-MK ml-IN mn-MN mr-IN ms ms-MY my-MM ne-NP nl-NL no-NO pl-PL "
    "pt-BR pt-PT rm ro ru-RU si-LK sk sl sr sv-SE sw ta-IN te-IN th tr-TR uk vi "
    "zh-CN zh-HK zh-TW zu".split()
)
TITLE_BANNED = re.compile(r"\b(free|best|top|#1|new|sale)\b", re.I)
PRICE = re.compile(r"[$€£¥₹]\s?\d|\d[.,]\d\d\s?(?:€|zł|kr|lei|Kč|₺|₽|₴)")
APPLE = re.compile(r"Apple|App Store|iPhone|iCloud|Apple Watch", re.I)
URL_OK = re.compile(r"https://jackwallner\.github\.io/\S+")
MEDICAL = re.compile(r"\b(cures?|treats?|treatment|diagnos\w*)\b", re.I)
EXPECTED = set(
    "en-US en-GB en-AU en-CA en-IN de-DE fr-FR fr-CA es-ES es-419 es-US pt-BR pt-PT it-IT "
    "nl-NL sv-SE no-NO da-DK fi-FI pl-PL cs-CZ sk sl hr hu-HU ro el-GR tr-TR ru-RU uk ar "
    "iw-IL hi-IN bn-BD mr-IN ta-IN te-IN kn-IN ml-IN id ms ms-MY th vi ja-JP ko-KR zh-CN "
    "zh-TW zh-HK ca".split()
)
# Word for "English" in each locale; the last line of every non-English description must use it.
ENGLISH_WORD = {
    "de-DE": "Englisch",
    "fr-FR": "anglais",
    "fr-CA": "anglais",
    "es-ES": "inglés",
    "es-419": "inglés",
    "es-US": "inglés",
    "pt-BR": "inglês",
    "pt-PT": "inglês",
    "it-IT": "inglese",
    "nl-NL": "Engels",
    "sv-SE": "engelska",
    "no-NO": "engelsk",
    "da-DK": "engelsk",
    "fi-FI": "englanninkielinen",
    "pl-PL": "angielskim",
    "cs-CZ": "angličtině",
    "sk": "angličtine",
    "sl": "angleščini",
    "hr": "engleskom",
    "hu-HU": "angol",
    "ro": "engleză",
    "el-GR": "αγγλικά",
    "tr-TR": "İngilizce",
    "ru-RU": "английском",
    "uk": "англійською",
    "ar": "الإنجليزية",
    "iw-IL": "באנגלית",
    "hi-IN": "अंग्रेज़ी",
    "bn-BD": "ইংরেজি",
    "mr-IN": "इंग्रजी",
    "ta-IN": "ஆங்கிலத்தில்",
    "te-IN": "ఇంగ్లీష్‌లో",
    "kn-IN": "ಇಂಗ್ಲಿಷ್‌ನಲ್ಲಿ",
    "ml-IN": "ഇംഗ്ലീഷിലാണ്",
    "id": "Inggris",
    "ms": "Inggeris",
    "ms-MY": "Inggeris",
    "th": "ภาษาอังกฤษ",
    "vi": "tiếng Anh",
    "ca": "anglès",
    "ja-JP": "英語",
    "ko-KR": "영어",
    "zh-CN": "英文",
    "zh-TW": "英文",
    "zh-HK": "英文"
}



def check(locale_dir: Path) -> list[str]:
    errs: list[str] = []
    loc = locale_dir.name
    if loc not in PLAY_LANGS:
        errs.append(f"unknown Play language code {loc}")
    for name, limit in LIMITS.items():
        p = locale_dir / name
        if not p.exists():
            errs.append(f"missing {name}")
            continue
        text = p.read_text(encoding="utf-8").strip()
        n = len(text)
        if n == 0 or n > limit:
            errs.append(f"{name} {n}/{limit}")
        if "\u2014" in text:
            errs.append(f"{name} has an em dash")
        if re.search("[\u00ad\u200b\ufeff]", text):
            errs.append(f"{name} has an invisible character")
        if PRICE.search(text):
            errs.append(f"{name} looks like it has a price: {PRICE.search(text).group(0)!r}")
        if APPLE.search(URL_OK.sub("", text)):
            errs.append(f"{name} mentions Apple wording: {APPLE.search(text).group(0)!r}")
        if name != "full_description.txt" and "\n" in text:
            errs.append(f"{name} spans lines")
    title = (locale_dir / "title.txt").read_text(encoding="utf-8") if (locale_dir / "title.txt").exists() else ""
    if TITLE_BANNED.search(title):
        errs.append(f"title has a promo word: {title.strip()!r}")
    full = (locale_dir / "full_description.txt").read_text(encoding="utf-8") if (locale_dir / "full_description.txt").exists() else ""
    if "Open-Meteo" not in full or "Health Connect" not in full:
        errs.append("full description lacks the Open-Meteo or Health Connect line")
    if MEDICAL.search(full):
        errs.append(f"medical claim wording: {MEDICAL.search(full).group(0)!r}")
    if not loc.startswith("en"):
        word = ENGLISH_WORD.get(loc)
        if word is None:
            errs.append("no English-notice word registered for this locale")
        elif word not in full.strip().split("\n")[-1]:
            errs.append(f"last line must say the app is in English ({word!r})")
    elif loc != "en-US" and loc not in ("en-GB", "en-AU", "en-CA", "en-IN"):
        errs.append("unexpected English locale")
    return errs


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, default=ROOT)
    args = ap.parse_args()
    bad = 0
    have = {d.name for d in args.root.iterdir() if d.is_dir()}
    if have != EXPECTED:
        print(f"locale set mismatch: missing {sorted(EXPECTED - have)} extra {sorted(have - EXPECTED)}")
        bad += 1
    dirs = sorted(d for d in args.root.iterdir() if d.is_dir())
    for d in dirs:
        errs = check(d)
        t = (d / "title.txt").read_text(encoding="utf-8").strip() if (d / "title.txt").exists() else ""
        s = (d / "short_description.txt").read_text(encoding="utf-8").strip() if (d / "short_description.txt").exists() else ""
        f = (d / "full_description.txt").read_text(encoding="utf-8").strip() if (d / "full_description.txt").exists() else ""
        status = "OK " if not errs else "BAD"
        print(f"{status} {d.name:7} t{len(t):>3} s{len(s):>3} f{len(f):>5}  {t}")
        for e in errs:
            print(f"      - {e}")
        bad += bool(errs)
    print(f"\n{len(dirs)} locales, {bad} with problems")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
