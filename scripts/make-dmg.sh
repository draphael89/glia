#!/bin/bash
# Build a distributable Glia DMG.
#
# Zero-config: auto-detects a "Developer ID Application" cert in the keychain.
#   - Found + NOTARY_PROFILE set  -> signed, notarized, stapled (shippable)
#   - Found, no NOTARY_PROFILE    -> Developer-ID-signed (notarize separately)
#   - None                        -> ad-hoc signed (local/dev only)
# One-time notary setup:
#   xcrun notarytool store-credentials glia-notary --apple-id <id> \
#     --team-id <TEAMID> --password <app-specific-password>
# Then: NOTARY_PROFILE=glia-notary scripts/make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# Auto-detect Developer ID unless one was passed explicitly.
# (|| true so "no cert found" doesn't trip set -e / pipefail — ad-hoc is valid.)
if [ -z "${SIGN_IDENTITY:-}" ]; then
  SIGN_IDENTITY=$( { security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" | head -1 \
    | sed -E 's/.*"(Developer ID Application: [^"]+)".*/\1/'; } || true )
fi

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

# Bundle the prebuilt glia-context server so "Enable MCP" is self-contained.
# Must land BEFORE codesign so it's sealed into CodeResources (pure JS, no
# separate signature needed). Best-effort: the app has runtime fallbacks.
if bash scripts/stage-mcp.sh; then
  ditto build-mcp/glia-context-mcp "$STAGE/Glia.app/Contents/Resources/glia-context-mcp"
  echo "==> Bundled glia-context server into Glia.app"
else
  echo "warn: mcp staging failed — app will fall back to install.sh / existing registration" >&2
fi

if [ -n "$SIGN_IDENTITY" ]; then
  echo "==> Signing (Developer ID): $SIGN_IDENTITY"
  # Inside-out (Apple guidance; --deep is discouraged for Developer ID):
  # nested frameworks first, then the app with hardened runtime.
  find "$STAGE/Glia.app/Contents/Frameworks" -name "*.framework" -maxdepth 1 -print0 2>/dev/null |
    while IFS= read -r -d '' fw; do
      codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$fw"
    done
  codesign --force --options runtime --timestamp \
    --entitlements Glia/Resources/Glia-Release.entitlements \
    --sign "$SIGN_IDENTITY" "$STAGE/Glia.app"

  # Notarization pre-flight guards — fail LOUD rather than ship an app the
  # notary service will reject (get-task-allow present, or hardened runtime
  # flag missing). Cheap insurance against a silent release regression.
  if codesign -d --entitlements - "$STAGE/Glia.app" 2>/dev/null | grep -q "get-task-allow"; then
    echo "FATAL: get-task-allow present after signing — notarization would reject."; exit 1
  fi
  if ! codesign -dvv "$STAGE/Glia.app" 2>&1 | grep -q "flags=.*runtime"; then
    echo "FATAL: hardened runtime not enabled — notarization would reject."; exit 1
  fi
  echo "==> Notarization pre-flight passed (no get-task-allow, hardened runtime on)."
else
  # Ad-hoc re-sign the WHOLE bundle so the app and its embedded frameworks
  # (Sparkle ships Developer-ID-signed) share a team identity — otherwise
  # dyld's library validation rejects the framework under hardened runtime.
  echo "==> Signing (ad-hoc, local/dev only — not distributable)"
  codesign --force --deep --sign - "$STAGE/Glia.app"
fi

echo "==> Creating DMG"
hdiutil create -volname "Glia" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [ -n "$SIGN_IDENTITY" ]; then
  codesign --force --sign "$SIGN_IDENTITY" "$DMG"   # sign the container too
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "==> Notarizing (this can take a few minutes)…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    echo "==> Notarized + stapled — ready for public release."
  else
    echo "==> Developer-ID signed. Set NOTARY_PROFILE to also notarize."
  fi
else
  echo "==> Ad-hoc build (Gatekeeper will warn on other Macs)."
fi

echo "==> Done: $DMG ($(du -h "$DMG" | cut -f1))"
