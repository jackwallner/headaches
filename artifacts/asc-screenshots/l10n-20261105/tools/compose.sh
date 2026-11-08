#!/bin/bash
# Compose, gate and sheet every target locale (or the ones given). No model step.
set -uo pipefail
KIT=$(cd "$(dirname "$0")/.." && pwd); cd "$KIT"; . .venv/bin/activate
CAT=../../../SharedHeadache/Localizable.xcstrings
LOCALES=("$@"); [ ${#LOCALES[@]} -eq 0 ] && LOCALES=($(python3 -c "import json;print(' '.join(t['store_locale'] for t in json.load(open('app.json'))['targets']))"))
for loc in "${LOCALES[@]}"; do
  lang=$(python3 -c "import json,sys;print([t['lang'] for t in json.load(open('app.json'))['targets'] if t['store_locale']=='$loc'][0])")
  [ "$lang" = no ] && lang=nb
  python tools/reskin.py --config frames.json --raw-root raw --headers copy/headers.json --locale "$loc" --out out >/dev/null 2>&1 || echo "$loc reskin FAIL"
  python tools/sheet.py --config frames.json --locale "$loc" --out-root out --base-label en >/dev/null 2>&1
  if python tools/gate.py --config frames.json --raw-root raw --headers copy/headers.json --out-root out --locale "$loc" --catalog "$CAT" --lang "$lang" >/tmp/gate-$$-$loc.log 2>&1; then echo "$loc PASS"; else echo "$loc FAIL"; tail -5 /tmp/gate-$$-$loc.log | cut -c1-200; fi
done
