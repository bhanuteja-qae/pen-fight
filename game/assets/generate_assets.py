#!/usr/bin/env python3
"""Generate Phase 0.5 placeholder assets for pen-fight.

Produces (idempotent):
  pen_red.png   - flat red   capsule sprite, 40x8 px, rounded ends
  pen_blue.png  - flat blue  capsule sprite, 40x8 px, rounded ends
  table.png     - dark wood-ish table texture, 1024x512, subtle noise

Requires Pillow. Regenerate any time with: python3 game/assets/generate_assets.py
"""
import hashlib
import math
import os
import random

from PIL import Image, ImageDraw

OUT = os.path.dirname(os.path.abspath(__file__))


def capsule(w: int, h: int, color, name: str) -> None:
    """Horizontal capsule: rounded rect with radius == half height."""
    r = h // 2
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=r, fill=color)
    rim = tuple(max(0, c - 70) for c in color)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=r, outline=rim, width=1)
    sheen = tuple(min(255, c + 60) for c in color)
    d.rounded_rectangle([r, 1, w - r - 1, h // 2], radius=1, fill=sheen)
    img.save(os.path.join(OUT, name))


def table(w: int, h: int, name: str) -> None:
    base = (74, 66, 58)  # dark brownish gray
    n = Image.effect_noise((w, h), 18).convert("L")

    def sh(g: int, b: int, spread: float = 0.32) -> int:
        return max(0, min(255, int(round(b * (0.9 + (g - 128) / 128.0 * spread)))))

    chans = [Image.eval(n, lambda g, b=b: sh(g, b)) for b in base]
    img = Image.merge("RGB", chans)
    d = ImageDraw.Draw(img, "RGBA")
    rnd = random.Random(7)
    for _ in range(70):  # faint wood-grain streaks
        y = rnd.randrange(0, h)
        basex = rnd.uniform(0, 6.28)
        streak = (38, 34, 30, rnd.randint(12, 28))
        pts = [(x, y + int(2.5 * math.sin(x / 120.0 + basex))) for x in range(0, w, 8)]
        d.line(pts, fill=streak, width=1)
    d.rectangle([0, 0, w - 1, h - 1], outline=(42, 38, 34), width=4)  # edge ring
    img.convert("RGB").save(os.path.join(OUT, name))


if __name__ == "__main__":
    capsule(40, 8, (222, 62, 62), "pen_red.png")
    capsule(40, 8, (62, 92, 222), "pen_blue.png")
    table(1024, 512, "table.png")
    for f in ("pen_red.png", "pen_blue.png", "table.png"):
        p = os.path.join(OUT, f)
        with open(p, "rb") as fh:
            data = fh.read()
        print(f, os.path.getsize(p), hashlib.md5(data).hexdigest())
