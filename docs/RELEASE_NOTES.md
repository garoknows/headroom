# Headroom 0.1.0

**Pre-release: the first preview.** It has been tested automatically but not yet on many Macs. Please report anything odd at github.com/garoknows/headroom/issues.

Headroom shows how much of your Claude plan's usage limits you've used, and when each one resets, in a Notification Center widget, with an optional menu bar item.

## What's in it

- Small and medium widgets: this week's limit, and the current 5-hour session when your plan has one. Light and dark mode.
- "As of" time that turns amber after 30 minutes; bars dim after 6 hours; a limit whose reset time has passed says so instead of guessing.
- Connect and Disconnect in Settings. Your Claude Code settings are backed up first; your existing status line keeps working exactly as before.
- Optional alert when you pass 90% (or 75%) of your weekly limit, once per week.
- Optional menu bar item with your weekly percent.
- "Delete all Headroom data" in Settings.

## Privacy

Headroom has no network code. It never reads your Claude sign-in, tokens or browser cookies. It keeps only the percent used, the reset times, the limit names and when they were updated.

## Requirements

macOS 14 Sonoma or later, and Claude Code signed in with a Pro, Max or Ultra plan. The numbers update each time Claude Code gets a reply.

Headroom is an independent project, not affiliated with Anthropic.
