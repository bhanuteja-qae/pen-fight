#!/usr/bin/env bash
# Focused regression suites for the turn-gate prompt-fit change.
# Runs the gate-facing suites (headless) and reports each one's verdict line.
set -u
# Run against the checkout this script lives in (works from any git worktree).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../game"
GODOT=/home/ubuntu/godot/Godot_v4.7.2-stable_linux.x86_64
export DISPLAY=:99
export LIBGL_ALWAYS_SOFTWARE=1

# Godot's global class cache lives in .godot/ (gitignored, never committed), so a
# fresh checkout — or any newly added class_name — needs ONE import pass before
# scripts that reference that class will parse. Without this, a new class makes
# every suite that loads main.gd fail with "Identifier X not declared in the
# current scope", which looks like a real regression and is not one.
echo "===== import pass (global class cache)"
"$GODOT" --headless --editor --quit --import . >/dev/null 2>&1
echo "   exit=$?"

run() {
  local name="$1" budget="$2"
  echo "===== $name (timeout ${budget}s)"
  timeout "$budget" "$GODOT" --headless --path . --script "res://tests/$name.gd" 2>&1 \
    | grep -v -E 'ALSA|PulseAudio|pulse|audio lib' \
    | grep -E 'PASS|FAIL|ERROR|SUMMARY|cases|rounds|assert|\[LOOP\]' | tail -12
  echo "   exit=${PIPESTATUS[0]}"
}

run display_name_test 120
run series_record_test 120
run turn_state_test 120
run loop_attribution_test 120
run touch_input_test 180
run settings_test 120
run auto_flick_test 180
run adjacent_pen_hit_test 300
run match_contract_test 120
run main_shot_submission_test 240
run aim_overlay_smoke 120
