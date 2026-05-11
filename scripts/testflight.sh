#!/usr/bin/env bash
# Bump build number, archive, and upload to TestFlight.
#
# Usage: ./scripts/testflight.sh

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT_YML="$ROOT/project.yml"
ARCHIVE="$ROOT/build/HeadacheLogger.xcarchive"
STAGING="$ROOT/build/upload-staging"
PLIST="$ROOT/AppStoreUploadOptions.plist"

if [[ ! -f "$PLIST" ]]; then
  echo "error: missing $PLIST" >&2
  exit 1
fi

# Bump build number
OLD=$(grep 'CURRENT_PROJECT_VERSION:' "$PROJECT_YML" | head -1 | awk '{print $2}' | tr -d '"')
NEW=$((OLD + 1))
echo "Bumping build: $OLD → $NEW"
sed -i '' "s/CURRENT_PROJECT_VERSION: \"$OLD\"/CURRENT_PROJECT_VERSION: \"$NEW\"/" "$PROJECT_YML"

# Regenerate xcodeproj (includes RevenueCat SPM package from project.yml)
echo "Generating xcodeproj..."
xcodegen generate

# Resolve SPM dependencies
echo "Resolving package dependencies..."
xcodebuild -resolvePackageDependencies -project HeadacheLogger.xcodeproj -scheme HeadacheLogger

# Archive
echo "Archiving..."
rm -rf "$ARCHIVE"
xcodebuild -project HeadacheLogger.xcodeproj \
  -scheme HeadacheLogger \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  archive

# Upload
echo "Uploading to TestFlight..."
mkdir -p "$STAGING"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$STAGING" \
  -exportOptionsPlist "$PLIST" \
  -allowProvisioningUpdates

# Commit the bump
git add "$PROJECT_YML"
git commit -m "Bump build for TestFlight upload

Co-authored-by: CommandCodeBot <noreply@commandcode.ai>"

echo ""
echo "Done! Build $NEW uploaded. Check App Store Connect → TestFlight for Processing."
