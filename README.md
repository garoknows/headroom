# Wiggleroom

**Your Claude plan usage, in Mac Notification Center.** See how much of your weekly and 5-hour limits you've used, and when each one resets, without opening anything.

<p>
  <img src="docs/images/widget-medium-dark-normal.png" width="364" alt="Wiggleroom medium widget in dark mode: Current session 23% used, resets today 5:57 PM; This week 41% used, resets Monday 1:00 AM; as of 2:41 PM">
  <img src="docs/images/widget-small-light-normal.png" width="170" alt="Wiggleroom small widget in light mode: This week 41%, resets Mon 1:00 AM">
</p>

Wiggleroom is a free, open-source widget (plus an optional menu bar item) for people who use **Claude Code** on a Pro, Max or Ultra plan. It shows the same numbers as the usage page in Claude's settings.

- **No sign-in, no tokens, no internet.** Wiggleroom has no network code at all. It never reads your Claude login, the Keychain or browser cookies.
- **Keeps almost nothing.** Only the percent used, the reset times, the limit names and when they were updated.
- **Leaves your setup alone.** Your existing Claude Code status line keeps working exactly as before, and Disconnect puts your settings back.

[Website](https://garoknows.github.io/wiggleroom/) · [Download](https://github.com/garoknows/wiggleroom/releases) · [Install guide](docs/INSTALL.md) · [Privacy](docs/PRIVACY.md)

## How it works

Every time Claude Code gets a reply, it hands a small bundle of information to its [status line](https://code.claude.com/docs/en/statusline), the optional line under the prompt. For Pro, Max and Ultra plans, that bundle includes your plan's usage: how much of the 5-hour and weekly limits you've used, and when each resets. This is a documented Claude Code feature.

When you click **Connect to Claude Code**, Wiggleroom adds a tiny helper to that status line. On each update the helper:

1. keeps only the usage numbers and the time (nothing else from the bundle),
2. saves them to a private file on your Mac,
3. runs your previous status line command, if you had one, with the same input, so what you see in Claude Code doesn't change.

The Wiggleroom app notices the new file, checks it, and passes it to the widget.

```
Claude Code ──(status line data)──> wiggleroom-statusline ──> your usual status line (unchanged)
                                         │
                                         └─ percent used + reset times only
                                              └─> Wiggleroom app ──> widget and menu bar
```

## Install

1. Download `Wiggleroom-<version>.dmg` from [Releases](https://github.com/garoknows/wiggleroom/releases), open it, and drag Wiggleroom to Applications.
2. Open Wiggleroom from Applications. A setup window appears.
3. Click **Connect to Claude Code**, then send any message in Claude Code.
4. Add the widget: click the date and time in the menu bar, scroll down, click **Edit Widgets**, search for Wiggleroom, and click the green **+**.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/window-setup-dark.png">
  <img src="docs/images/window-setup-light.png" width="420" alt="The Set Up Wiggleroom window, with step 1 Connect to Claude Code and step 2 Add the widget to Notification Center.">
</picture>

The [install guide](docs/INSTALL.md) has pictures for each step. You need macOS 14 Sonoma or later.

A Homebrew cask (`wiggleroom`) will follow once a signed release has been checked on real Macs.

### Tried the Headroom preview?

For one day this app was published as an unsigned preview called Headroom. It was renamed because another Mac app already uses that name. If you installed it: open Headroom, click **Disconnect** in its Settings, quit it, and move it to the Trash. Then install Wiggleroom as above. If you skip this, Wiggleroom still handles it: Connect replaces the Headroom entry in your status line setting and keeps your own status line, and **Delete All Wiggleroom Data** also clears the preview's old folder.

## Good to know

- **Numbers update when Claude Code replies.** Using Claude on claude.ai or in the Claude app counts toward the same limits, but Wiggleroom sees it only at your next Claude Code reply. The "As of" time shows how fresh the numbers are. It turns amber after 30 minutes, and the bars dim after 6 hours.
- **Reset times are always right,** because Claude Code sends the exact moment each limit resets. After a reset, Wiggleroom says "Reset at 1:00 AM, waiting for new numbers" instead of guessing 0%.
- **Plans without a 5-hour limit** show only the weekly row.
- **Signed in with an API key** (not a Claude plan)? Claude Code doesn't report plan limits then, so Wiggleroom has nothing to show.
- **Alerts:** optional notifications when you pass 90% (or 75%) of your weekly limit, once per week each.
- **Menu bar:** optional, off by default. Shows your weekly percent; click for the full card.
- **Status line note:** Claude Code shows fewer keyboard hints whenever any status line is set. If you had no status line before, connecting Wiggleroom adds an empty one, so you may notice those hints are gone.

## Uninstall

1. Open Wiggleroom's Settings and click **Disconnect** (or **Delete All Wiggleroom Data**, which also disconnects). Your previous status line comes back.
2. Click **Quit Wiggleroom** at the bottom of Settings, then drag Wiggleroom to the Trash.

If you delete the app without disconnecting, your previous status line keeps working: the setting Wiggleroom wrote runs it directly when Wiggleroom is gone. Disconnecting is still the tidy way, because it removes Wiggleroom's entry from your settings. Backups of your settings are in `~/Library/Application Support/io.github.garoknows.wiggleroom/settings-backups/`.

## Privacy

Wiggleroom stores two small files: the numbers file in `~/Library/Application Support/io.github.garoknows.wiggleroom/` (readable only by you) and a copy in the app's shared container for the widget. It never connects to the internet. See [docs/PRIVACY.md](docs/PRIVACY.md) for exactly what is stored and what is never touched.

## Build from source

You need Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
swift test --package-path Packages/WiggleroomCore   # tests
xcodegen generate                                  # makes Wiggleroom.xcodeproj from project.yml
open Wiggleroom.xcodeproj
```

Builds are signed "to run locally" by default. Unsigned builds can't share data with the widget (macOS only allows that for signed apps), so use the menu bar item, or copy `Config/Signing.example.xcconfig` to `Config/Signing.xcconfig` and add your Apple Developer Team ID.

## License and credits

[MIT](LICENSE). Wiggleroom is an independent project. It is not made by, affiliated with or endorsed by Anthropic. "Claude" and "Claude Code" are used only to describe what Wiggleroom works with.
