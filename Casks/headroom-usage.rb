# Draft of the Homebrew cask for garoknows/homebrew-tap. It is NOT in the tap yet: it goes there
# only after a real-Mac check of a signed release (lesson 19). scripts/update-cask.sh fills in
# the version and sha256 from a release.
#
# The name is "headroom-usage" because Homebrew's main catalog already has an unrelated app
# called "headroom"; this way nobody installs the wrong one by accident.
cask "headroom-usage" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/garoknows/headroom/releases/download/v#{version}/Headroom-#{version}.dmg"
  name "Headroom"
  desc "Claude plan usage and reset times in Notification Center"
  homepage "https://garoknows.github.io/headroom/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"
  # Both apps install "Headroom.app".
  conflicts_with cask: "headroom"

  app "Headroom.app"

  # Put the user's previous Claude Code status line back before the app goes away (lesson 21),
  # then quit the app.
  uninstall script: {
              executable: "#{appdir}/Headroom.app/Contents/MacOS/Headroom",
              args:       ["--disconnect"],
              sudo:       false,
            },
            quit:   "io.github.garoknows.headroom"

  zap trash: [
    "~/Library/Application Scripts/io.github.garoknows.headroom.widgets",
    "~/Library/Application Support/io.github.garoknows.headroom",
    "~/Library/Containers/io.github.garoknows.headroom.widgets",
    "~/Library/Group Containers/*.io.github.garoknows.headroom",
    "~/Library/Preferences/io.github.garoknows.headroom.plist",
    "~/Library/Saved Application State/io.github.garoknows.headroom.savedState",
  ]
end
