# Wiggleroom 0.2.3

**An honest "As of" in the medium widget's All tools view.** In 0.2.2, a tool you hadn't used lately made the whole widget's "As of" line turn amber. The widget now uses the same rule as the menu bar popover.

- **One line, two times when needed:** "As of 9:29 PM · Codex 8:21 PM". The first time covers the tools whose numbers are up to date; a tool whose numbers are older (amber after 30 minutes) follows with its own name and time, in amber.
- **Never fresher than the numbers:** when both tools are about as old as each other, the line shows the older of their times.
- **Never cut off:** with very old dates, the older tool's part gets shorter ("Codex Jan 6", then "Codex") instead of being cut off.
- The small widget, the one-tool widgets and the popover are unchanged.

To update with Homebrew: `brew upgrade --cask wiggleroom`. Or quit Wiggleroom from its menu and replace it in Applications with the new version. You don't need to connect Claude Code or Codex again.

Wiggleroom has been tested automatically but not yet on many Macs. Please report anything odd at github.com/garoknows/wiggleroom/issues.

## What's in it

- Small and medium widgets, for Claude Code, Codex or All tools: weekly limits, and the 5-hour limits when your plan has them. Light and dark mode.
- "As of" time that turns amber after 30 minutes; bars dim after 6 hours; a limit whose reset time has passed says so instead of guessing.
- A Tools section in Settings. Claude Code: your settings are backed up first, and your existing status line keeps working exactly as before. Codex: nothing in Codex changes.
- Optional alerts when a tool passes 90% (or 75%) of a limit.
- Optional menu bar item. Click it for every tool's limits, in a compact view when you use both tools.
- "Delete all Wiggleroom data" in Settings (covers Codex too, and never touches Codex's own folder).

## Changelog

- **0.2.3:** The medium widget's All tools view shows an honest "As of" for each tool, like the popover, so an unused tool no longer turns it amber.
- **0.2.2:** Replaces the 0.2.1 pre-release. No C or X tag next to the menu bar percent, an honest "As of" for each tool in the popover, and every tool's watcher in Settings' Status section.
- **0.2.1 (pre-release only, replaced by 0.2.2):** A compact popover when you use both tools, the menu bar's tool always first in it, a footer that names every tool, and dates for resets a week away on today's weekday.
- **0.2.0:** Added Codex, the Tools section, the widget's Tool setting (Claude Code, Codex, All tools), one popover card per tool, the "Menu bar shows" picker, and alerts for every tool and limit.
- **0.1.1:** Fixed: the setup and Settings windows were cut off at the edges, the menu bar popover had an empty gap, and reset times now show the weekday. Percentages now round up, like Claude's usage page.
- **0.1.0:** First release. Renamed from Headroom, a one-day unsigned preview, because another Mac app already uses that name. If you tried Headroom, Connect takes over its place in your status line setting and keeps your own status line. See "Tried the Headroom preview?" in the install guide.

## Privacy

Wiggleroom has no network code. It never reads your Claude or Codex sign-in, tokens or browser cookies. From Codex's session log it keeps only the usage numbers. It keeps only the percent used, the reset times, the limit names and when they were updated.

## Requirements

macOS 14 Sonoma or later, and Claude Code signed in with a Pro, Max or Ultra plan, Codex signed in with ChatGPT, or both. The numbers update each time the tool gets a reply.

Wiggleroom is an independent project, not affiliated with Anthropic or OpenAI.
