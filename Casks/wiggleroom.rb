# The Homebrew cask, published in garoknows/homebrew-tap (brew install --cask garoknows/tap/wiggleroom).
# scripts/update-cask.sh fills in the version and sha256 from a release; copy the result to the tap.
cask "wiggleroom" do
  version "0.2.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/garoknows/wiggleroom/releases/download/v#{version}/Wiggleroom-#{version}.dmg"
  name "Wiggleroom"
  desc "Claude Code and Codex plan limits in Notification Center"
  homepage "https://garoknows.github.io/wiggleroom/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Wiggleroom.app"

  # Homebrew runs "uninstall" on upgrades too, so it must not disconnect Wiggleroom from Claude
  # Code (an upgrade would silently stop the numbers). Removing the app is safe anyway: the
  # status line setting falls back to the user's previous command when Wiggleroom is gone.
  uninstall quit: "io.github.garoknows.wiggleroom"

  zap trash: [
    "~/Library/Application Scripts/io.github.garoknows.wiggleroom.widgets",
    "~/Library/Application Support/io.github.garoknows.wiggleroom",
    "~/Library/Containers/io.github.garoknows.wiggleroom.widgets",
    "~/Library/Group Containers/*.io.github.garoknows.wiggleroom",
    "~/Library/Preferences/io.github.garoknows.wiggleroom.plist",
    "~/Library/Saved Application State/io.github.garoknows.wiggleroom.savedState",
  ]
end
