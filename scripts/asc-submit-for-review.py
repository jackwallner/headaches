#!/usr/bin/env python3
"""Attach a build, set auto-release, and submit a draft version for App Store review.

Usage: ASC_APP_VERSION=1.4.3 python3 scripts/asc-submit-for-review.py --build 82 [--manual]
Default release is AFTER_APPROVAL (auto-release once approved); pass --manual to keep MANUAL.
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from asc_lib import (
    ASCClient,
    bearer_token,
    bundle_id_from_appfile,
    find_app,
    find_version_by_string,
    list_all,
    load_credentials,
    load_state,
)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", required=True, help="build number (CFBundleVersion) to attach")
    ap.add_argument("--manual", action="store_true", help="keep MANUAL release instead of AFTER_APPROVAL")
    args = ap.parse_args()

    version_string = os.environ.get("ASC_APP_VERSION") or load_state().get("draftVersion")
    if not version_string:
        sys.exit("set ASC_APP_VERSION")

    k, i, p = load_credentials()
    c = ASCClient(bearer_token(k, i, p))
    app = find_app(c, bundle_id_from_appfile())
    aid = app["id"]
    ver = find_version_by_string(c, aid, version_string)
    if not ver:
        sys.exit(f"version {version_string} not found")
    vid = ver["id"]
    state = ver["attributes"].get("appStoreState")
    print(f"version {version_string} (id={vid}) state={state}")

    # 1. find build
    builds = list_all(c, f"/builds?filter[app]={aid}&filter[version]={args.build}&limit=1")
    if not builds:
        sys.exit(f"build {args.build} not found")
    bid = builds[0]["id"]
    print(f"build {args.build} id={bid} state={builds[0]['attributes'].get('processingState')}")

    # 2. attach build + set release type in one PATCH
    release = "MANUAL" if args.manual else "AFTER_APPROVAL"
    c.patch(
        f"/appStoreVersions/{vid}",
        {
            "data": {
                "type": "appStoreVersions",
                "id": vid,
                "attributes": {"releaseType": release},
                "relationships": {"build": {"data": {"type": "builds", "id": bid}}},
            }
        },
    )
    print(f"attached build {args.build}; releaseType={release}")

    # 3. reuse an open reviewSubmission or create one
    subs = list_all(c, f"/apps/{aid}/reviewSubmissions?filter[platform]=IOS")
    open_sub = next(
        (s for s in subs if s["attributes"].get("state") in ("READY_FOR_REVIEW", "UNRESOLVED_ISSUES", None)
         and not s["attributes"].get("submitted")),
        None,
    )
    if open_sub:
        sid = open_sub["id"]
        print(f"reusing open reviewSubmission {sid} (state={open_sub['attributes'].get('state')})")
    else:
        sid = c.post(
            "/reviewSubmissions",
            {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                      "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}},
        )["data"]["id"]
        print(f"created reviewSubmission {sid}")

    # 4. add the version as an item (skip if already present)
    items = list_all(c, f"/reviewSubmissions/{sid}/items")
    have = any((it.get("relationships", {}).get("appStoreVersion", {}).get("data") or {}).get("id") == vid for it in items)
    if not have:
        try:
            c.post(
                "/reviewSubmissionItems",
                {"data": {"type": "reviewSubmissionItems",
                          "relationships": {
                              "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}},
                              "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}},
            )
            print("added version to submission")
        except RuntimeError as e:
            print(f"item add note: {e}")
    else:
        print("version already an item on submission")

    # 5. submit
    c.patch(
        f"/reviewSubmissions/{sid}",
        {"data": {"type": "reviewSubmissions", "id": sid, "attributes": {"submitted": True}}},
    )
    print(f"SUBMITTED reviewSubmission {sid} for {version_string} (release={release})")


if __name__ == "__main__":
    main()
