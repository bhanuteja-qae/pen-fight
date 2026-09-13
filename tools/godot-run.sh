#!/usr/bin/env bash
# Pinned Godot runner for the screenshot loop on this (headless) Linux box.
# Always runs under Xvfb so the engine always has a display + GL context.
# Verify: ./tools/godot-run.sh --version
set -euo pipefail
GODOT="${GODOT:-$HOME/godot/Godot_v4.7.2-stable_linux.x86_64}"
RES="${RES:-1280x720x24}"
export LIBGL_ALWAYS_SOFTWARE=1   # mesa swrast: force software rendering, don't probe X
exec xvfb-run -a -s "-screen 0 $RES" "$GODOT" "$@"