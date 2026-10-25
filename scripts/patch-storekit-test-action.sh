#!/bin/bash
# Puts the StoreKit configuration on the UI test scheme's TestAction.
#
# XcodeGen writes a StoreKitConfigurationFileReference only into a LaunchAction
# (the `test:` key in project.yml is ignored), and a UI test launches the app
# through the TestAction. Without this, every simulator paywall in a UI test,
# the release gate's journeys included, is the "Couldn't Load Plans" state.
# project.yml runs this as XcodeGen's postGenCommand.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR/.."

CONFIG="../../HeadacheLogger/Services/Products.storekit"

for SCHEME in HeadacheLogger.xcodeproj/xcshareddata/xcschemes/HeadacheLoggerUITests.xcscheme; do
  /usr/bin/python3 - "$SCHEME" "$CONFIG" <<'PY'
import re, sys

path, config = sys.argv[1], sys.argv[2]
with open(path) as handle:
    scheme = handle.read()

reference = (
    '      <StoreKitConfigurationFileReference\n'
    f'         identifier = "{config}">\n'
    '      </StoreKitConfigurationFileReference>\n'
)

test_action = re.search(r"   <TestAction\b.*?   </TestAction>\n", scheme, re.S)
if test_action is None:
    sys.exit("no TestAction in " + path)

block = test_action.group(0)
if "StoreKitConfigurationFileReference" in block:
    sys.exit(0)

patched = block.replace("   </TestAction>\n", reference + "   </TestAction>\n")
with open(path, "w") as handle:
    handle.write(scheme.replace(block, patched))
print("==> Patched StoreKit configuration into the TestAction of", path)
PY
done
