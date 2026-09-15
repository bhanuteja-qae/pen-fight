#!/usr/bin/env bash
# Live-run capture: launch the real game under Xvfb with the deterministic
# autoplay harness and grab x11 frames across a whole match.
set -u
cd /home/ubuntu/pen-fight/game
GODOT=/home/ubuntu/godot/Godot_v4.7.2-stable_linux.x86_64
export DISPLAY=:99
export LIBGL_ALWAYS_SOFTWARE=1
export PENFIGHT_AUTOPLAY=1
OUT=${1:-/tmp/pf_live}
N=${2:-26}
mkdir -p "$OUT"
rm -f "$OUT"/frame_*.png

"$GODOT" --path . >"$OUT/run.log" 2>&1 &
GPID=$!
sleep 4   # let it boot + import-warm

for i in $(seq -w 1 "$N"); do
  ffmpeg -y -loglevel error -f x11grab -video_size 1280x720 -i :99 \
    -frames:v 1 "$OUT/frame_$i.png" 2>/dev/null
  sleep 1
done

kill "$GPID" 2>/dev/null || true
wait "$GPID" 2>/dev/null || true
for pid in $(pgrep -f 'Godot_v4\.7\.2' || true); do [ "$pid" = "$$" ] || kill "$pid" 2>/dev/null || true; done

echo "frames: $(ls "$OUT"/frame_*.png | wc -l)"
grep -c -i -E 'ERROR|SCRIPT ERROR' "$OUT/run.log" || true
grep -i -E 'SCRIPT ERROR|Parse Error' "$OUT/run.log" | head -5 || true
