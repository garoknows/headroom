# Headroom and your privacy

Headroom is built to know as little as possible.

## What Headroom stores

| What | Where | Who can read it |
| --- | --- | --- |
| Percent used of each limit, when each resets, the limit's name (like `seven_day`), and when the numbers arrived | `~/Library/Application Support/io.github.garoknows.headroom/usage.json` | Only your user account (file permissions 0600, folder 0700) |
| A copy of the same numbers for the widget | Headroom's shared container (`~/Library/Group Containers/…io.github.garoknows.headroom/snapshot.json`) | Only your user account |
| Your choices (alerts, menu bar, setup done) | Headroom's preferences | Only your user account |

Example of everything in the numbers file:

```json
{"format":1,"limits":[{"id":"five_hour","outOfRange":false,"resetsAt":1799996400,"usedPercent":23.5},{"id":"seven_day","outOfRange":false,"resetsAt":1800417600,"usedPercent":41.2}],"updatedAt":1799990000}
```

## What Headroom never stores or reads

- Your prompts, Claude's replies, file names, folders or projects.
- Session IDs, model names, costs or spend amounts, or account details.
- Your Claude sign-in: Headroom never reads Claude Code's Keychain item or any token, never calls Anthropic's servers, and never reads claude.ai cookies or pages.

Claude Code sends its status line much more than the usage numbers (for example the current folder and the model). Headroom's helper reads only the `rate_limits` part, and an automated test feeds it a full sample and checks that nothing else ends up in the file.

## No network

There is no network code in the app, the widget or the helper. An automated test fails the build if networking code appears in the source, and another check inspects the built app for networking functions. Headroom never needs the internet.

## Changing your Claude Code settings

Headroom edits `~/.claude/settings.json` only when you click **Connect** or **Disconnect** (or **Delete All Headroom Data**, which disconnects). Each time it:

- saves a backup next to the file first,
- changes only the `statusLine` setting and leaves every other character as you wrote it,
- reads the result back and checks it before saving, and
- changes nothing at all if the file can't be read safely, and tells you why.

## Deleting your data

**Settings > Delete All Headroom Data** disconnects from Claude Code, deletes both numbers files and resets Headroom's preferences. Backups of your Claude Code settings are your own settings, so they're kept.

## Questions

Open an issue at [github.com/garoknows/headroom](https://github.com/garoknows/headroom/issues). Headroom is an independent open-source project, not affiliated with Anthropic.
