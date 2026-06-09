#!/usr/bin/env python3
"""Inspect/fix App Store Connect IAP localizations (em dashes in English copy).

Read-only by default. With --fix, replaces em dashes in English-locale (en-*)
IAP descriptions/names only. Em dash is valid punctuation in ru/uk/zh/etc., so
those locales are never touched.
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from asc_lib import (
    ASCClient,
    bearer_token,
    bundle_id_from_appfile,
    find_app,
    list_all,
    load_credentials,
)

V2 = "https://api.appstoreconnect.apple.com/v2"
EM_DASH = "—"


def raw(token: str, method: str, url: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        url, data=data, method=method,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            txt = resp.read().decode()
            return json.loads(txt) if txt else {}
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{method} {url} -> {e.code}: {e.read().decode()}") from e


def fix_text(s: str) -> str:
    # "forever — proactive" style → "forever, with proactive"; generic fallback ", ".
    out = s.replace(" — ", ", ").replace("—", "-")
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--fix", action="store_true", help="PATCH em dashes out of English IAP locales")
    args = ap.parse_args()

    key_id, issuer_id, key_path = load_credentials()
    token = bearer_token(key_id, issuer_id, key_path)
    client = ASCClient(token)
    app = find_app(client, bundle_id_from_appfile())
    app_id = app["id"]
    print(f"App {app['attributes'].get('name')} ({app_id})\n")

    iaps = list_all(client, f"/apps/{app_id}/inAppPurchasesV2")
    if not iaps:
        print("No in-app purchases found.")
        return

    changed = 0
    for iap in iaps:
        a = iap["attributes"]
        print(f"IAP: {a.get('name')}  [{a.get('productId')}]  state={a.get('state')}  id={iap['id']}")
        loc_url = f"{V2}/inAppPurchases/{iap['id']}/inAppPurchaseLocalizations"
        locs = raw(token, "GET", loc_url).get("data", [])
        for loc in locs:
            la = loc["attributes"]
            locale = la.get("locale") or ""
            name = la.get("name") or ""
            desc = la.get("description") or ""
            has_em = EM_DASH in name or EM_DASH in desc
            tag = "  <EM-DASH>" if has_em else ""
            print(f"  - {locale} (id={loc['id']}){tag}")
            print(f"      name: {name}")
            print(f"      desc: {desc}")
            if args.fix and has_em and locale.lower().startswith("en"):
                new_name = fix_text(name)
                new_desc = fix_text(desc)
                attrs = {}
                if new_name != name:
                    attrs["name"] = new_name
                if new_desc != desc:
                    attrs["description"] = new_desc
                if attrs:
                    raw(token, "PATCH", f"{V2}/inAppPurchaseLocalizations/{loc['id']}",
                        {"data": {"type": "inAppPurchaseLocalizations", "id": loc["id"], "attributes": attrs}})
                    changed += 1
                    print(f"      FIXED -> name: {new_name}")
                    print(f"               desc: {new_desc}")
            elif args.fix and has_em:
                print(f"      (left as-is: em dash is valid in {locale})")
        print()

    if args.fix:
        print(f"Patched {changed} English localization(s).")


if __name__ == "__main__":
    main()
