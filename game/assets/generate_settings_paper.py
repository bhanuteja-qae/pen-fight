#!/usr/bin/env python3
"""Generate the settings sheet's paper texture (settings_paper.png).

The sheet is a page of ruled binder paper on the classroom desk. Everything
static about the page lives here rather than in code because two of its features
need REAL alpha, which CanvasItem drawing cannot do (drawing can only add):

  * the punch holes are CUT-OUTS - alpha 0, so the scrimmed game shows through
    them exactly like the mockup (assets/design/mockups/settings.html, rendered
    as mock-settings.png). Drawn opaque they read as bullet points next to the
    rows instead of binder holes;
  * the ruled lines and the margin rule carry partial alpha so they composite
    over the paper the way the design's SVG does.

Geometry is the mockup's own card coordinate space, shifted so the page's
top-left is (0,0): the mockup centres its 536x428 card on (800,430) and draws
everything around that origin. Values in brackets are the mockup's coordinates.

  page        536 x 482   (mockup 536 x 428 + one ruled row: a hot-seat game
                           needs a pen row per player, not one "My pen" row)
  ruled lines (x -244..244 -> 24..512) first at y 64, pitch 27, 16 lines
  margin rule (x -196 -> 72)  #d9707f, alpha 0.7
  punch holes (x -238 -> 30)  y 94 / 241 / 388, r 9, alpha 0, lit rim outside

Run: .asset-venv/bin/python game/assets/generate_settings_paper.py
"""
from __future__ import annotations

import hashlib
import os

from PIL import Image, ImageDraw

OUT = os.path.dirname(os.path.abspath(__file__))

W, H = 536, 482
RADIUS = 4
PAPER = (244, 239, 226, 255)          # #f4efe2
RULE = (169, 189, 212, 255)           # #a9bdd4
MARGIN = (217, 112, 127, 179)         # #d9707f at 0.7
HOLE_X = 30
HOLE_YS = (94, 241, 388)
HOLE_R = 9
RULE_X0, RULE_X1 = 24, 512
RULE_Y0, RULE_PITCH, RULE_COUNT = 64, 27, 16
MARGIN_X = 72


def main() -> None:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # page (rounded rect; the radius is small enough that per-pixel masking is
    # unnecessary - draw the body then knock the corners back out)
    d.rounded_rectangle([0, 0, W - 1, H - 1], radius=RADIUS, fill=PAPER)

    # ruled lines + margin rule
    for i in range(RULE_COUNT):
        y = RULE_Y0 + RULE_PITCH * i
        if y >= H:
            break
        d.line([(RULE_X0, y), (RULE_X1, y)], fill=RULE, width=1)
    d.line([(MARGIN_X, 0), (MARGIN_X, H - 1)], fill=MARGIN, width=1)

    # punch holes: erase to alpha 0, then a lit cut edge around each
    for cy in HOLE_YS:
        d.ellipse([HOLE_X - HOLE_R, cy - HOLE_R, HOLE_X + HOLE_R, cy + HOLE_R],
                  fill=(0, 0, 0, 0))
    px = img.load()
    for cy in HOLE_YS:
        for y in range(cy - HOLE_R - 3, cy + HOLE_R + 4):
            for x in range(HOLE_X - HOLE_R - 3, HOLE_X + HOLE_R + 4):
                if not (0 <= x < W and 0 <= y < H):
                    continue
                dist = ((x - HOLE_X) ** 2 + (y - cy) ** 2) ** 0.5
                if HOLE_R < dist <= HOLE_R + 1.4:
                    base = px[x, y]
                    # warm lit edge of the cut paper, keeping the pixel's alpha
                    px[x, y] = (246, 242, 232, max(base[3], 150))

    path = os.path.join(OUT, "settings_paper.png")
    img.save(path)
    with open(path, "rb") as fh:
        data = fh.read()
    print(f"settings_paper.png {os.path.getsize(path)} B  size {W}x{H}  "
          f"md5 {hashlib.md5(data).hexdigest()}")
    # report the cut-outs, since they are the reason this is a texture
    holes = sum(1 for y in range(H) for x in range(W) if px[x, y][3] == 0)
    print(f"transparent punch-hole pixels: {holes} (expected ~3 * pi * {HOLE_R}^2 = {int(3 * 3.14159 * HOLE_R ** 2)})")


if __name__ == "__main__":
    main()
