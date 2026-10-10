# Changelog

All notable changes to Claude Usage Widget. Versions follow [semantic versioning](https://semver.org/).
Each version is a [GitHub release](https://github.com/mrcsXndr/claude-usage-widget/releases) with an installer.

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
