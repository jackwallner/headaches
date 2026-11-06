#!/bin/bash
set -euo pipefail

TOOLS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KIT=$(cd "$TOOLS_DIR/.." && pwd)
REPO=$(git -C "$KIT" rev-parse --show-toplevel)
LOCALE_FILE="$REPO/HeadacheLoggerUITests/Resources/capture-locales.json"
BACKUP=$(mktemp)
ID_FILE=$(mktemp)
cp "$LOCALE_FILE" "$BACKUP"

cleanup() {
  cp "$BACKUP" "$LOCALE_FILE"
  rm -f "$BACKUP" "$ID_FILE"
}
trap cleanup EXIT

CAPTURE_MODE=all
LOCALE_ARGS=()
HAS_LOCALE_ARGUMENT=0
for arg in "$@"; do
  if [ "$arg" = "--history-only" ]; then
    CAPTURE_MODE=history
  else
    LOCALE_ARGS+=("$arg")
    HAS_LOCALE_ARGUMENT=1
  fi
done
if [ "$HAS_LOCALE_ARGUMENT" -eq 0 ]; then LOCALE_ARGS=(""); fi

python3 - "$KIT/app.json" "$LOCALE_FILE" "$CAPTURE_MODE" "${LOCALE_ARGS[@]}" <<'PY'
import json
import sys
from pathlib import Path

app_path, locale_path, capture_mode, *requested_args = sys.argv[1:]
app = json.loads(Path(app_path).read_text())
targets = app["targets"]
requested = {item for arg in requested_args for item in arg.split(",") if item}
if requested == {"all"} or not requested:
    selected = targets
else:
    unknown = requested - {target["store_locale"] for target in targets}
    if unknown:
        raise SystemExit(f"unknown target locale(s): {', '.join(sorted(unknown))}")
    selected = [target for target in targets if target["store_locale"] in requested]

locales = [{"store_locale": "en-US", "language": "en", "apple_locale": "en_US"}]
locales.extend({
    "store_locale": target["store_locale"],
    "language": target["lang"],
    "apple_locale": target["apple_locale"],
} for target in selected)
Path(locale_path).write_text(json.dumps(locales, ensure_ascii=False, indent=2) + "\n")
print("Capturing locales:", ", ".join(item["store_locale"] for item in locales))
print("Capture mode:", capture_mode)
PY

TEST_METHOD=HeadacheLoggerUITests/ReleaseJourneysUITests/testLocalizedStoreScreenshots
if [ "$CAPTURE_MODE" = history ]; then
  TEST_METHOD=HeadacheLoggerUITests/ReleaseJourneysUITests/testLocalizedHistoryStoreScreenshots
fi

SIM_STATUS=0
gh-sim test \
  --scheme HeadacheLoggerUITests \
  --device "iPhone 17 Pro Max" \
  --wait 14 \
  --only "$TEST_METHOD" \
  --id-file "$ID_FILE" || SIM_STATUS=$?

COLLECT_STATUS=0
if [ -s "$ID_FILE" ]; then
  if [ "$CAPTURE_MODE" = history ]; then
    python3 "$TOOLS_DIR/collect.py" --id "$(cat "$ID_FILE")" --kit "$KIT" --frames "02-review-a-recorded-headache.png,03-read-your-record-clearly.png,06-review-each-entry.png" || COLLECT_STATUS=$?
  else
    python3 "$TOOLS_DIR/collect.py" --id "$(cat "$ID_FILE")" --kit "$KIT" || COLLECT_STATUS=$?
  fi
else
  COLLECT_STATUS=1
  echo "gh-sim did not write a run id" >&2
fi

if [ "$SIM_STATUS" -ne 0 ]; then exit "$SIM_STATUS"; fi
exit "$COLLECT_STATUS"
