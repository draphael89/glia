#!/bin/bash
# Archive + upload the Mac App Store build.
# Prereqs: Xcode signed into the enrolled Apple ID; DEVELOPMENT_TEAM set.
#   DEVELOPMENT_TEAM=XXXXXXXXXX scripts/archive-mas.sh
set -euo pipefail
cd "$(dirname "$0")/.."

: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your 10-char Team ID}"

ARCHIVE=dist/Glia-MAS.xcarchive
mkdir -p dist

echo "==> Archiving Glia-MAS"
xcodegen generate
xcodebuild archive \
  -project Glia.xcodeproj \
  -scheme Glia-MAS \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Distribution" \
  | grep -E "error|ARCHIVE" | tail -5

echo "==> Exporting + uploading to App Store Connect"
sed "s/\${DEVELOPMENT_TEAM}/$DEVELOPMENT_TEAM/" \
  packaging/ExportOptions-appstore.plist > dist/ExportOptions.plist
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist dist/ExportOptions.plist \
  -exportPath dist/mas-export \
  -allowProvisioningUpdates

echo "==> Uploaded. Next: App Store Connect -> TestFlight/App Store tab."
