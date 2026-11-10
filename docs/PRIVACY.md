# Wiggleroom and your privacy

Wiggleroom is built to know as little as possible.

## What Wiggleroom stores

| What | Where | Who can read it |
| --- | --- | --- |
| Percent used of each limit, when each resets, the limit's name (like `seven_day`), and when the numbers arrived | `~/Library/Application Support/io.github.garoknows.wiggleroom/usage.json` | Only your user account (file permissions 0600, folder 0700) |
| A copy of the same numbers for the widget | Wiggleroom's shared container (`~/Library/Group Containers/…io.github.garoknows.wiggleroom/snapshot.json`) | Only your user account |
| Your choices (alerts, menu bar, setup done) | Wiggleroom's preferences | Only your user account |
| Backups of `~/.claude/settings.json`, made before each Connect or Disconnect | `~/Library/Application Support/io.github.garoknows.wiggleroom/settings-backups/` | Only your user account |

Example of everything in the numbers file:

```json
{"format":1,"limits":[{"id":"five_hour","outOfRange":false,"resetsAt":1799996400,"usedPercent":23.5},{"id":"seven_day","outOfRange":false,"resetsAt":1800417600,"usedPercent":41.2}],"updatedAt":1799990000}
```

## What Wiggleroom never stores or reads

- Your prompts, Claude's replies, file names, folders or projects.
- Session IDs, model names, costs or spend amounts, or account details.
- Your Claude sign-in: Wiggleroom never reads Claude Code's Keychain item or any token, never calls Anthropic's servers, and never reads claude.ai cookies or pages.

Claude Code sends its status line much more than the usage numbers (for example the current folder and the model). Wiggleroom's helper reads only the `rate_limits` part, and an automated test feeds it a full sample and checks that nothing else ends up in the file.

## No network

There is no network code in the app, the widget or the helper. An automated test fails the build if networking code appears in the source, and another check inspects the built app for networking functions. Wiggleroom never needs the internet.

## Changing your Claude Code settings

Wiggleroom edits `~/.claude/settings.json` only when you click **Connect** or **Disconnect** (or **Delete All Wiggleroom Data**, which disconnects). Each time it:

- saves a backup first, in Wiggleroom's own private folder (never next to the file, so it can't land in a dotfiles repository),
- changes only the `statusLine` setting and leaves every other character as you wrote it,
- reads the result back and checks it before saving, and
- changes nothing at all if the file can't be read safely, and tells you why.

## Deleting your data

**Settings > Delete All Wiggleroom Data** disconnects from Claude Code, deletes both numbers files and resets Wiggleroom's preferences. Backups of your Claude Code settings are your own settings, so they're kept in `settings-backups/`; delete that folder yourself if you don't want them.

## Questions

Open an issue at [github.com/garoknows/wiggleroom](https://github.com/garoknows/wiggleroom/issues). Wiggleroom is an independent open-source project, not affiliated with Anthropic.
