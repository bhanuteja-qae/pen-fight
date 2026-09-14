#!/usr/bin/env python3
"""Generate the top-down classroom floor assets for pen-fight.

Outputs (both in game/assets/):
  table_classroom.png (1440x840) — table.png with the near-black bleed ring
      repainted as light-gray tiled linoleum, desk region preserved exactly.
  background_classroom.png (1280x720) — matching floor for ultra-wide aspects
      (sits BEHIND the table sprite; only visible when the window is wider than
      the table sprite's aspect, so its tile grid is phase-aligned to the
      table sprite's grid in viewport space).

Origin geometry (measured from table.png, not guessed):
  * table.png is 1440x840; the desk content occupies EXACTLY x160..1279,
    y120..719 (1120x600 = the playfield). Everything else is bleed.
  * The bleed is near-black (14,10,8) with a slight shadow ramp toward the desk.

WHY THIS SCRIPT EXISTS: the first version of this repaint (2026-09-14) shipped a
1-pixel black screen-door instead of a floor — two bugs, both invisible to the
verification it used:
  1. the "ensure nothing stays void-black" sweep iterated every 2nd pixel in BOTH
     axes, so only 25% of the bleed was ever repainted, leaving a near-black
     lattice at 3/4 of the ring's pixels;
  2. the per-tile tone variation was applied with a stride-2 x loop.
Both the repaint and its verification sampled on the same even lattice, so the
check reported "0 near-black pixels" on an asset that was 33% near-black.

RULES FOR ANYONE EDITING THIS:
  * never verify a texture by sampling every Nth pixel — a 1px lattice aliases
    perfectly against any even stride. Verify at full resolution (this script
    does) and, for looks, use an AREA/box downscale, never point sampling.
  * keep the desk rect exact; it is the physics playfield.

Run:  /home/ubuntu/pen-fight/.asset-venv/bin/python generate_classroom_floor.py
"""

from __future__ import annotations

import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ASSETS = Path(__file__).resolve().parent
SRC = ASSETS / "table.png"
DST_TABLE = ASSETS / "table_classroom.png"
DST_BG = ASSETS / "background_classroom.png"

# measured from table.png (see module docstring)
DESK = (160, 120, 1280, 720)  # x0, y0, x1, y1  (x1/y1 exclusive)
FEATHER = 14                  # px ramp wood -> floor at the desk rim

# palette: neutral light gray, so the in-engine CanvasModulate tint stays the
# single knob that decides the room's warmth
BASE = (128, 130, 133)
GROUT = (112, 114, 117)
TILE = 40
TONE = 5                      # per-tile lightness jitter, +-TONE
SEED = 20260914


def floor_tiles(w: int, h: int, origin: tuple[int, int] = (0, 0),
                blur: float = 1.0) -> Image.Image:
    """Full-coverage tiled linoleum: every pixel written, no stride tricks."""
    rnd = random.Random(SEED)
    im = Image.new("RGB", (w, h), BASE)
    px = im.load()
    ox, oy = origin
    # per-tile tone variation over the WHOLE tile
    for ty in range(-oy % TILE - TILE, h + TILE, TILE):
        for tx in range(-ox % TILE - TILE, w + TILE, TILE):
            shade = rnd.randint(-TONE, TONE)
            if shade == 0:
                continue
            for yy in range(max(ty, 0), min(ty + TILE, h)):
                for xx in range(max(tx, 0), min(tx + TILE, w)):
                    r, g, b = px[xx, yy]
                    px[xx, yy] = (min(255, r + shade), min(255, g + shade),
                                  min(255, b + shade))
    draw = ImageDraw.Draw(im)
    for x in range(-ox % TILE, w, TILE):
        draw.line([(x, 0), (x, h - 1)], fill=GROUT, width=1)
    for y in range(-oy % TILE, h, TILE):
        draw.line([(0, y), (w - 1, y)], fill=GROUT, width=1)
    if blur:
        im = im.filter(ImageFilter.GaussianBlur(blur))
    return im


def build_table() -> Image.Image:
    src = Image.open(SRC).convert("RGB")
    w, h = src.size
    assert (w, h) == (1440, 840), f"unexpected table.png size {w}x{h}"
    out = src.copy()
    floor = floor_tiles(w, h, origin=(0, 0), blur=1.0)
    fpx, opx = floor.load(), out.load()

    x0, y0, x1, y1 = DESK

    def signed_dist(x: int, y: int) -> int:
        """+ve inside the desk rect, -ve outside, 0 at the rim."""
        if x0 <= x < x1 and y0 <= y < y1:
            return min(x - x0, x1 - 1 - x, y - y0, y1 - 1 - y)
        dx = max(x0 - x, 0, x - (x1 - 1))
        dy = max(y0 - y, 0, y - (y1 - 1))
        return -max(dx, dy)

    for y in range(h):
        for x in range(w):
            d = signed_dist(x, y)
            if d >= FEATHER:
                continue                          # deep wood: untouched
            if d <= -FEATHER:
                opx[x, y] = fpx[x, y]             # ring: floor, every pixel
                continue
            t = (d + FEATHER) / (2 * FEATHER)     # 0 = pure floor, 1 = pure wood
            r, g, b = opx[x, y]
            fr, fg, fb = fpx[x, y]
            opx[x, y] = (int(r * t + fr * (1 - t)),
                         int(g * t + fg * (1 - t)),
                         int(b * t + fb * (1 - t)))
    return out


def verify_table(out: Image.Image, src: Image.Image) -> None:
    w, h = out.size
    x0, y0, x1, y1 = DESK
    opx, spx = out.load(), src.load()
    dark = 0
    lo, hi, tot, n = 255, 0, 0, 0
    worst_desk = 0
    for y in range(h):
        for x in range(w):
            r, g, b = opx[x, y]
            if x0 <= x < x1 and y0 <= y < y1:
                edge = min(x - x0, x1 - 1 - x, y - y0, y1 - 1 - y)
                if edge >= FEATHER and (r, g, b) != spx[x, y]:
                    worst_desk += 1
                continue
            v = (r + g + b) // 3
            tot += v
            n += 1
            lo = min(lo, v)
            hi = max(hi, v)
            if r + g + b < 90:
                dark += 1
    print(f"  ring: {n} px  brightness min {lo} mean {tot/n:.1f} max {hi}")
    print(f"  ring near-black (sum<90): {dark}")
    print(f"  desk interior pixels altered: {worst_desk}")
    assert dark == 0, "ring still contains near-black pixels"
    assert worst_desk == 0, "desk interior was modified"
    avg = sum(opx[x, y][0] for y in range(0, h, 16) for x in range(0, w, 16)) / ((h // 16 + 1) * (w // 16 + 1))
    print(f"  full-frame mean should be >= 3 (not a black void): {avg:.1f}")


def main() -> int:
    print(f"building {DST_TABLE.name} ...")
    src = Image.open(SRC).convert("RGB")
    out = build_table()
    verify_table(out, src)
    out.save(DST_TABLE)
    out.reduce(4).save("/tmp/pf_floor_preview.png")

    print(f"building {DST_BG.name} ...")
    # table sprite top-left sits at (-80,-60) in the 1280x720 viewport, so align
    # the bg tile grid to y % TILE == 20 (x already aligns: 80 % 40 == 0)
    bg = floor_tiles(1280, 720, origin=(0, 20), blur=1.2)
    bgp = bg.load()
    dark = sum(1 for y in range(720) for x in range(1280)
               if sum(bgp[x, y]) < 90)
    print(f"  bg near-black px: {dark}")
    assert dark == 0
    bg.save(DST_BG)
    print("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
