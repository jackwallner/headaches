#!/usr/bin/env python3
"""2026-Q3 re-optimization pass (all 50 ASC locales).

Rules enforced (per user directive + ~/Desktop/aso.md):
  - Keep the working migraine-first NAMES untouched (live, ranking #1-5 on combos).
  - No repeated word across name / subtitle / keyword field (exact token match,
    case-insensitive). Repetition adds zero weight on iOS — it wastes characters.
  - Fix the 4 cross-field duplicate locales via subtitle swaps (>=24 chars, no
    word shared with the name).
  - Keyword field packed to >=94 chars for non-CJK locales (English cognates that
    already appear in the app's tracked keyword set are the validated pad pool),
    capped at 100. CJK locales expanded densely with validated CJK terms but not
    forced to 94 (a CJK char carries far more meaning; padding = junk).
  - Latin/Cyrillic title & subtitle target >=24 chars; non-Latin dense scripts
    (Arabic/Hebrew/Thai/Indic/CJK) are treated as compliant at their natural
    length -- padding them would corrupt native phrasing.

Names are never rewritten here. Only subtitle (3 overrides) + keywords (all).
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
META = ROOT / "fastlane/metadata"
KW_MAX = 100
KW_TARGET = 94  # non-CJK minimum

CJK = {"ja", "ko", "zh-Hans", "zh-Hant"}

# --- Subtitle overrides: fix name<->subtitle duplicate words (all >=24 chars) ---
SUB_OVERRIDE: dict[str, str] = {
    # name "Migrenă & Durere Cap Jurnal" already owns "jurnal" -> drop it from subtitle
    "ro": "Simptome într-o atingere",          # 24
    # name "Дневник мигрени, головной боли" owns "дневник" -> use журнал in subtitle
    "ru": "Журнал симптомов, 1 касание",        # 26
    # name "Nhật ký Migraine & Đau đầu" owns "nhật ký" -> record symptoms one tap
    "vi": "Ghi triệu chứng một chạm",           # 24
}

# --- Explicit keyword removals beyond exact-match dedup (inflected duplicates) ---
# ru name carries головной/боли/мигрени; kw had головная/боль/мигрень (same lemmas).
KW_REMOVE: dict[str, set[str]] = {
    "ru": {"головная", "боль", "мигрень"},
}

# --- Native surplus pad pools (validated in Astro tracked set), highest value first ---
PAD_NATIVE: dict[str, list[str]] = {
    "ru": ["облегчение", "напряжение", "прогноз", "простой"],
    "ja": ["ウォッチ", "ウィジェット", "エクスポート", "ログ"],
    "ko": ["워치", "위젯", "보내기", "의사", "로그"],
    "zh-Hans": ["手表", "小组件", "导出"],
    "zh-Hant": ["手錶", "小工具", "匯出"],
}

# --- English cognate pad pool (all appear in the app's tracked keyword universe) ---
PAD_ENGLISH = [
    "diary", "pain", "trigger", "relief", "forecast", "pressure",
    "cluster", "tension", "chronic", "export", "symptom", "doctor",
    "health", "aura", "log", "watch", "widget", "barometric",
]


def read(loc: str, field: str) -> str:
    p = META / loc / f"{field}.txt"
    return p.read_text(encoding="utf-8").strip() if p.exists() else ""


def write(loc: str, field: str, value: str) -> None:
    (META / loc / f"{field}.txt").write_text(value + "\n", encoding="utf-8")


def name_sub_tokens(name: str, sub: str) -> set[str]:
    text = f"{name} {sub}".lower()
    toks = set()
    for w in re.split(r"[\s,·・、，&/|]+", text):
        w = w.strip("-–—·:;.()[]!?\"'")
        if len(w) >= 2:
            toks.add(w)
    return toks


def build_kw(loc: str, name: str, sub: str, cur_kw: str) -> str:
    blocked = name_sub_tokens(name, sub)
    remove = KW_REMOVE.get(loc, set())
    out: list[str] = []
    seen: set[str] = set()

    def add(term: str) -> bool:
        t = term.strip()
        tl = t.lower()
        if not t or tl in seen or tl in blocked or tl in remove:
            return False
        candidate = ",".join(out + [t])
        if len(candidate) > KW_MAX:
            return False
        out.append(t)
        seen.add(tl)
        return True

    # 1. keep surviving existing terms (order preserved), deduped vs name/sub
    for raw in cur_kw.split(","):
        add(raw)

    # 2. native surplus pad (CJK expansion / ru relief-tension-forecast-simple)
    for term in PAD_NATIVE.get(loc, []):
        add(term)

    # 3. English cognate pad to reach >=94 (non-CJK only)
    if loc not in CJK:
        for term in PAD_ENGLISH:
            if len(",".join(out)) >= KW_TARGET:
                break
            add(term)

    return ",".join(out)


def main() -> None:
    locales = sorted(p.name for p in META.iterdir()
                     if p.is_dir() and (p / "name.txt").exists())
    report: dict[str, dict] = {}
    for loc in locales:
        name = read(loc, "name")
        old_sub = read(loc, "subtitle")
        old_kw = read(loc, "keywords")
        new_sub = SUB_OVERRIDE.get(loc, old_sub)
        new_kw = build_kw(loc, name, new_sub, old_kw)
        if new_sub != old_sub:
            write(loc, "subtitle", new_sub)
        if new_kw != old_kw:
            write(loc, "keywords", new_kw)
        report[loc] = {
            "name": {"val": name, "len": len(name)},
            "subtitle": {"old": old_sub, "new": new_sub, "len": len(new_sub),
                         "changed": new_sub != old_sub},
            "keywords": {"old": old_kw, "new": new_kw, "len": len(new_kw),
                         "changed": new_kw != old_kw},
        }
    out = ROOT / "scripts" / "aso-reoptimize-2026q3-report.json"
    out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    n_sub = sum(1 for r in report.values() if r["subtitle"]["changed"])
    n_kw = sum(1 for r in report.values() if r["keywords"]["changed"])
    print(f"Processed {len(report)} locales -> {out.name}")
    print(f"  subtitle changed: {n_sub}")
    print(f"  keywords changed: {n_kw}")


if __name__ == "__main__":
    main()
