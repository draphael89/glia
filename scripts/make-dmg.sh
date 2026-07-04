#!/bin/bash
# Build a distributable Glia DMG.
#
# Unsigned by default (local/dev). For release, export:
#   SIGN_IDENTITY="Developer ID Application: ..."   codesign identity
#   NOTARY_PROFILE="glia-notary"                    notarytool keychain profile
# and the script signs, notarizes, and staples.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(grep -A1 'CFBundleShortVersionString' Glia/Resources/Info.plist | tail -1 \
  | sed -E 's/.*<string>(.*)<\/string>.*/\1/')
DIST=dist
STAGE="$DIST/stage"
DMG="$DIST/Glia-$VERSION.dmg"

echo "==> Building Release"
xcodegen generate
xcodebuild -project Glia.xcodeproj -scheme Glia -configuration Release build \
  | grep -E "error|warning: .*deprecated|BUILD" | tail -3 || true

APP=$(find "$HOME/Library/Developer/Xcode/DerivedData" \
  -path "*/Build/Products/Release/Glia.app" -maxdepth 6 | head -1)
[ -d "$APP" ] || { echo "Glia.app not found"; exit 1; }

echo "==> Staging"
rm -rf "$DIST"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  echo "==> Signing"
  codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$STAGE/Glia.app"
fi

echo "==> Creating DMG"
hdiutil create -volname "Glia" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [ -n "${SIGN_IDENTITY:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "==> Notarizing"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo "==> Done: $DMG ($(du -h "$DMG" | cut -f1))"
