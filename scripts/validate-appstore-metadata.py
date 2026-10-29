#!/usr/bin/env python3
"""Validate App Store metadata limits and keyword hygiene for selected locales."""
from __future__ import annotations

import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
META = ROOT / "fastlane/metadata"
LIMITS = {
    "name": 30,
    "subtitle": 30,
    "keywords": 100,
    "promotional_text": 170,
    "description": 4000,
}
FIELDS = tuple(LIMITS)
WORD_SEPARATORS = re.compile(r"[^\w]+", re.UNICODE)


def read_field(locale: str, field: str) -> str:
    path = META / locale / f"{field}.txt"
    if not path.is_file():
        raise FileNotFoundError(path)
    return path.read_text(encoding="utf-8").removesuffix("\n")


def search_tokens(text: str) -> set[str]:
    normalized = unicodedata.normalize("NFKC", text).casefold()
    return {token for token in WORD_SEPARATORS.split(normalized) if token}


def validate(locale: str) -> list[str]:
    fields: dict[str, str] = {}
    errors: list[str] = []

    for field in FIELDS:
        try:
            value = read_field(locale, field)
        except FileNotFoundError as error:
            errors.append(f"{error.filename}: missing")
            continue

        fields[field] = value
        if value != value.strip():
            errors.append(f"{field}: leading or trailing whitespace")
        if chr(0x2014) in value:
            errors.append(f"{field}: contains an em dash")
        if len(value) > LIMITS[field]:
            errors.append(f"{field}: {len(value)} characters, limit {LIMITS[field]}")

    keywords = fields.get("keywords", "")
    keyword_tokens = [
        unicodedata.normalize("NFKC", token.strip()).casefold()
        for token in keywords.split(",")
    ]
    if any(not token for token in keyword_tokens):
        errors.append("keywords: empty comma-separated token")
    if any(any(char.isspace() for char in token) for token in keyword_tokens):
        errors.append("keywords: spaces inside a token")
    if re.search(r",\s", keywords):
        errors.append("keywords: whitespace after a comma")
    duplicates = sorted({token for token in keyword_tokens if keyword_tokens.count(token) > 1})
    if duplicates:
        errors.append("keywords: duplicate tokens " + ", ".join(duplicates))

    visible_tokens = search_tokens(fields.get("name", "")) | search_tokens(fields.get("subtitle", ""))
    repeated = sorted(set(keyword_tokens) & visible_tokens)
    if repeated:
        errors.append("keywords: repeats name or subtitle token(s) " + ", ".join(repeated))

    return errors


def main() -> int:
    locales = sys.argv[1:] or sorted(
        path.name for path in META.iterdir() if path.is_dir() and (path / "name.txt").is_file()
    )
    failed = False
    for locale in locales:
        counts = []
        try:
            for field in FIELDS:
                value = read_field(locale, field)
                counts.append(f"{field}={len(value)}/{LIMITS[field]}")
        except FileNotFoundError as error:
            print(f"FAIL {locale}: {error.filename} missing")
            failed = True
            continue

        errors = validate(locale)
        print(f"{'FAIL' if errors else 'PASS'} {locale}: " + ", ".join(counts))
        for error in errors:
            print(f"  - {error}")
        failed |= bool(errors)

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
