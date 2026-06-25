#!/usr/bin/env python3
"""Resolve per-storefront app-name collisions on the editable appInfo.

For each locale, try candidate names in order until one is accepted by ASC
(name uniqueness is enforced per territory). Also (re)applies the subtitle,
since the failed appInfoLocalization update carried both name and subtitle.

Prints the winning name per locale; updates fastlane/metadata/<loc>/name.txt
to match so deliver stays consistent.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc_lib import (
    ASCClient,
    bearer_token,
    bundle_id_from_appfile,
    find_app,
    list_all,
    load_credentials,
)

# Candidate names per locale, most-preferred first. Subtitle is fixed per locale.
CANDIDATES = {
    "en-US": (
        ["Migraine & Headache Tracker", "Headache & Migraine Diary",
         "Headache & Migraine Log", "Headache Migraine Tracker"],
        "One Tap Easy Symptom Diary Log",
    ),
    "de-DE": (
        ["Migräne & Kopfschmerz Tracker", "Migräne & Kopfschmerz Diary",
         "Migräne & Kopfschmerz Log", "Kopfschmerz & Migräne Diary"],
        "Symptom-Tagebuch, ein Tipp",
    ),
    "fr-CA": (
        ["Suivi Maux de Tête & Migraine", "Migraine & Maux de Tête Suivi",
         "Journal Migraine & Céphalée", "Suivi Migraine & Céphalée"],
        "Journal symptômes, un geste",
    ),
    "fr-FR": (
        ["Suivi Céphalées & Migraine", "Migraine & Céphalées Suivi",
         "Journal Migraine & Céphalées", "Suivi Migraine & Maux de Tête"],
        "Journal symptômes, un geste",
    ),
}

META = Path(__file__).resolve().parent.parent / "fastlane" / "metadata"


def main() -> None:
    k, i, p = load_credentials()
    c = ASCClient(bearer_token(k, i, p))
    app = find_app(c, bundle_id_from_appfile())
    infos = list_all(c, f"/apps/{app['id']}/appInfos")
    edit = next(x for x in infos if x["attributes"].get("appStoreState") == "PREPARE_FOR_SUBMISSION")
    locs = {l["attributes"]["locale"]: l for l in list_all(c, f"/appInfos/{edit['id']}/appInfoLocalizations")}

    results = {}
    for locale, (names, subtitle) in CANDIDATES.items():
        loc = locs.get(locale)
        if not loc:
            print(f"{locale}: NO localization found, skipping")
            continue
        lid = loc["id"]
        won = None
        for name in names:
            if len(name) > 30:
                print(f"{locale}: skip {name!r} (>30 chars)")
                continue
            try:
                c.patch(
                    f"/appInfoLocalizations/{lid}",
                    {"data": {"type": "appInfoLocalizations", "id": lid,
                              "attributes": {"name": name, "subtitle": subtitle}}},
                )
                won = name
                print(f"{locale}: OK -> {name!r}")
                break
            except Exception as e:
                msg = str(e)
                if "already being used" in msg or "already used" in msg:
                    print(f"{locale}: taken {name!r}, trying next")
                    continue
                print(f"{locale}: ERROR {name!r}: {msg}")
                raise
        if not won:
            print(f"{locale}: FAILED all candidates")
            sys.exit(1)
        results[locale] = won
        # keep fastlane name.txt in sync so deliver won't re-conflict
        (META / locale / "name.txt").write_text(won + "\n")

    print("\nResolved:")
    for k2, v in results.items():
        print(f"  {k2}: {v}")


if __name__ == "__main__":
    main()
