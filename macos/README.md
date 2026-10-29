# Claude Usage for macOS

**Your Claude 5-hour, 7-day and Fable limits as small rings in the Mac menu bar.** A native Swift port of the Windows widget in this repo, with the same features, reading the same numbers the same way.

## Features

- **Rings in the menu bar.** Each ring is green below 70%, amber below 90% and red from 90%. Hover for the numbers and when each limit resets.
- **Two styles per account.** **Rings** gives each limit its own ring. **Combined** puts one limit in the middle of a single dial (a pie, or an inner ring) with the other as the ring around it.
- **Choose what you see.** Inside the ring: nothing, initials or the percentage. Next to it: nothing, the caption, the percentage, "in 1h 34m" or "Sat 03:02". Size Compact, Normal or Large (Large adds the reset time), spacing Tight, Normal or Wide, account names left, right or hidden, and optional lines between accounts.
- **Several accounts.** Claude Code logins (found automatically in `~/.claude` and every other `~/.claude*` folder), tokens from `claude setup-token` (kept in your Keychain), or a command such as a password manager CLI. Tick the accounts you want in the menu bar. An account can hide itself while it's at its limit.
- **All limits in one click.** The list shows every account's 5-hour window, 7-day window and Fable weekly limit with bars and reset countdowns.
- **Settings window.** Accounts, Display, Captions and Updates tabs. Changes preview in the menu bar right away; **OK** or **Apply** keeps them, **Cancel** undoes them.
- **Stays out of the way.** Refreshes every 30 minutes by default (5 at the most frequent), at most once a minute by hand, catches up after sleep, follows a light or dark menu bar, has no Dock icon, and starts at login.
- **Update check.** Once a day it looks for a newer Mac release on GitHub and tells you; it never downloads anything by itself.

## Install

### Build it yourself (recommended)

You need macOS 13 (Ventura) or later and the Xcode Command Line Tools. If `swift --version` doesn't work in Terminal, run `xcode-select --install` first.

```bash
git clone -b macos-menu-bar https://github.com/Olig49/claude-usage-widget.git
cd claude-usage-widget/macos
./scripts/install.sh
```

That builds **Claude Usage.app**, copies it to `~/Applications` and starts it. Running the script again (after `git pull`) updates it and keeps your settings. An app you build yourself opens without any security warning.

### Or download it

Each push builds the app on GitHub: open the fork's **Actions → macOS build**, pick the latest green run, and download **ClaudeUsage-macOS** under Artifacts. The app isn't signed by a registered Apple developer, so macOS blocks it at first ("Apple could not verify…"). Click **Done**, then either:

- open **System Settings → Privacy & Security**, scroll to **Security** and click **Open Anyway** next to "Claude Usage", or
- run `xattr -dr com.apple.quarantine "/Applications/Claude Usage.app"` in Terminal.

You only do this once.

**On a MacBook with a notch,** macOS hides menu bar items that don't fit left of the notch, without telling you. If the rings don't appear, quit an app with a menu bar icon, or choose a more compact look in Settings → Display.

## Use

| | |
| --- | --- |
| **Click** the rings | Open the account list |
| **Tick** an account | Show it in the menu bar (with none ticked, the first account is shown) |
| **⟳** | Refresh now (at most once a minute) |
| **⚙** or **⌘,** | Settings |
| **⋯** | Scan for accounts · Launch at login · Open config file · Open log · Quit |
| **Right-click** the rings | Refresh · Settings · Scan for accounts · Launch at login · Open config file · Open log · Uninstall · Quit |
| **⌘ + drag** | Move the rings along the menu bar (a macOS feature) |

## Settings

**Accounts:** rename an account, set its initials, show or hide it, choose Rings or Combined, pick which rings it shows (or which limit sits in the middle of the dial), set its plan, turn the Fable check off, replace a token, change its folder or command, reorder accounts, and remove them. **+** adds an account or finds new Claude Code logins.

**Display:** what goes inside and next to the rings, size, spacing, account names, the middle of combined dials, lines between accounts, hiding accounts at their limit, the colour key under the list, the refresh interval and launch at login.

**Captions:** rename "5h", "7d" and "Fable".

**Updates:** the installed version, the daily check, and Check now.

## Accounts

There are three kinds of account:

| Source | Where the token comes from |
| --- | --- |
| **Claude Code login** | Claude Code's own login for a config folder. Found automatically. |
| **Token** | A token from `claude setup-token`, pasted in Settings → Accounts → + → Add account. Saved in your login Keychain (service `claude-usage-widget`), never in a file. |
| **Command** | Whatever a command prints, for example `op read op://Private/claude/token`. Runs in your login shell. |

**Another Claude Code account:** run `CLAUDE_CONFIG_DIR=~/.claude-work claude` in Terminal, sign in with `/login`, then choose **Scan for accounts** (or Settings → Accounts → + → Find new Claude Code logins). Each login keeps its own `~/.claude*` folder; your main login in `~/.claude` isn't touched.

**How Claude Code logins are read:** on a Mac, Claude Code keeps its login in the login Keychain:

| Config folder | Keychain item (service) |
| --- | --- |
| `~/.claude` (default) | `Claude Code-credentials` |
| any other folder set with `CLAUDE_CONFIG_DIR` | `Claude Code-credentials-<first 8 hex of SHA-256 of the folder path>` |

The app reads these with Apple's `security` tool, the same tool Claude Code uses to save them, so macOS normally doesn't ask. If it does, choose **Always Allow**. A `.credentials.json` file in the folder is used when there's no Keychain item.

## How it works

For each account it calls `GET api.anthropic.com/api/oauth/usage`, which is free and works for Claude Code logins. Setup tokens aren't allowed to use that endpoint, so for those it sends a 1-token request and reads the limits from the rate-limit headers (about 35 tokens per refresh). It sends that request to Fable, because only then does the reply include the Fable weekly limit; you can turn that off per account. The plan label comes from `/api/oauth/profile` when the token may read it, else from the plan you picked.

**Claude Code logins expire.** The app only reads them and never renews them, because renewing would sign Claude Code out. If you see "Login expired", run Claude Code with that folder once.

**After rebuilding the app,** macOS may ask once whether Claude Usage may read the tokens it saved in your Keychain, because each build has a new signature. Choose **Always Allow**.

## Config file

Everything is stored in `~/Library/Application Support/claude-usage-widget/config.json` (⋯ → **Open config file…**). It uses the same names as the Windows widget, so you can copy display settings across. Settings is the easier way to change it; hand edits are picked up at the next refresh.

```json
{
  "refreshMinutes": 30,
  "inside": "percent",
  "next": "none",
  "size": "compact",
  "spacing": "normal",
  "captions": { "5h": "5h", "7d": "7d", "fable": "Fable" },
  "accounts": [
    { "name": "claude-code", "label": "me@personal.com", "source": "claude-code", "menuBar": true },
    { "name": "claude-code-work", "label": "me@work.com", "source": "claude-code",
      "dir": "/Users/me/.claude-work", "menuBar": true, "style": "combined", "pie": "5h" },
    { "name": "ci", "label": "CI", "source": "token", "plan": "Max 5x" },
    { "name": "vault", "label": "Vault", "source": "command", "command": "op read op://Private/claude/token" }
  ]
}
```

| Setting | Values |
| --- | --- |
| `refreshMinutes` | Minutes between refreshes, 5 at the lowest |
| `inside` | `none`, `initials`, `percent` (default) |
| `next` | `none` (default), `caption`, `percent`, `resetin`, `resetat` |
| `size` | `compact` (default), `normal`, `large` |
| `spacing` | `tight`, `normal` (default), `wide` |
| `names` | `left`, `right`, `hidden`; leave out for automatic (left when several accounts are shown) |
| `innerWindow` | `5h` (default) or `7d`: the middle of combined dials |
| `hideAtLimit`, `showDividers`, `showLegend` | `true` / `false` |
| `updateCheck` | `false` turns the daily update check off |

| Account field | Meaning |
| --- | --- |
| `source` | `claude-code`, `token` or `command` |
| `dir` | Claude Code config folder (leave out for `~/.claude`) |
| `command` | For `command` accounts |
| `menuBar` | Show in the menu bar |
| `style` | `rings` (default) or `combined`; `pie` picks the middle limit (`5h` / `7d`) |
| `limits` | Rings to draw: any of `"5h"`, `"7d"`, `"fable"` (default 5h and 7d) |
| `short` | 1-2 letters for initials inside the ring |
| `plan` | Plan label when the API can't tell (`Pro`, `Max 5x`, `Max 20x`) |
| `hidden` | Leave the account out of the list and the menu bar |
| `fable` | `false` skips the Fable probe |

## Privacy

- Tokens are held in memory only for one request. They're never written to config.json or the log, and never passed on a command line.
- The only network calls go to `api.anthropic.com`, plus `api.github.com` for the daily update check (which you can turn off).
- Settings live in `~/Library/Application Support/claude-usage-widget`; pasted tokens live in your login Keychain.

## Uninstall

Right-click the rings and choose **Uninstall…**. That removes the login item, the app's settings, the tokens it saved, and moves the app to the Trash. Your Claude Code logins aren't touched. From Terminal instead:

```bash
./scripts/uninstall.sh            # add --keep-settings to keep config.json
```

## Publishing a release

The update check looks for GitHub releases on this fork whose tag starts with `mac-v` (so they don't mix with the Windows `v…` tags). To publish one: bump `AppInfo.version` in `Sources/UsageCore/Config.swift` and `CFBundleShortVersionString` in `Resources/Info.plist`, push, download the zip from the green Actions run, and create a release tagged e.g. `mac-v1.1.0` with the zip attached.

## For developers

```bash
swift build          # debug build
swift test           # unit tests for UsageCore
swift run            # runs from the terminal (launch at login only works from the .app)
./scripts/build-app.sh
```

| Path | What it does |
| --- | --- |
| `Sources/UsageCore` | No UI: config, token sources (Claude Code logins, Keychain tokens, commands), usage API, probe, update check, formatting |
| `Sources/ClaudeUsageBar` | The menu bar app: status item, ring drawing, dropdown, Settings window, timers, launch at login, uninstall |
| `Tests/UsageCoreTests` | Unit tests for `UsageCore` |
| `scripts/` | Build, install and uninstall |
