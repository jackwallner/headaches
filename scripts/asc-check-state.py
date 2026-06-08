#!/usr/bin/env python3
"""Print draft vs live ASC locale counts (appInfo + version)."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from asc_lib import (
    ASCClient,
    bearer_token,
    bundle_id_from_appfile,
    find_app,
    find_editable_app_info,
    find_editable_version,
    find_live_version,
    list_all,
    load_credentials,
    load_state,
)


def main() -> None:
    key_id, issuer_id, key_path = load_credentials()
    client = ASCClient(bearer_token(key_id, issuer_id, key_path))
    app = find_app(client, bundle_id_from_appfile())
    live_v = find_live_version(client, app["id"])
    draft_v = find_editable_version(client, app["id"])
    live_info = [i for i in list_all(client, f"/apps/{app['id']}/appInfos") if i["attributes"].get("appStoreState") == "READY_FOR_SALE"]
    draft_info = find_editable_app_info(client, app["id"])

    state = load_state()
    print(f"state file: draft={state.get('draftVersion')} live={state.get('liveVersion')}")
    if live_v:
        n = len(list_all(client, f"/appStoreVersions/{live_v['id']}/appStoreVersionLocalizations"))
        print(f"live version {live_v['attributes']['versionString']}: {n} version locales")
    if draft_v:
        n = len(list_all(client, f"/appStoreVersions/{draft_v['id']}/appStoreVersionLocalizations"))
        print(f"draft version {draft_v['attributes']['versionString']}: {n} version locales")
    if live_info:
        n = len(list_all(client, f"/appInfos/{live_info[0]['id']}/appInfoLocalizations"))
        print(f"live appInfo: {n} locales")
    if draft_info:
        n = len(list_all(client, f"/appInfos/{draft_info['id']}/appInfoLocalizations"))
        print(f"draft appInfo: {n} locales")


if __name__ == "__main__":
    main()
