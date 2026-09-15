#!/usr/bin/env bash
# Wave-4 status capture: engine-side shots of the shipped build under Xvfb.
set -u
cd /home/ubuntu/pen-fight/game
GODOT=/home/ubuntu/godot/Godot_v4.7.2-stable_linux.x86_64
export DISPLAY=:99
export LIBGL_ALWAYS_SOFTWARE=1

for pid in $(pgrep -f 'Godot_v4\.7\.2' || true); do
  [ "$pid" = "$$" ] || kill "$pid" 2>/dev/null || true
done
sleep 1

echo "=== import (pass 1) ==="
timeout 300 "$GODOT" --headless --editor --quit --import . 2>&1 | tail -2
echo "=== import (pass 2) ==="
timeout 300 "$GODOT" --headless --editor --quit --import . 2>&1 | tail -2

echo "=== skin_shot ==="
mkdir -p /tmp/skin_frames
timeout 300 "$GODOT" --path . --script res://tests/skin_shot.gd 2>&1 \
  | grep -v -E 'ALSA|PulseAudio|pulse|audio|dummy' | tail -25

echo "=== settings_shot ==="
timeout 300 "$GODOT" --path . --script res://tests/settings_shot.gd 2>&1 \
  | grep -v -E 'ALSA|PulseAudio|pulse|audio|dummy' | tail -12

echo "=== artifacts ==="
ls -la /tmp/skin_frames/ 2>&1
ls -la /tmp/settings_shot*.png 2>&1
