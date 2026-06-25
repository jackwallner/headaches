#!/usr/bin/env python3
"""Round 2: reorder ALL remaining locales to migraine-first (non-Latin scripts +
collision-forced fr/nl). Cancels any open review submission first (appInfo is
locked while WAITING_FOR_REVIEW), applies names with collision fallbacks, syncs
fastlane name.txt. Re-submit is done separately after verification.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc_lib import (
    ASCClient, bearer_token, bundle_id_from_appfile, find_app,
    find_editable_app_info, find_version_by_string, list_all, load_credentials,
)

META = Path(__file__).resolve().parent.parent / "fastlane" / "metadata"

# locale -> migraine-first candidates (first that ASC accepts wins; else keep current)
NEW = {
    "ar-SA": ["متتبع الشقيقة والصداع"],
    "bn-BD": ["মাইগ্রেন ও মাথাব্যথা ট্র্যাকার"],
    "gu-IN": ["માઇગ્રેન અને માથાનો દુખાવો"],
    "he":    ["מעקב מיגרנה וכאב ראש"],
    "hi":    ["माइग्रेन और सिरदर्द ट्रैकर"],
    "id":    ["Pelacak Migrain Sakit Kepala"],
    "ja":    ["片頭痛・頭痛トラッカー"],
    "kn-IN": ["ಮೈಗ್ರೇನ್ ತಲೆನೋವು ಟ್ರ್ಯಾಕರ್"],
    "ko":    ["편두통·두통 기록기"],
    "ml-IN": ["മൈഗ്രേൻ തലവേദന ട്രാക്കർ"],
    "mr-IN": ["माइग्रेन आणि डोकेदुखी ट्रॅकर"],
    "ms":    ["Penjejak Migrain Sakit Kepala"],
    "or-IN": ["ମାଇଗ୍ରେନ ଓ ମୁଣ୍ଡବିନାଶ ଟ୍ରାକର"],
    "pa-IN": ["ਮਾਈਗ੍ਰੇਨ ਤੇ ਸਿਰਦਰਦ ਟਰੈਕਰ"],
    "ta-IN": ["மைக்ரேன் தலைவலி ட்ராக்கர்"],
    "te-IN": ["మైగ్రేన్ తలనొప్పి ట్రాకర్"],
    "th":    ["ติดตามไมเกรนและปวดหัว"],
    "ur-PK": ["مائیگرین اور سر درد ٹریکر"],
    "zh-Hans": ["偏头痛头痛追踪记录"],
    "zh-Hant": ["偏頭痛頭痛追蹤記錄"],
    "sl-SI": ["Sledilnik Migrene Glavobola"],
    "vi":    ["Nhật ký Migraine & Đau đầu"],
    "fr-CA": ["Migraine & Maux de Tête Suivi", "Migraine Maux de Tête Suivi", "Suivi Migraine Maux de Tête"],
    "fr-FR": ["Migraine & Céphalées Suivi", "Migraine Céphalées Suivi", "Suivi Migraine Céphalées"],
    "nl-NL": ["Migraine Hoofdpijn Tracker", "Migraine & Hoofdpijn Log", "Migraine & Hoofdpijn Dagboek"],
}


def main() -> None:
    cur = json.loads(Path("/private/tmp/claude-501/-Users-jackwallner-headaches/"
                          "9c38b1e1-16f9-42b3-9153-593fafb81e3e/scratchpad/current_meta.json").read_text())
    k, i, p = load_credentials()
    c = ASCClient(bearer_token(k, i, p))
    app = find_app(c, bundle_id_from_appfile()); aid = app["id"]

    # cancel any open submission so appInfo becomes editable again
    for s in list_all(c, f"/apps/{aid}/reviewSubmissions?filter[platform]=IOS"):
        if s["attributes"].get("state") == "WAITING_FOR_REVIEW":
            c.patch(f"/reviewSubmissions/{s['id']}",
                    {"data": {"type": "reviewSubmissions", "id": s["id"], "attributes": {"canceled": True}}})
            print("canceled submission", s["id"][:8])

    edit = find_editable_app_info(c, aid)
    print("editable appInfo:", edit["attributes"].get("appStoreState"))
    locs = {l["attributes"]["locale"]: l for l in list_all(c, f"/appInfos/{edit['id']}/appInfoLocalizations")}

    for loc, cands in NEW.items():
        lo = locs.get(loc)
        if not lo:
            print(f"{loc}: NO localization, skip"); continue
        lid = lo["id"]
        current = cur.get(loc, {}).get("name")
        landed, status = current, "kept-current (all taken)"
        for name in cands:
            if len(name) > 30:
                print(f"   {loc}: skip {name!r} (>30)"); continue
            try:
                c.patch(f"/appInfoLocalizations/{lid}",
                        {"data": {"type": "appInfoLocalizations", "id": lid, "attributes": {"name": name}}})
                landed, status = name, "applied"; break
            except Exception as e:
                if "already being used" in str(e) or "already used" in str(e):
                    print(f"   {loc}: taken {name!r}"); continue
                raise
        (META / loc / "name.txt").write_text(landed + "\n")
        print(f"{loc:8} {status:26} {current!r} -> {landed!r}")


if __name__ == "__main__":
    main()
