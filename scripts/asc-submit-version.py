#!/usr/bin/env python3
"""Attach the processed build, set auto-release, and submit an ASC version for review.

Usage:
    ASC_APP_VERSION=1.1.1 ASC_BUILD=37 python3 scripts/asc-submit-version.py [--dry-run]

Steps:
  1. Resolve app + the target appStoreVersion (must be editable).
  2. Find the build by CFBundleVersion (ASC_BUILD); require processingState=VALID.
  3. PATCH version: releaseType (ASC_RELEASE_TYPE, default MANUAL) + attach build.
  4. Create/reuse a reviewSubmission, add the version as an item, submit.

Export compliance is declared in Info.plist (ITSAppUsesNonExemptEncryption=false), so no
encryption answer is required at submission time.
"""
from __future__ import annotations

import os
import sys

import asc_lib as L  # sibling module in scripts/ (sys.path[0] when run as a file)


def main() -> int:
    dry = "--dry-run" in sys.argv
    version_string = os.environ.get("ASC_APP_VERSION", "1.1.1")
    # MANUAL by default: approval and going live are separate decisions, and a
    # release that changes price should wait for a human to press the button.
    # Set ASC_RELEASE_TYPE=AFTER_APPROVAL to go live the moment review clears.
    release_type = os.environ.get("ASC_RELEASE_TYPE", "MANUAL")
    build_number = os.environ.get("ASC_BUILD", "37")

    kid, iss, kp = L.load_credentials()
    c = L.ASCClient(L.bearer_token(kid, iss, kp))
    app = L.find_app(c, L.bundle_id_from_appfile())
    app_id = app["id"]
    print(f"app {app_id}  version {version_string}  build {build_number}")

    ver = L.find_version_by_string(c, app_id, version_string)
    if not ver:
        print(f"ERROR: version {version_string} not found")
        return 1
    ver_id = ver["id"]
    state = ver["attributes"]["appStoreState"]
    print(f"version id={ver_id} state={state}")
    if state not in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"):
        print(f"ERROR: version not in an editable/submittable state ({state})")
        return 1

    # Find build by CFBundleVersion
    builds = L.list_all(
        c,
        f"/builds?filter[app]={app_id}&filter[version]={build_number}"
        f"&fields[builds]=version,processingState,expired&limit=200",
    )
    if not builds:
        print(f"ERROR: build {build_number} not found yet (still uploading/processing?)")
        return 2
    b = builds[0]
    ps = b["attributes"]["processingState"]
    print(f"build id={b['id']} processingState={ps} expired={b['attributes'].get('expired')}")
    if ps != "VALID":
        print(f"NOT READY: build processingState={ps} (need VALID). Re-run when processed.")
        return 2

    if dry:
        print(f"[dry-run] would set releaseType={release_type}, attach build, submit for review")
        return 0

    # 3. Auto-release + attach build
    c.patch(
        f"/appStoreVersions/{ver_id}",
        {
            "data": {
                "type": "appStoreVersions",
                "id": ver_id,
                "attributes": {"releaseType": release_type},
                "relationships": {"build": {"data": {"type": "builds", "id": b["id"]}}},
            }
        },
    )
    print(f"set releaseType={release_type} + attached build")

    # 4. Review submission
    subs = L.list_all(
        c,
        f"/reviewSubmissions?filter[app]={app_id}&filter[state]=READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES"
        f"&fields[reviewSubmissions]=state&limit=10",
    )
    open_sub = next((s for s in subs if s["attributes"]["state"] in ("READY_FOR_REVIEW", "UNRESOLVED_ISSUES")), None)
    if open_sub:
        sub_id = open_sub["id"]
        print(f"reusing open reviewSubmission {sub_id} ({open_sub['attributes']['state']})")
    else:
        created = c.post(
            "/reviewSubmissions",
            {
                "data": {
                    "type": "reviewSubmissions",
                    "attributes": {"platform": "IOS"},
                    "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
                }
            },
        )
        sub_id = created["data"]["id"]
        print(f"created reviewSubmission {sub_id}")

    # Add the version as a submission item (ignore if already present)
    try:
        c.post(
            "/reviewSubmissionItems",
            {
                "data": {
                    "type": "reviewSubmissionItems",
                    "relationships": {
                        "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
                        "appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver_id}},
                    },
                }
            },
        )
        print("added version to submission")
    except Exception as e:  # noqa: BLE001
        print(f"submission item note: {e} (likely already attached)")

    # Submit
    c.patch(
        f"/reviewSubmissions/{sub_id}",
        {"data": {"type": "reviewSubmissions", "id": sub_id, "attributes": {"submitted": True}}},
    )
    tail = ("will auto-release on approval" if release_type == "AFTER_APPROVAL"
            else "awaits a manual release after approval")
    print(f"SUBMITTED reviewSubmission {sub_id}: version {version_string} {tail}")
    live = L.find_live_version(c, app_id)
    live_version = live["attributes"]["versionString"] if live else None
    L.save_state(version_string, live_version, app_id)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
