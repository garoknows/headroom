# Wiggleroom and your privacy

Wiggleroom is built to know as little as possible.

## What Wiggleroom stores

| What | Where | Who can read it |
| --- | --- | --- |
| Percent used of each limit, when each resets, the limit's name (like `seven_day`), and when the numbers arrived | `~/Library/Application Support/io.github.garoknows.wiggleroom/usage.json` | Only your user account (file permissions 0600, folder 0700) |
| Codex's percent used, reset times, window lengths and when the numbers arrived (only if you connect Codex) | `~/Library/Application Support/io.github.garoknows.wiggleroom/codex.json` | Only your user account (0600) |
| A copy of the same numbers for the widget, one entry per connected tool | Wiggleroom's shared container (`~/Library/Group Containers/…io.github.garoknows.wiggleroom/snapshots.json`, plus `snapshot.json` with Claude Code's numbers, kept so an older Wiggleroom still works) | Only your user account |
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
- Your Codex sign-in or conversations: Wiggleroom never opens `~/.codex/auth.json` or any file in `~/.codex` other than session logs, never calls OpenAI's servers, and never keeps any text from a session log.

Claude Code sends its status line much more than the usage numbers (for example the current folder and the model). Wiggleroom's helper reads only the `rate_limits` part, and an automated test feeds it a full sample and checks that nothing else ends up in the file.

## Reading Codex (only if you connect it)

A Codex session log holds your whole conversation, so Wiggleroom treats it with extra care:

- It opens only the newest plain session log in `~/.codex/sessions/` from the last 7 days, **read-only**. It never changes, moves or locks it, and never follows a link to somewhere else.
- It reads only the **last 256 KB** of that file.
- It looks only at lines that are Codex usage events (`token_count`), and from those copies out only each limit's percent used, its length and its reset time, plus the event's time. Every other line, and every other part of those lines, is dropped without being stored, logged or shown.
- An automated test fills an invented log with fake secrets (a fake prompt, a fake API key, a fake home folder path, secret text inside the usage event's other fields) and checks that none of it reaches the numbers, the saved file, the widget's file or anything on screen. It also checks that a 500 MB log is handled in under 50 milliseconds and 20 MB of memory, because only the end is read.

Wiggleroom writes nothing in `~/.codex`. Disconnecting Codex deletes `codex.json` and removes Codex from the widget.

## No network

There is no network code in the app, the widget or the helper. An automated test fails the build if networking code appears in the source, and another check inspects the built app for networking functions. Wiggleroom never needs the internet.

## Changing your Claude Code settings

Wiggleroom edits `~/.claude/settings.json` only when you click **Connect** or **Disconnect** (or **Delete All Wiggleroom Data**, which disconnects). Each time it:

- saves a backup first, in Wiggleroom's own private folder (never next to the file, so it can't land in a dotfiles repository),
- changes only the `statusLine` setting and leaves every other character as you wrote it,
- reads the result back and checks it before saving, and
- changes nothing at all if the file can't be read safely, and tells you why.

## Deleting your data

**Settings > Delete All Wiggleroom Data** disconnects from Claude Code and Codex, deletes every numbers file (Claude Code's, Codex's and the widget's copies) and resets Wiggleroom's preferences. It never touches anything in `~/.codex`. Backups of your Claude Code settings are your own settings, so they're kept in `settings-backups/`; delete that folder yourself if you don't want them. If you tried the one-day Headroom preview (this app's name before it was renamed), it also clears that preview's folder, `~/Library/Application Support/io.github.garoknows.headroom/`, the same way. It never touches `~/Library/Application Support/Headroom/`, which belongs to an unrelated app.

## Questions

Open an issue at [github.com/garoknows/wiggleroom](https://github.com/garoknows/wiggleroom/issues). Wiggleroom is an independent open-source project, not affiliated with Anthropic or OpenAI.
