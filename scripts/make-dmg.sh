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
  -derivedDataPath build/dd | grep -E "error|BUILD" | tail -2 || true

APP=build/dd/Build/Products/Release/Glia.app
[ -d "$APP" ] || { echo "Glia.app not found"; exit 1; }

echo "==> Staging"
rm -rf "$DIST"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Glia.app"          # ditto preserves signatures; cp -R may not
ln -s /Applications "$STAGE/Applications"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  echo "==> Signing (Developer ID)"
  codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$STAGE/Glia.app"
else
  # Ad-hoc re-sign the WHOLE bundle so the app and its embedded frameworks
  # (Sparkle ships Developer-ID-signed) share a team identity — otherwise
  # dyld's library validation rejects the framework under hardened runtime.
  echo "==> Signing (ad-hoc, local build)"
  codesign --force --deep --sign - "$STAGE/Glia.app"
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
