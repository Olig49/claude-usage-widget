# Changelog

All notable changes to Claude Usage Widget. Versions follow [semantic versioning](https://semver.org/).
Each version is a [GitHub release](https://github.com/mrcsXndr/claude-usage-widget/releases) with an installer.

## [1.9.1] - 2026-10-15

### Changed
- **What the rings show is now two independent choices** (Settings > Display). **Inside the ring**: Nothing, Initials or Percentage. **Next to the ring**: Nothing, Caption (5h / 7d) or Percentage. Any combination works: rings only, rings with small initials, percentage inside plus caption beside, and so on. Turning percentages on no longer hides the initials. Existing configs keep their look (`showPercents` / `showCaptions` are still understood until you pick).
- **Size**: Compact (as before), Normal or Large. Large shows each limit's reset time under the caption or percentage. The widget scales down to fit a short taskbar.
- **Dividers between accounts** are an option, off by default (the spacing stays the same either way).
- Spacing and text sizes derive from the chosen size, so rings, text and gaps stay in proportion.

## [1.9.0] - 2026-10-15

### Fixed
- **Rings showed more than the real percentage.** The arc was drawn with round caps, which stick out half a stroke width past both ends and closed the gap: 91% looked like 95%, 50% like 54%. Arcs now use flat caps and end exactly at the percentage (100% is a full circle). `-RingCheck` renders 0, 25, 50, 91 and 100% at 100, 125 and 150% scaling, measures each arc from the pixels and fails if one is off by more than 1 degree.
- **The widget flashed when you clicked it open or closed.** Closing rebuilt the whole list and the taskbar rose above the widget until a 750 ms timer put it back. The rings are now rebuilt only when something they show has changed (tooltips still refresh), nothing is rebuilt on close, and the widget is put back on top immediately.
- **Switching Settings tabs resized the window.** Settings is now its own window with a fixed size, so tabs only swap what is inside it.

### Changed
- **Settings is a normal Windows window**: title bar, resizable with a minimum size, tabs (Accounts, Display, Captions, Updates) and **OK / Cancel / Apply**. It opens from the cog or right-click > Settings, and keeps its size while the widget runs. Edits still preview on the taskbar; Cancel, Esc and the close button undo them.
- **Easier to read on a laptop.** Rings are 32 px instead of 30 with a thicker stroke, the numbers and initials are bold and larger, captions and names are brighter and larger, and there is more room between rings and accounts. Text uses pixel-snapped rendering at every display scale.

## [1.8.0] - 2026-10-13

### Added
- **Settings > Display > Percentages.** On by default (the look so far). Off, the taskbar shows only the rings, so many accounts fit: five Combined dials take about half the width. Combined becomes two rings (inner and outer) with the account's initials in the middle; Rings keeps one ring per limit with the initials inside each.
- **Initials inside the ring.** Each account gets 1-2 characters: the first letter of its name, or two letters for accounts whose first letters clash (fadir and fable become Fa and Fb). Change them per account in Settings > Accounts (the arrow on the row > Initials); empty means automatic. Stored as `"short"` in config.json.
- **Which ring is which.** Hovering an account on the taskbar now says where each limit sits (inner / outer ring, middle, or left / middle / right ring) and the colour thresholds, next to its percentages and reset times. The list has a one-line legend under it (for example "Inner 5h, outer 7d" and the green / amber / red key).

## [1.7.1] - 2026-10-10

Small fixes ship as patch versions from now on.

### Fixed
- **Find new accounts missed xndr-claude accounts added after the widget started.** Two causes, both silent: the widget only saw the PATH it started with, so a CLI installed later (or one whose account list changed behind a stale PATH) was "not installed"; and `xndr-claude usage --json` exiting non-zero (an account limited or errored) discarded the whole list. The PATH is now refreshed from the Machine/User environment when a command is not found, and a non-zero exit with a JSON list is accepted. Failures are logged with the exit code.
- Rings are now centred. The ring is an even number of device pixels across at any display scale (30 DIP was 37.5 px at 125%, putting the centre half a pixel off), the pie and ring share that centre, the window sits on whole device pixels, and the percentage and caption text are lifted about 0.6 px so the digits, not the line box, are centred on the ring (measured: 0.69 px low before, 0.00 after).

### Added
- **New accounts are found automatically**: at startup and every hour the widget checks xndr-claude and Claude Code logins. A new one shows as "New account found: <name>" with **Add** / **Ignore**, and a small dot on the widget. Nothing is added on its own; ignored names are remembered (`state.json`).
- **Settings tabs**: Accounts, Display, Captions, Updates. Save / Cancel stay global. In Accounts each account is one compact row; the arrow opens its style, plan and rings.
- **Reorder accounts** with the up / down arrows on each row. The order is saved in `config.json` and the taskbar follows it.

## [1.7.0] - 2026-10-10

### Fixed
- A token you approved is saved for real, at once. Closing or cancelling Settings no longer deletes the variable it created (that was why it seemed to vanish); the account is kept too. Only an explicit **Remove** deletes a variable (still asked first).
- After saving, the widget says where it went: "Saved as user environment variable CLAUDE_USAGE_TOKEN_<NAME> (Windows Settings → Environment Variables → User variables)".

### Added
- When xndr-claude is installed, the token approval offers **Save to xndr-claude** first (`xndr-claude add <name> --stdin`, the token goes over stdin, never argv). Without it, the user environment variable is used. These accounts use `source: xndr-claude`.

## [1.6.0] - 2026-10-10

### Added
- Settings > Add account > **Token**: paste a token from `claude setup-token` into a masked box and name the account. After an explicit approval ("Save this token as the Windows user environment variable CLAUDE_USAGE_TOKEN_<NAME>? It stays on this PC.") the widget stores it with `SetEnvironmentVariable(..., 'User')`, reads it back from the registry, and points the account at the variable. The token is never written to config.json, the log or a snapshot. A token that does not start with `sk-ant-oat` only gets a warning.
- Removing an account the widget created a variable for offers to delete that variable too (applied on Save).

### Changed
- Environment-variable accounts read `HKCU\Environment` first, so a variable set after the widget started is picked up without a restart.
- Add account offers two sources, Claude Code login and Token. xndr-claude (find and add) now appears only when it is installed; existing xndr-claude accounts are untouched. The old "Env var" source is replaced by Token (existing `env` accounts keep working).
- Cancelling Settings removes a token variable created in that session.

## [1.5.0] - 2026-10-10

### Added
- Self-update. Once a day the widget asks GitHub for the latest release (unauthenticated, short timeout, silent when offline or rate-limited). When it is newer than the installed version you get a tray notification, an "Update available" box with the first lines of the release notes, and an **Update now** button. Update now runs the official installer (`releases/latest/download/install.ps1`, that exact URL only) in a separate process; the widget restarts on the new version and confirms it.
- Settings: **Check for updates daily** (turn the automatic check off), **Check now**, and the installed version.

## [1.4.0] - 2026-10-10

### Added
- Account management in Settings. **Find new accounts** re-runs discovery and lists Claude Code logins and xndr-claude accounts that aren't in the widget yet; tick the ones to add (the plan comes from the login, else xndr-claude, else a picker). **Add account** takes a name, a source (Claude Code login folder with a Browse button, xndr-claude account, or env var name) and a plan. A bin on each account removes it, after a confirm. Like every Settings edit these apply on Save and are dropped on Cancel. Only references are stored; tokens are never shown.

## [1.3.0] - 2026-10-10

### Changed
- The plan label (Pro, Max 5x, Max 20x) now comes from the API (`/api/oauth/profile`) for every token that can read it, on each refresh, so a plan upgrade shows without editing anything. The last good answer is kept when a call fails.

### Added
- A per-account Plan picker in Settings: Auto, Pro, Max 5x, Max 20x. Setup-tokens can't read their plan from the API (the profile endpoint returns 403 and no response header carries it), so for those accounts the picked plan is shown. The plan found when the account was added is the initial pick. Hover an account in the list to see where its plan came from.

## [1.2.2] - 2026-09-29

### Fixed
- If you closed the popup while Settings was open, Settings flashed briefly the next time you opened it. Closing from Settings now returns to the main list, and reopening shows only the list, fading in cleanly.

### Added
- Optional debug log of popup open/close decisions. Set `CUW_DEBUG=1` to turn it on.

## [1.2.1] - 2026-09-29

### Fixed
- The popup no longer flickers or jumps when it opens or when you switch between the list and Settings.

### Added
- The popup fades and slides in when it opens, and fades softly when you switch to or from Settings.
- **Settings → Display → Animations** turns the animations off (`"animations": false`).

## [1.2.0] - 2026-09-29

### Added
- **Save** and **Cancel** in Settings. Changes preview on the taskbar right away. Save keeps them, and Cancel (or Esc) undoes them. Clicking away keeps them.
- Settings options to turn account names and ring captions on the taskbar on or off.
- A refresh interval setting: every 30 minutes by default, 5 minutes at the most frequent.

### Changed
- The combined style's legend markers (● for the pie, ○ for the ring) are now the same size, so both lines line up.
- The per-account "In list" checkbox is gone; the checkbox next to the name is the only one. `"hidden": true` in the config still hides an account.

## [1.1.0] - 2026-09-29

### Added
- **Combined** style: one limit as a pie in the middle and the other as the ring around it, with both percentages beside it. You choose which limit goes in the middle, and each account can use Rings or Combined.

## [1.0.1] - 2026-09-29

### Added
- **Uninstall…** in the right-click menu (it asks you to confirm first), and an Uninstall section in the README.

## [1.0.0] - 2026-09-29

First release.

- 5-hour, 7-day and Fable weekly limits as rings on the Windows 11 taskbar. They're colour-coded at 70% and 90%.
- An account list that opens with one click, with reset countdowns. Tick accounts to show them side by side on the taskbar.
- Finds Claude Code logins (`~/.claude*`) and [xndr-claude](https://github.com/mrcsXndr/xndr-claude) accounts automatically. Other tokens can come from a command or an environment variable.
- Free usage reads through the usage API where a token allows it, and a tiny 1-token probe for setup-tokens.
- Settings: rename accounts, choose each account's rings, rename the ring captions.
- One-line installer with no admin rights, git or Node needed. Adds a Start menu entry, starts with Windows, and can be uninstalled from Settings → Apps.

[1.2.2]: https://github.com/mrcsXndr/claude-usage-widget/releases/tag/v1.2.2
[1.2.1]: https://github.com/mrcsXndr/claude-usage-widget/releases/tag/v1.2.1
[1.2.0]: https://github.com/mrcsXndr/claude-usage-widget/releases/tag/v1.2.0
[1.1.0]: https://github.com/mrcsXndr/claude-usage-widget/releases/tag/v1.1.0
[1.0.1]: https://github.com/mrcsXndr/claude-usage-widget/releases/tag/v1.0.1
[1.0.0]: https://github.com/mrcsXndr/claude-usage-widget/releases/tag/v1.0.0
