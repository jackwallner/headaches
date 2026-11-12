#!/usr/bin/env python3
"""Upload the composed 13-inch iPad screenshots to the editable App Store version.

out/<locale>/<NN-name>.png  ->  APP_IPAD_PRO_3GEN_129 set of that locale's
version localization on the draft (PREPARE_FOR_SUBMISSION) version. An existing
iPad set is emptied first so a rerun replaces rather than duplicates.
Never submits for review.
"""
from __future__ import annotations

import hashlib
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "scripts"))
from asc_lib import (  # noqa: E402
    ASCClient, bearer_token, find_app, find_editable_version, list_all, load_credentials,
)

HERE = Path(__file__).resolve().parent
DISPLAY_TYPE = "APP_IPAD_PRO_3GEN_129"
BUNDLE = "com.jackwallner.headachelogger"


def put_chunks(path: Path, operations: list[dict]) -> None:
    data = path.read_bytes()
    for op in operations:
        chunk = data[op["offset"]: op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
        for header in op["requestHeaders"]:
            req.add_header(header["name"], header["value"])
        urllib.request.urlopen(req, timeout=300).read()


def main() -> None:
    locales = sys.argv[1:] or sorted(p.name for p in (HERE / "out").iterdir() if p.is_dir())
    client = ASCClient(bearer_token(*load_credentials()))
    app = find_app(client, BUNDLE)
    version = find_editable_version(client, app["id"])
    if not version:
        raise SystemExit("no editable version")
    print("version", version["attributes"]["versionString"], version["attributes"]["appStoreState"])
    locs = {
        item["attributes"]["locale"]: item
        for item in list_all(client, f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")
    }
    for locale in locales:
        loc = locs[locale]
        sets = list_all(client, f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")
        shot_set = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == DISPLAY_TYPE), None)
        if shot_set is None:
            shot_set = client.post("/appScreenshotSets", {"data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
                "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"]}}},
            }})["data"]
        for old in list_all(client, f"/appScreenshotSets/{shot_set['id']}/appScreenshots"):
            client.request("DELETE", f"/appScreenshots/{old['id']}")
        order = []
        for file in sorted((HERE / "out" / locale).glob("*.png")):
            data = file.read_bytes()
            created = client.post("/appScreenshots", {"data": {
                "type": "appScreenshots",
                "attributes": {"fileName": file.name, "fileSize": len(data)},
                "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": shot_set["id"]}}},
            }})["data"]
            put_chunks(file, created["attributes"]["uploadOperations"])
            client.patch(f"/appScreenshots/{created['id']}", {"data": {
                "type": "appScreenshots", "id": created["id"],
                "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()},
            }})
            order.append(created["id"])
            print(f"uploaded {locale}/{file.name}")
        client.patch(f"/appScreenshotSets/{shot_set['id']}/relationships/appScreenshots", {
            "data": [{"type": "appScreenshots", "id": i} for i in order],
        })


if __name__ == "__main__":
    main()
