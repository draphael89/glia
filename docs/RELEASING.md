# Releasing Glia

The whole train, in order. Steps 1–2 are one-time setup.

## 1. One-time: signing & notarization

1. Apple Developer Program membership → create a **Developer ID Application**
   certificate; install in the login keychain.
2. Store notary credentials:
   `xcrun notarytool store-credentials glia-notary --apple-id … --team-id … --password <app-specific>`
3. Generate the Sparkle EdDSA keypair:
   `./bin/generate_keys` (from a Sparkle release archive). Public key goes in
   Info.plist as `SUPublicEDKey`; private key becomes the
   `SPARKLE_ED_PRIVATE_KEY` repo secret.

## 2. One-time: enable the update feed

Add to `project.yml` info properties (then `xcodegen generate`):

```yaml
SUFeedURL: https://REPLACE_OWNER.github.io/glia/appcast.xml
SUPublicEDKey: <public key from step 1.3>
```

The in-app updater and "Check for Updates…" menu item activate automatically
when `SUFeedURL` is present (see `Glia/App/Updater.swift`).

## 3. Every release

```bash
# 1. bump CFBundleShortVersionString + CFBundleVersion in project.yml
# 2. verify
xcodegen generate && xcodebuild test -project Glia.xcodeproj -scheme Glia -destination 'platform=macOS'
# 3. build + sign + notarize + staple the DMG
SIGN_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=glia-notary scripts/make-dmg.sh
# 4. tag + release (or let .github/workflows/release.yml do 3–5 once secrets exist)
git tag vX.Y.Z && git push --tags
gh release create vX.Y.Z dist/Glia-X.Y.Z.dmg --generate-notes
# 5. regenerate appcast.xml with Sparkle's generate_appcast against the
#    release assets; publish to the gh-pages branch
```

## 4. Launch sequence (first public release)

demo GIF → Show HN → gbrain README PR → wait for the notability bar
(~75 stars) → submit `packaging/glia.rb` to homebrew/cask.
