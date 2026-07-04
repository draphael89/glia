# Homebrew cask template. Submit to homebrew/cask after the first
# notarized GitHub release exists (Homebrew requires notarization and
# a notability bar — see docs/RELEASING.md for the launch sequence).
cask "glia" do
  version "0.1.0"
  sha256 "REPLACE_WITH_DMG_SHA256"

  url "https://github.com/REPLACE_OWNER/glia/releases/download/v#{version}/Glia-#{version}.dmg"
  name "Glia"
  desc "Native macOS window into your gbrain — watch your agent's brain learn"
  homepage "https://github.com/REPLACE_OWNER/glia"

  auto_updates true
  depends_on macos: ">= :sequoia"

  app "Glia.app"

  zap trash: [
    "~/Library/Application Support/Glia",
    "~/Library/Preferences/ai.glia.app.plist",
    "~/Library/Saved Application State/ai.glia.app.savedState",
  ]
end
