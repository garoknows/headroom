# Which tools Wiggleroom supports

Wiggleroom shows the usage limits of the AI coding tools you pay for. It adds a tool only when that tool hands out its plan's limits through a channel its own maker supports: something the tool gives Wiggleroom directly, or writes on your own Mac in a documented or visible form.

Wiggleroom never uses your sign-in token, browser cookies, a browser session or an undocumented web address to get the numbers. That's what keeps it free of network code and safe to run.

*Last checked: November 10, 2026.*

## Supported

| Tool | How Wiggleroom gets the numbers |
| --- | --- |
| **Claude Code** (Pro, Max and Ultra plans) | Claude Code hands its usage to its [status line](https://code.claude.com/docs/en/statusline) after every reply. Wiggleroom's small helper keeps only the numbers. Since Wiggleroom 0.1. |
| **Codex** (signed in with ChatGPT) | After each reply, Codex writes a usage event into its own session log on your Mac (`~/.codex/sessions/`), with the same 5-hour and weekly numbers Codex shows in its limits display. Wiggleroom reads only those numbers, read-only, from the end of the newest log. Since Wiggleroom 0.2. |

### How Wiggleroom treats Codex's log

A Codex session log holds your whole conversation, so Wiggleroom is strict about it:

- It opens only the newest session log from the last 7 days, read-only, and never changes, moves or locks it.
- It reads only the last 256 KB, where the newest events are.
- It looks only at Codex's usage events and copies out only the percent used, the window length, the reset time and the time of the event. Everything else is ignored and never stored, logged or shown.
- An automated test fills an invented log with fake secrets and checks that none of them reaches anything Wiggleroom keeps or shows.

Codex signed in with an API key (not ChatGPT) doesn't report plan limits, so Wiggleroom says so instead of showing 0%. Codex compresses a session after it ends; Wiggleroom doesn't read compressed logs, and doesn't need to, because the session that just replied is never compressed.

## Not yet

| Tool | Why not yet |
| --- | --- |
| **Grok Build** (xAI) | Its status line can run a command, but the information it hands over has no plan or quota fields, and xAI hasn't published Grok Build quotas. The `/usage` command shows credits on screen only. Waiting on xAI. |
| **Gemini CLI** | No official way to read the remaining quota was found. `/stats` shows numbers only on screen, and counting session files would be a guess, not a reading. Google has also moved personal-plan users to a different tool this year. |
| **GitHub Copilot CLI** | Its status line reports requests used in the current session, not your monthly allowance. The allowance is only in GitHub's billing service, which would need your token and the internet, and Wiggleroom has no network code. |

If one of these starts handing out its plan's limits officially, Wiggleroom will add it. If you know of a change, [open an issue](https://github.com/garoknows/wiggleroom/issues).

## Considered and set aside for Codex

- **Asking Codex's background server for the limits.** Codex has a server mode with a call that returns rate limits, but using it would make Codex contact OpenAI in the background with your sign-in, on a timer. It's barely documented, and it would make "no network" harder to keep true.
- **A Codex status line command.** Codex's status line offers only built-in items today; custom commands are an open feature request. If Codex adds them with limit fields, Wiggleroom will switch to that, the same way it works with Claude Code.

Wiggleroom is an independent project. It is not made by, affiliated with or endorsed by Anthropic, OpenAI, xAI, Google or GitHub. Tool names are used only to say what Wiggleroom works with.
