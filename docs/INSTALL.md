# Installing Wiggleroom

You need a Mac with macOS 14 Sonoma or later, and Claude Code signed in with a Claude Pro, Max or Ultra plan.

## Tried the Headroom preview?

For one day this app was published as an unsigned preview called Headroom (it was renamed because another Mac app already uses that name). If you installed it, do this first:

1. Open **Headroom** and click **Disconnect** in its Settings. Your previous status line comes back.
2. Quit Headroom (**Quit Headroom** at the bottom of Settings).
3. Drag Headroom from Applications to the Trash.

Then continue below. If you skip these steps, Wiggleroom handles it anyway: **Connect to Claude Code** replaces the Headroom entry in your status line setting, keeps your own status line if you had one, and never runs the Headroom helper. Wiggleroom doesn't copy the preview's numbers; fresh ones arrive with your next Claude Code reply. **Delete All Wiggleroom Data** also clears the preview's old folder (`~/Library/Application Support/io.github.garoknows.headroom/`, keeping any settings backups in it). It never touches folders of the unrelated app that is also called Headroom.

## 1. Download and open

1. Go to [Releases](https://github.com/garoknows/wiggleroom/releases) and download the newest `Wiggleroom-<version>.dmg`.
2. Open the file and drag **Wiggleroom** onto **Applications**.
3. Open **Wiggleroom** from your Applications folder. (Opening it straight from the download window works too, but Wiggleroom will ask you to move it to Applications before connecting, because Claude Code needs a place that won't move.)

The setup window appears. It walks you through the next two steps:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="images/window-setup-dark.png">
  <img src="images/window-setup-light.png" width="620" alt="The Set Up Wiggleroom window: a welcome line, step 1 Connect to Claude Code with its button, and step 2 Add the widget to Notification Center with the first two annotated pictures. The rest of the window scrolls.">
</picture>

Wiggleroom has no Dock icon. It runs quietly in the background. To get back to it later, open it again from Applications: its Settings window appears.

## 2. Connect to Claude Code

In the setup window (or Settings), click **Connect to Claude Code**.

What this does: it adds Wiggleroom's small helper to the `statusLine` setting in `~/.claude/settings.json`. It changes nothing else in that file, and saves a backup first, in Wiggleroom's own private folder (`~/Library/Application Support/io.github.garoknows.wiggleroom/settings-backups/`), not next to your settings, so a backup can never end up in a dotfiles repository. If you already had a status line, Wiggleroom runs it after saving the numbers, so it looks exactly the same.

Then send any message in Claude Code. The numbers arrive with its reply.

## 3. Add the widget

![Step 1: click the date and time in the menu bar](images/setup-1-menu-bar-light.png)

**1.** Click the date and time at the right end of the menu bar. Notification Center opens.

![Step 2: click Edit Widgets](images/setup-2-notification-center-light.png)

**2.** Scroll to the bottom and click **Edit Widgets**.

![Steps 3 and 4: search for Wiggleroom and click the plus button](images/setup-3-widget-gallery-light.png)

**3.** Type **Wiggleroom** in the search field.
**4.** Choose the small or medium size and click the green **+** (or drag the widget where you want it). Click **Done**.

You can also put the widget on your desktop: right-click the desktop, choose **Edit Widgets**, and drag it there.

## 4. Check the numbers

Compare the widget with **Settings > Usage** on claude.ai. They should match within a point (Wiggleroom rounds up, so it never shows less than you've used). If the widget shows "Connect Wiggleroom to Claude Code", send another message in Claude Code and wait a few seconds.

## 5. Add Codex (optional)

If you also use Codex with a ChatGPT plan:

1. Open Wiggleroom's Settings (open Wiggleroom again from Applications) and find **Tools**.
2. Click **Connect** next to Codex. It says "Connected. Your numbers appear after Codex's next reply."
3. Run one prompt in Codex. Within a few seconds Wiggleroom shows Codex's 5-hour and weekly limits. Compare them with Codex's own limits display (`/status` in the Codex CLI); they should match within a point.
4. Right-click the widget, choose **Edit Widget**, and set **Tool** to **All tools** to see both tools in one widget, or to **Codex** for Codex only. You can also add a second widget for each tool.

What Connect does: nothing in Codex changes. Wiggleroom starts watching Codex's session folder (`~/.codex/sessions/`) and, after each Codex reply, reads only the usage numbers from the end of the newest session log, read-only. [How Codex is read](TOOLS.md#how-wiggleroom-treats-codexs-log).

If Settings says "Codex not found on this Mac", Codex hasn't been installed or run yet. Run Codex once, then click **Check Again**. If it says "Codex isn't reporting plan limits", you're signed in to Codex with an API key; plan limits are only reported when you sign in with ChatGPT.

## Options

In Wiggleroom's Settings:

- **Tools:** connect or disconnect Claude Code and Codex. "More tools" links to [which tools are supported and which are coming](TOOLS.md).
- **Alerts:** a notification when a tool passes 90% of a limit (and 75% if you turn it on), for every connected tool and every limit, at most once per level, per tool, per limit. For example: "Codex: 90% of your weekly limit used. Resets Monday 1:00 AM."
- **Show in the menu bar:** a weekly percent next to a small gauge. **Menu bar shows** picks whose: **Highest of my tools** (the default; hold the pointer over it to see which tool), **Claude Code** or **Codex**. Click it for every tool's limits, with the menu bar's tool first. With both tools, the popover is compact: each tool's weekly limit, plus any other limit at 75% or more.
- **Open at login:** keeps the widget current after a restart. On by default after setup.
- **Reveal Data File** and **Delete All Wiggleroom Data**.

## What the widget states mean

| You see | It means |
| --- | --- |
| "As of 2:41 PM" in grey | Numbers from the tool's last reply at 2:41 PM. The medium widget names the tool on this line ("Codex · As of 2:41 PM"). |
| "As of" in amber | The numbers are over 30 minutes old. Usage elsewhere (claude.ai, the Claude app) isn't counted until your next Claude Code reply. |
| "As of 9:29 PM · Codex 8:21 PM" (All tools) | One tool's numbers are older than the other's. The first time covers the up-to-date tool; the older tool's name and time follow in amber, so a tool you haven't used lately doesn't make the whole widget look out of date. |
| Dimmed bars | The numbers are over 6 hours old. |
| "Reset at 1:00 AM, waiting for new numbers" | That limit has reset; fresh numbers come with your next Claude Code reply. |
| "Connect Wiggleroom to Claude Code" | No numbers yet. Connect, then send a message in Claude Code. |
| "Codex" with "Connect Codex in Wiggleroom's Settings" | The widget is set to Codex, but there are no Codex numbers yet. Connect Codex (step 5), then run a Codex prompt. |
| One row per tool, titled with each tool's name | The widget's Tool is All tools. The tool closest to its limit comes first. |
| "This copy of Wiggleroom can't share numbers with widgets" | You're running an unsigned build. Use the menu bar item, or install the signed release. |

## Uninstall

1. In Wiggleroom's Settings, click **Disconnect** (your previous status line comes back), or **Delete All Wiggleroom Data** (also disconnects).
2. Click **Quit Wiggleroom** at the bottom of Settings, then drag Wiggleroom to the Trash.

Codex needs nothing undone: Wiggleroom never changed anything in Codex.

Using Homebrew? `brew uninstall --cask wiggleroom` removes the app (your previous status line keeps working even if you skip step 1), and `--zap` also removes Wiggleroom's files.
