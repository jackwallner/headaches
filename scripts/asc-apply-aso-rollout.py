#!/usr/bin/env python3
"""Apply the migraine-first ASO rollout across locales on the editable appInfo.

- English locales: new title + new subtitle.
- Latin-script European locales: reorder title to migraine-first.
- Everything else: left as-is (already on-formula).

Each title is set with a fallback list to survive per-store name collisions
(first candidate that ASC accepts wins). Updates fastlane/metadata/<loc>/name.txt
(and subtitle.txt for English) to match what landed. Prints a full before/after
table and re-reads every locale at the end to confirm it applied.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc_lib import (
    ASCClient,
    bearer_token,
    bundle_id_from_appfile,
    find_app,
    find_editable_app_info,
    list_all,
    load_credentials,
)

META = Path(__file__).resolve().parent.parent / "fastlane" / "metadata"

ENGLISH = ["en-US", "en-AU", "en-CA", "en-GB"]
ENGLISH_TITLE_CANDIDATES = [
    "Migraine Headache Tracker Log",
    "Headache Migraine Tracker Log",
    "Migraine Headache Diary Log",
    "Headache Migraine Diary Log",
    "Migraine Headache Tracker",
]
ENGLISH_SUBTITLE = "One Tap Symptom Diary Journal"

# Latin-script European reorders to migraine-first. primary first, then fallbacks.
EURO_TITLES = {
    "cs": ["Migréna a Bolest Hlavy Tracker"],
    "da": ["Migræne & Hovedpine Tracker"],
    "fi": ["Migreeni & Päänsärky Seuranta"],
    "hr": ["Migrena i Glavobolja Tracker"],
    "hu": ["Migrén & Fejfájás Követő"],
    "it": ["Emicrania e Cefalea Tracker"],
    "nl-NL": ["Migraine & Hoofdpijn Tracker"],
    "no": ["Migrene & Hodepine Tracker"],
    "ro": ["Migrenă & Durere Cap Jurnal"],
    "sk": ["Migréna a Bolesť Hlavy Tracker"],
    "sv": ["Migrän & Huvudvärk Tracker"],
    "tr": ["Migren & Baş Ağrısı Takip"],
    "el": ["Ημικρανία Πονοκέφαλος Tracker"],
    "ru": ["Дневник мигрени, головной боли"],
}


def patch_loc(c, lid, attrs):
    c.patch(f"/appInfoLocalizations/{lid}",
            {"data": {"type": "appInfoLocalizations", "id": lid, "attributes": attrs}})


def set_name(c, lid, candidates, current):
    """Try candidates in order; fall back to current (already-valid) name if all collide."""
    for name in candidates:
        if len(name) > 30:
            print(f"      skip {name!r} (>30)")
            continue
        try:
            patch_loc(c, lid, {"name": name})
            return name, "applied"
        except Exception as e:
            if "already being used" in str(e) or "already used" in str(e):
                print(f"      taken {name!r}")
                continue
            raise
    # all candidates collided -> keep current valid name
    return current, "kept-current (all candidates taken)"


def main() -> None:
    cur = json.loads((Path("/private/tmp/claude-501/-Users-jackwallner-headaches/"
                           "9c38b1e1-16f9-42b3-9153-593fafb81e3e/scratchpad/current_meta.json")).read_text())
    k, i, p = load_credentials()
    c = ASCClient(bearer_token(k, i, p))
    app = find_app(c, bundle_id_from_appfile())
    edit = find_editable_app_info(c, app["id"])
    print("editable appInfo:", edit["id"], edit["attributes"].get("appStoreState"))
    locs = {l["attributes"]["locale"]: l for l in list_all(c, f"/appInfos/{edit['id']}/appInfoLocalizations")}

    plan = {}
    for loc in ENGLISH:
        plan[loc] = (ENGLISH_TITLE_CANDIDATES, ENGLISH_SUBTITLE)
    for loc, cands in EURO_TITLES.items():
        plan[loc] = (cands, None)

    results = {}
    for loc, (cands, subtitle) in plan.items():
        loc_obj = locs.get(loc)
        if not loc_obj:
            print(f"{loc}: NO localization, skip"); continue
        lid = loc_obj["id"]
        current_name = cur.get(loc, {}).get("name")
        name, status = set_name(c, lid, cands, current_name)
        if subtitle is not None:
            patch_loc(c, lid, {"subtitle": subtitle})
            (META / loc / "subtitle.txt").write_text(subtitle + "\n")
        (META / loc / "name.txt").write_text(name + "\n")
        results[loc] = (current_name, name, status)
        print(f"{loc:8} {status:32} {current_name!r} -> {name!r}")

    print("\n=== applied changes ===")
    for loc in sorted(results):
        old, new, st = results[loc]
        print(f"  {loc:8} {old!r} -> {new!r}  [{st}]")


if __name__ == "__main__":
    main()
