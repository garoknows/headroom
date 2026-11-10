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

Compare the widget with **Settings > Usage** on claude.ai. They should match within a point. If the widget shows "Connect Wiggleroom to Claude Code", send another message in Claude Code and wait a few seconds.

## Options

In Wiggleroom's Settings:

- **Alerts:** a notification when you pass 90% of your weekly limit (and 75% if you turn it on). Once per week each.
- **Show in the menu bar:** your weekly percent next to a small gauge. Click it for the full card.
- **Open at login:** keeps the widget current after a restart. On by default after setup.
- **Reveal Data File** and **Delete All Wiggleroom Data**.

## What the widget states mean

| You see | It means |
| --- | --- |
| "As of 2:41 PM" in grey | Numbers from Claude Code's last reply at 2:41 PM. |
| "As of" in amber | The numbers are over 30 minutes old. Usage elsewhere (claude.ai, the Claude app) isn't counted until your next Claude Code reply. |
| Dimmed bars | The numbers are over 6 hours old. |
| "Reset at 1:00 AM, waiting for new numbers" | That limit has reset; fresh numbers come with your next Claude Code reply. |
| "Connect Wiggleroom to Claude Code" | No numbers yet. Connect, then send a message in Claude Code. |
| "This copy of Wiggleroom can't share numbers with widgets" | You're running an unsigned build. Use the menu bar item, or install the signed release. |

## Uninstall

1. In Wiggleroom's Settings, click **Disconnect** (your previous status line comes back), or **Delete All Wiggleroom Data** (also disconnects).
2. Click **Quit Wiggleroom** at the bottom of Settings, then drag Wiggleroom to the Trash.

Using Homebrew? `brew uninstall --cask wiggleroom` removes the app (your previous status line keeps working even if you skip step 1), and `--zap` also removes Wiggleroom's files.
