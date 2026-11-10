# Wiggleroom 0.1.1

**A fix release.** Fixed: the setup and Settings windows were cut off at the edges, the menu bar popover had an empty gap, and reset times now show the weekday. Percentages now round up, like Claude's usage page.

- **Setup window:** the widget pictures now fit the window, so nothing is cut off on the left or right.
- **Settings window:** every section fits inside the window, including when scroll bars are set to always show.
- **Menu bar popover:** it is now exactly as tall as what it shows. A plan with only a weekly limit shows one row with no empty space.
- **Reset times:** a reset up to 7 days away now reads like Claude's own usage page, for example "Resets Monday 1:00 AM" instead of "Resets Nov 16, 1:00 AM".
- **Percentages:** they now round up, like Claude's usage page, so Wiggleroom never shows less than you've used: 3.2% shows as 4%. Exactly 0 still shows 0%, and 100% appears only when a limit is really used up.

To update: quit Wiggleroom from its menu, then replace it in Applications with the new version. You don't need to connect again.

Wiggleroom has been tested automatically but not yet on many Macs. Please report anything odd at github.com/garoknows/wiggleroom/issues.

Wiggleroom shows how much of your Claude plan's usage limits you've used, and when each one resets, in a Notification Center widget, with an optional menu bar item.

## What's in it

- Small and medium widgets: this week's limit, and the current 5-hour session when your plan has one. Light and dark mode.
- "As of" time that turns amber after 30 minutes; bars dim after 6 hours; a limit whose reset time has passed says so instead of guessing.
- Connect and Disconnect in Settings. Your Claude Code settings are backed up first; your existing status line keeps working exactly as before.
- Optional alert when you pass 90% (or 75%) of your weekly limit, once per week.
- Optional menu bar item with your weekly percent.
- "Delete all Wiggleroom data" in Settings.

## Changelog

- **0.1.1:** Fixed: the setup and Settings windows were cut off at the edges, the menu bar popover had an empty gap, and reset times now show the weekday. Percentages now round up, like Claude's usage page.
- **0.1.0:** First release. Renamed from Headroom, a one-day unsigned preview, because another Mac app already uses that name. If you tried Headroom, Connect takes over its place in your status line setting and keeps your own status line. See "Tried the Headroom preview?" in the install guide.

## Privacy

Wiggleroom has no network code. It never reads your Claude sign-in, tokens or browser cookies. It keeps only the percent used, the reset times, the limit names and when they were updated.

## Requirements

macOS 14 Sonoma or later, and Claude Code signed in with a Pro, Max or Ultra plan. The numbers update each time Claude Code gets a reply.

Wiggleroom is an independent project, not affiliated with Anthropic.
