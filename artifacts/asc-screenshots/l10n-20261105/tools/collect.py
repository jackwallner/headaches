#!/usr/bin/env python3
"""Sort localized store screenshot attachments into the kit raw tree."""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path
from typing import Any, Iterator


def strings(node: Any) -> Iterator[tuple[str, str]]:
    if isinstance(node, dict):
        for key, value in node.items():
            if isinstance(value, str):
                yield key, value
            else:
                yield from strings(value)
    elif isinstance(node, list):
        for value in node:
            yield from strings(value)


def attachment_records(root: Path) -> list[dict[str, Any]]:
    records = []
    for manifest in root.rglob("manifest.json"):
        try:
            payload = json.loads(manifest.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        pending = [payload]
        while pending:
            item = pending.pop()
            if isinstance(item, dict):
                if any(name in item for name in ("suggestedHumanReadableName", "exportedFileName")):
                    records.append(item)
                pending.extend(value for value in item.values() if isinstance(value, (dict, list)))
            elif isinstance(item, list):
                pending.extend(item)
    return records


def locate_attachment(root: Path, token: str, records: list[dict[str, Any]]) -> Path | None:
    wanted = Path(token).stem.casefold()
    for record in records:
        values = list(strings(record))
        if not any(wanted in Path(value).stem.casefold() for _, value in values):
            continue
        for key, value in values:
            if "file" not in key.casefold():
                continue
            path = root / value
            if path.is_file():
                return path
            matches = list(root.rglob(Path(value).name))
            if matches:
                return matches[0]

    for path in root.rglob("*.png"):
        if wanted in path.name.casefold():
            return path
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--id", required=True)
    parser.add_argument("--kit", type=Path, required=True)
    parser.add_argument("--frames", help="optional comma-separated frame filenames to collect")
    args = parser.parse_args()

    run = Path.home() / ".gh-sim" / "results" / args.id
    attachment_root = run / "attachments"
    if not attachment_root.is_dir():
        print(f"missing attachment directory: {attachment_root}", file=sys.stderr)
        return 1

    config = json.loads((args.kit / "frames.json").read_text())
    app = json.loads((args.kit / "app.json").read_text())
    locales = ["en-US"] + [target["store_locale"] for target in app["targets"]]
    selected_frames = {item for item in (args.frames or "").split(",") if item}
    available_frames = {frame["file"] for group in config["sets"].values() for frame in group["frames"]}
    unknown_frames = selected_frames - available_frames
    if unknown_frames:
        parser.error(f"unknown frame(s): {', '.join(sorted(unknown_frames))}")
    records = attachment_records(attachment_root)
    missing = []
    copied = 0
    for locale in locales:
        for set_name, group in config["sets"].items():
            output = args.kit / "raw" / locale / set_name
            output.mkdir(parents=True, exist_ok=True)
            for frame in group["frames"]:
                if selected_frames and frame["file"] not in selected_frames:
                    continue
                token = f"{locale}__{frame['file']}"
                source = locate_attachment(attachment_root, token, records)
                if source is None:
                    missing.append(token)
                    continue
                shutil.copy2(source, output / frame["file"])
                copied += 1

    print(f"sorted {copied} screenshot attachments into {args.kit / 'raw'}")
    for item in missing:
        print(f"missing attachment: {item}", file=sys.stderr)
    return int(bool(missing))


if __name__ == "__main__":
    raise SystemExit(main())
