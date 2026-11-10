# Wiggleroom 0.2.0

**Codex, and a Tools section.** Wiggleroom now shows your Codex plan's limits next to Claude Code's: every AI coding limit in one glance.

- **Codex:** in Settings, under the new **Tools** section, click **Connect** next to Codex. Connecting changes nothing in Codex: after each Codex reply, Wiggleroom reads only the usage numbers from the end of Codex's newest session log on your Mac, read-only. Works when you're signed in to Codex with ChatGPT. [How Codex is read](https://github.com/garoknows/wiggleroom/blob/main/docs/TOOLS.md).
- **Widget "Tool" setting:** right-click the widget, choose **Edit Widget**, and pick **Claude Code**, **Codex** or **All tools**. Widgets you already have keep showing Claude Code.
- **Popover:** one card per connected tool, the one closest to its limit first.
- **Menu bar:** "Menu bar shows" picks **Highest of my tools** (the default), **Claude Code** or **Codex**. With both tools connected, a C or X tag says whose percent it is.
- **Alerts for every tool and every limit:** 75% and 90% now apply to each tool's 5-hour and weekly limits, at most once per level each. For example: "Codex: 90% of your weekly limit used. Resets Monday 1:00 AM."
- **Which tools are next:** Wiggleroom adds a tool only when it hands out its limits in a way its maker supports. [See which tools are supported and which are coming](https://github.com/garoknows/wiggleroom/blob/main/docs/TOOLS.md).

To update with Homebrew: `brew upgrade --cask wiggleroom`. Or quit Wiggleroom from its menu and replace it in Applications with the new version. You don't need to connect Claude Code again.

Wiggleroom has been tested automatically but not yet on many Macs. Please report anything odd at github.com/garoknows/wiggleroom/issues.

## What's in it

- Small and medium widgets, for Claude Code, Codex or All tools: weekly limits, and the 5-hour limits when your plan has them. Light and dark mode.
- "As of" time that turns amber after 30 minutes; bars dim after 6 hours; a limit whose reset time has passed says so instead of guessing.
- A Tools section in Settings. Claude Code: your settings are backed up first, and your existing status line keeps working exactly as before. Codex: nothing in Codex changes.
- Optional alerts when a tool passes 90% (or 75%) of a limit.
- Optional menu bar item.
- "Delete all Wiggleroom data" in Settings (covers Codex too, and never touches Codex's own folder).

## Changelog

- **0.2.0:** Added Codex, the Tools section, the widget's Tool setting (Claude Code, Codex, All tools), one popover card per tool, the "Menu bar shows" picker, and alerts for every tool and limit.
- **0.1.1:** Fixed: the setup and Settings windows were cut off at the edges, the menu bar popover had an empty gap, and reset times now show the weekday. Percentages now round up, like Claude's usage page.
- **0.1.0:** First release. Renamed from Headroom, a one-day unsigned preview, because another Mac app already uses that name. If you tried Headroom, Connect takes over its place in your status line setting and keeps your own status line. See "Tried the Headroom preview?" in the install guide.

## Privacy

Wiggleroom has no network code. It never reads your Claude or Codex sign-in, tokens or browser cookies. From Codex's session log it keeps only the usage numbers. It keeps only the percent used, the reset times, the limit names and when they were updated.

## Requirements

macOS 14 Sonoma or later, and Claude Code signed in with a Pro, Max or Ultra plan, Codex signed in with ChatGPT, or both. The numbers update each time the tool gets a reply.

Wiggleroom is an independent project, not affiliated with Anthropic or OpenAI.
