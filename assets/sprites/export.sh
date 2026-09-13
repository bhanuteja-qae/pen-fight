#!/usr/bin/env bash
# Rasterise the SVG sources in src/ to PNG sprites.
#
# Uses Playwright's headless_shell, NOT `chrome --headless`: full Chrome reserves
# ~98px of window height, which silently crops the bottom of the output.
# Override the binary with HEADLESS_SHELL=/path/to/headless_shell.
set -euo pipefail

SHELL_BIN="${HEADLESS_SHELL:-/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell}"
[ -x "$SHELL_BIN" ] || { echo "headless_shell not found at $SHELL_BIN" >&2; exit 1; }
cd "$(dirname "$0")"

# render <src.svg> <w> <h> <scale> <out.png>
render() {
  local src=$1 w=$2 h=$3 scale=$4 out=$5
  local page; page=$(mktemp /tmp/penfight-XXXX.html)
  printf '<style>html,body{margin:0;padding:0;background:transparent;overflow:hidden}img{display:block;width:%spx;height:%spx}</style><img src="file://%s/src/%s">' \
    "$w" "$h" "$PWD" "$src" > "$page"
  "$SHELL_BIN" --no-sandbox --disable-gpu --hide-scrollbars \
    --default-background-color=00000000 \
    --force-device-scale-factor="$scale" --window-size="$w,$h" \
    --screenshot="$out" "file://$page" >/dev/null 2>&1
  rm -f "$page"
  echo "  $out"
}

echo "pens (440x96 source, pen length 360px at 1x):"
for p in pen_cobalt pen_amber pen_cobalt_shadow pen_amber_shadow; do
  render "$p.svg" 440 96 1 "$p.png"
  render "$p.svg" 440 96 2 "$p@2x.png"
done

echo "table (1440x840, desk surface at 160,120,1120x600):"
render table.svg 1440 840 1 table.png

echo "done."
