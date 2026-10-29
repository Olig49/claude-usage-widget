#!/bin/bash
# Removes Claude Usage, its settings and the tokens it saved in the Keychain. Your Claude Code logins are never touched.
# Add --keep-settings to keep config.json for a later reinstall.
set -euo pipefail

APP="$HOME/Applications/Claude Usage.app"
SETTINGS="$HOME/Library/Application Support/claude-usage-widget"

pkill -x ClaudeUsageBar 2>/dev/null || true
rm -rf "$APP" "/Applications/Claude Usage.app"
defaults delete io.github.claude-usage-widget.mac >/dev/null 2>&1 || true

if [ "${1:-}" != "--keep-settings" ]; then
  rm -rf "$SETTINGS"
  # Tokens pasted in Settings (service "claude-usage-widget"); Claude Code's own items are left alone.
  while security delete-generic-password -s claude-usage-widget >/dev/null 2>&1; do :; done
fi

echo "Claude Usage removed."
echo "If it still appears under System Settings > General > Login Items, remove it there."
