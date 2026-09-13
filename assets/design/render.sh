#!/usr/bin/env bash
# Re-render the design references. Uses Playwright's headless shell, NOT full
# chrome --headless: full chrome reserves ~98px of window height, which silently
# crops the bottom of the frame.
set -euo pipefail
SHELL_BIN="${HEADLESS_SHELL:-/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell}"
cd "$(dirname "$0")"
shot() { "$SHELL_BIN" --no-sandbox --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=2 --window-size="$2" --screenshot="$3" "file://$PWD/$1"; }
shot table-view.html 1280,600 pen-fight-table.png
shot pen-sheet.html   1280,940 pen-design-sheet.png
