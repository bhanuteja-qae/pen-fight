#!/usr/bin/env python3
"""Generate the four realistic pen skins for pen-fight, at the game's true scale.

WHY THIS EXISTS (supersedes the pen art in generate_assets_v4.py):
v4 drew beautiful anatomy at the WRONG size. At the scene's old 0.408 sprite
scale its 288x56 sprite drew a 109x21 pen, while the physics capsule
(PenBody: half_len 85, radius 5) is a 180x10 stadium, i.e. 18:1. Every design is
authored here at ONE footprint so that at PEN_SPRITE_SCALE (1/3) it draws
EXACTLY 180 x 10 px - a real pen scaled into the game, sitting on its capsule:

  texture content 540x30  x  scale 1/3  =  180x10 on screen  ==  the capsule

The content is bbox-fitted (cropped to the drawn alpha, then resized to 540x30),
so the sprite's opaque extent equals the capsule rather than falling short of it
(an earlier pass drew 173x10 because the art only filled 518 of 540 columns).

ANATOMY (top-down; cap + clip left, writing tip right; 18:1 overall). All
coordinates are TEXTURE px (x 0..540, y 0..30), rendered at 4x supersample and
Lanczos-downsampled:

  cap (rounded push-button end)   x  44..126   y 2..28
  clip arm (wraps over the side)  x  34..200   y 0..4 + hook curling down
  clip mount band                 x  22..36
  barrel (translucent / matte)    x 126..486   y 3..27   (24 px = 8 screen px)
  ink tube (translucent designs)  x 138..476   y 9..21
  brand band (subtle)             x 170..232
  grip (ribbed)                   x 486..504
  nose cone (metal, long taper)   x 504..538   24 -> 6
  ball tip                        x 538..544

REALISM RULES (each one fixes a measured defect, do not undo them):
  * The cylinder shade is an ANALYTIC function of cross-section position, not a
    handful of colour stops: with stops, every stop boundary showed up as a band
    at 1:1 (the vision pass called it "heavy gradient banding along the barrel").
  * No crisp 1 px "rim light" rectangles - they band at 3x. Edge light is part
    of the analytic curve.
  * A 1 px darker silhouette outline keeps the pen legible on both dark and pale
    desk wood (graphite vanished into the wood, ivory dissolved into it).
  * The clip must WRAP: arm along the top edge plus a hook that curls down the
    far side, or it reads as "a flat pale tab" glued on.
  * The cone starts at the barrel's full thickness and is long (52 px): a short
    cone on a thick barrel reads as a different object stuck on the end.

Run: .asset-venv/bin/python game/assets/generate_pens_real.py
"""
from __future__ import annotations

import hashlib
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.dirname(os.path.abspath(__file__))

SS = 4
CONTENT_W, CONTENT_H = 540, 30
CANVAS_W, CANVAS_H = 600, 100
SW, SH = CONTENT_W * SS, CONTENT_H * SS
OX, OY = (CANVAS_W - CONTENT_W) // 2, (CANVAS_H - CONTENT_H) // 2

CAP_X0, CAP_X1 = 44, 126
BAR_X0, BAR_X1 = 126, 486
BAR_TOP, BAR_BOT = 3, 27
GRIP_X0, GRIP_X1 = 486, 504
CONE_X0, CONE_X1 = 504, 538
TIP_X0, TIP_X1 = 538, 544
CLIP_X0, CLIP_X1 = 34, 200
MOUNT_X0, MOUNT_X1 = 22, 36
BAND_X0, BAND_X1 = 170, 232
TUBE_X0, TUBE_X1 = 138, 476

DESIGNS = [
    dict(name="amber", seed=11,
         base=(208, 128, 46), ink=(138, 54, 16), cap=(56, 59, 68),
         metal=(198, 202, 212), metal_dark=(116, 120, 130),
         translucent=True, gloss=1.0, matte=False, cap_is_body=False),
    dict(name="cobalt", seed=23,
         base=(62, 100, 210), ink=(22, 42, 140), cap=(34, 56, 132),
         metal=(198, 202, 212), metal_dark=(116, 120, 130),
         translucent=True, gloss=1.0, matte=False, cap_is_body=True),
    dict(name="graphite", seed=37,
         base=(84, 87, 95), ink=(84, 87, 95), cap=(52, 54, 60),
         metal=(150, 155, 166), metal_dark=(88, 92, 100),
         translucent=False, gloss=0.5, matte=True, cap_is_body=True),
    dict(name="ivory", seed=53,
         base=(206, 199, 183), ink=(206, 199, 183), cap=(150, 143, 128),
         metal=(206, 174, 100), metal_dark=(132, 108, 56),
         translucent=False, gloss=0.85, matte=False, cap_is_body=True),
]


# ---- shading ---------------------------------------------------------------
def shade(t: float, base, gloss: float, matte: bool) -> tuple[int, int, int]:
    """Analytic cylinder cross-section shade. t = 0 top edge .. 1 bottom edge.

    One continuous function -> no stop-boundary banding at 1:1.
    """
    m = 1.0
    m += 0.30 * math.exp(-((t - 0.05) ** 2) / (2 * 0.045 ** 2))          # top edge light
    m += (0.30 if matte else 0.62) * gloss * math.exp(-((t - 0.20) ** 2) / (2 * 0.11 ** 2))
    if t > 0.22:                                                        # falloff
        m -= (0.42 if matte else 0.55) * ((t - 0.22) / 0.78) ** 1.2
    if t > 0.86:                                                        # bottom AO
        m -= 0.15 * ((t - 0.86) / 0.14)
    return tuple(int(max(0, min(255, c * m))) for c in base)


def shade_column(base, gloss: float, matte: bool) -> list[tuple[int, int, int]]:
    return [shade(y / (SH - 1), base, gloss, matte) for y in range(SH)]


def _vgrad_from_rows(rows) -> Image.Image:
    g = Image.new("RGBA", (SW, SH))
    px = g.load()
    for y, c in enumerate(rows):
        for x in range(SW):
            px[x, y] = c + (255,)
    return g


def _mask(x0, y0, x1, y1, radius) -> Image.Image:
    m = Image.new("L", (SW, SH), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        [x0 * SS, y0 * SS, x1 * SS, y1 * SS], radius=int(radius * SS), fill=255)
    return m


def _blur(img, r):
    return img.filter(ImageFilter.GaussianBlur(r * SS))


def _metal_rows(metal, metal_dark, gloss: float):
    """Brushed metal: smooth band with a soft dark lower third."""
    rows = []
    for y in range(SH):
        t = y / (SH - 1)
        k = 0.55 + 0.75 * math.exp(-((t - 0.24) ** 2) / (2 * 0.16 ** 2)) - 0.45 * max(0.0, t - 0.55)
        rows.append(tuple(int(max(0, min(255, metal[i] * k + metal_dark[i] * (1 - k) * 0.35)))
                          for i in range(3)))
    return rows


def make_pen(d: dict) -> None:
    rnd = random.Random(d["seed"])
    img = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    dd = ImageDraw.Draw(img)
    base, ink, cap = d["base"], d["ink"], d["cap"]
    metal, metal_dark, gloss = d["metal"], d["metal_dark"], d["gloss"]

    # ---------- CAP: rounded push-button end, same shade curve as the barrel ----
    cap_grad = _vgrad_from_rows(shade_column(cap, gloss * 1.25, d["matte"]))
    layer = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    layer.paste(cap_grad, (0, 0), _mask(CAP_X0, 2, CAP_X1, 28, 13))
    img.alpha_composite(layer)
    # end-cap ring: reads as the push-button rim of a real pen cap
    ring = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring)
    rd.rounded_rectangle([(CAP_X0 + 6) * SS, 3.2 * SS, (CAP_X0 + 8.2) * SS, 26.8 * SS],
                         radius=SS, fill=(0, 0, 0, 60))
    rd.rounded_rectangle([(CAP_X0 + 8.2) * SS, 3.6 * SS, (CAP_X0 + 9.6) * SS, 26.4 * SS],
                         radius=SS, fill=(255, 255, 255, 52))
    img.alpha_composite(_blur(ring, 0.4))

    # ---------- BARREL ---------------------------------------------------------
    bar_grad = _vgrad_from_rows(shade_column(base, gloss, d["matte"]))
    layer = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    layer.paste(bar_grad, (0, 0), _mask(BAR_X0, BAR_TOP, BAR_X1, BAR_BOT, 12))
    img.alpha_composite(layer)

    # cap/barrel seam: a soft collar so the two sections read as ONE pen
    seam = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    sd = ImageDraw.Draw(seam)
    sd.rounded_rectangle([(BAR_X0 - 3) * SS, 3.4 * SS, (BAR_X0 + 2) * SS, 26.6 * SS],
                         radius=1.4 * SS, fill=(0, 0, 0, 74))
    sd.rounded_rectangle([(BAR_X0 + 2) * SS, 3.8 * SS, (BAR_X0 + 4) * SS, 26.2 * SS],
                         radius=SS, fill=(255, 255, 255, 46))
    img.alpha_composite(_blur(seam, 0.6))

    if d["translucent"]:
        # ink cartridge behind the translucent barrel: an object, not a stripe
        tube = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
        td = ImageDraw.Draw(tube)
        td.rounded_rectangle([TUBE_X0 * SS, 10 * SS, TUBE_X1 * SS, 20 * SS],
                             radius=5 * SS, fill=ink + (150,))
        td.rectangle([(TUBE_X0 + 5) * SS, 11.4 * SS, (TUBE_X1 - 5) * SS, 13.0 * SS],
                     fill=tuple(min(255, c + 130) for c in ink) + (70,))
        td.rectangle([(TUBE_X0 + 5) * SS, 17.6 * SS, (TUBE_X1 - 5) * SS, 19.0 * SS],
                     fill=(0, 0, 0, 46))
        # ink body deepens toward the writing end, so it is not a flat bar
        for i in range(60):
            t = i / 59
            x0 = TUBE_X0 + (TUBE_X1 - TUBE_X0) * t
            td.rectangle([x0 * SS, 10 * SS, (x0 + (TUBE_X1 - TUBE_X0) / 60 + 1) * SS, 20 * SS],
                         fill=(0, 0, 0, int(22 + 40 * t)))
        img.alpha_composite(_blur(tube, 0.7))
    elif d["matte"]:
        for fy in (9.6, 20.4):
            dd.rectangle([(BAR_X0 + 2) * SS, fy * SS, (BAR_X1 - 2) * SS, fy * SS + SS],
                         fill=(0, 0, 0, 24))
            dd.rectangle([(BAR_X0 + 2) * SS, (fy - 0.8) * SS, (BAR_X1 - 2) * SS, fy * SS],
                         fill=(255, 255, 255, 20))

    # ---------- ONE continuous lengthwise gloss band (fades at both ends) ------
    if gloss > 0.5:
        spec = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
        sdw = ImageDraw.Draw(spec)
        sy = (BAR_TOP + 3.2) * SS
        steps = 150
        for i in range(steps):
            t = i / (steps - 1)
            x = BAR_X0 + 3 + (BAR_X1 - BAR_X0 - 6) * t
            fade = math.sin(math.pi * min(1.0, max(0.0, (t - 0.05) / 0.9))) ** 0.55
            a = int(132 * fade * gloss)
            if a <= 0:
                continue
            wpx = (BAR_X1 - BAR_X0 - 6) / steps + 1.2
            sdw.rectangle([x * SS, sy, (x + wpx) * SS, sy + 2.2 * SS], fill=(255, 255, 255, a))
        img.alpha_composite(_blur(spec, 1.3))

    # ---------- subtle brand band ---------------------------------------------
    band = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    ImageDraw.Draw(band).rounded_rectangle(
        [BAND_X0 * SS, (BAR_TOP + 3) * SS, BAND_X1 * SS, (BAR_BOT - 3) * SS],
        radius=3 * SS, fill=(0, 0, 0, 26))
    ImageDraw.Draw(band).rounded_rectangle(
        [(BAND_X0 + 6) * SS, (BAR_TOP + 6) * SS, (BAND_X1 - 6) * SS, (BAR_TOP + 7.2) * SS],
        radius=0.6 * SS, fill=(255, 255, 255, 36))
    img.alpha_composite(band)

    # ---------- CLIP: arm + hook that WRAPS down the far side -----------------
    arm = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    rd = ImageDraw.Draw(arm)
    rd.rounded_rectangle([CLIP_X0 * SS, 2.8 * SS, CLIP_X1 * SS, 5.8 * SS],
                         radius=1.5 * SS, fill=metal_dark + (255,))
    rd.rounded_rectangle([CLIP_X0 * SS, 0 * SS, CLIP_X1 * SS, 3.1 * SS],
                         radius=1.4 * SS, fill=metal + (255,))
    rd.rounded_rectangle([(CLIP_X0 + 4) * SS, 0.5 * SS, (CLIP_X1 - 6) * SS, 1.5 * SS],
                         radius=0.6 * SS, fill=tuple(min(255, c + 40) for c in metal) + (230,))
    # hook: curls over the edge and down the near side
    rd.ellipse([(CLIP_X1 - 9) * SS, 0.0 * SS, (CLIP_X1 + 1) * SS, 6.4 * SS], fill=metal + (255,))
    rd.ellipse([(CLIP_X1 - 9) * SS, 5.6 * SS, (CLIP_X1 - 2) * SS, 12.6 * SS],
               fill=tuple(int(c * 0.86) for c in metal) + (255,))
    rd.ellipse([(CLIP_X1 - 7) * SS, 1.0 * SS, (CLIP_X1 - 2) * SS, 3.6 * SS],
               fill=tuple(min(255, c + 45) for c in metal) + (205,))
    img.alpha_composite(arm)
    # cast shadow: the clip floats over the cap, so it must throw one
    cast = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    ImageDraw.Draw(cast).rounded_rectangle(
        [(CLIP_X0 + 2) * SS, 3.4 * SS, (CLIP_X1 + 2) * SS, 7.6 * SS],
        radius=2 * SS, fill=(0, 0, 0, 96))
    img.alpha_composite(_blur(cast, 1.1))
    # mount band (the clip is ATTACHED to something)
    mount = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    md = ImageDraw.Draw(mount)
    md.rounded_rectangle([MOUNT_X0 * SS, 1.4 * SS, MOUNT_X1 * SS, 28.6 * SS], radius=2.2 * SS,
                         fill=metal_dark + (255,))
    md.rounded_rectangle([MOUNT_X0 * SS, 1.4 * SS, (MOUNT_X0 + 6) * SS, 28.6 * SS], radius=2.2 * SS,
                         fill=metal + (255,))
    md.rectangle([(MOUNT_X0 + 6) * SS, 1.8 * SS, (MOUNT_X0 + 7.2) * SS, 28.2 * SS],
                 fill=tuple(min(255, c + 36) for c in metal) + (190,))
    img.alpha_composite(_blur(mount, 0.35))

    # ---------- GRIP: ribbed, wrapping the cylinder ---------------------------
    grip_grad = _vgrad_from_rows(shade_column(tuple(int(c * 0.82) for c in base),
                                             gloss * 0.8, d["matte"]))
    layer = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    layer.paste(grip_grad, (0, 0), _mask(GRIP_X0, 4, GRIP_X1, 26, 10))
    img.alpha_composite(layer)
    rx = GRIP_X0 + 2.4
    while rx < GRIP_X1 - 2.4:
        rib = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
        ImageDraw.Draw(rib).rectangle([rx * SS, 6 * SS, (rx + 1.1) * SS, 24 * SS],
                                      fill=(255, 255, 255, 54))
        ImageDraw.Draw(rib).rectangle([(rx + 1.1) * SS, 6 * SS, (rx + 2.0) * SS, 24 * SS],
                                      fill=(0, 0, 0, 50))
        img.alpha_composite(_blur(rib, 0.3))
        rx += 4.6

    # ---------- NOSE CONE: long metal taper from the barrel's full thickness ---
    cone = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    cd = ImageDraw.Draw(cone)
    metal_rows = _metal_rows(metal, metal_dark, gloss)
    steps = 200
    for i in range(steps):
        t = i / (steps - 1)
        x = CONE_X0 + (CONE_X1 - CONE_X0) * t
        half = 12.0 * (1.0 - 0.80 * t)
        y0 = int(15 - half) * SS
        y1 = int(15 + half) * SS
        for y in range(max(0, y0), min(SH, y1)):
            cd.rectangle([x * SS - SS, y, x * SS + SS, y + 1], fill=metal_rows[y] + (255,))
    img.alpha_composite(_blur(cone, 0.3))
    ring = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    ImageDraw.Draw(ring).rounded_rectangle([(CONE_X0 - 2.4) * SS, 4.6 * SS, (CONE_X0 + 0.6) * SS, 25.4 * SS],
                                           radius=SS, fill=tuple(min(255, c + 34) for c in metal) + (225,))
    img.alpha_composite(_blur(ring, 0.35))
    chl = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    ImageDraw.Draw(chl).rounded_rectangle([(CONE_X0 + 6) * SS, 7.2 * SS, (CONE_X1 - 12) * SS, 9.2 * SS],
                                          radius=SS, fill=(255, 255, 255, 105))
    img.alpha_composite(_blur(chl, 0.9))
    dd.ellipse([(TIP_X0 - 1) * SS, 12.2 * SS, (TIP_X1 + 1) * SS, 17.8 * SS], fill=(26, 26, 30, 255))
    dd.ellipse([(TIP_X0 + 1) * SS, 13.0 * SS, (TIP_X0 + 3) * SS, 14.6 * SS], fill=(138, 142, 150, 200))

    # ---------- final: bbox-fit -> 540x30, soft outline, canvas, shadow -------
    bbox = img.getchannel("A").getbbox()
    pen = img.crop(bbox).resize((CONTENT_W, CONTENT_H), Image.LANCZOS)

    # NOTE: no 1 px silhouette outline - a traced outline read as a "halo/glow"
    # in every design at 1:1. Contrast + the (now two-layer) shadow do the
    # separating instead.

    canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    canvas.alpha_composite(pen, ((CANVAS_W - CONTENT_W) // 2, (CANVAS_H - CONTENT_H) // 2))
    canvas.save(os.path.join(OUT, f"pen_{d['name']}.png"))

    # Two-layer shadow: a tight contact core plus a wide soft penumbra. A single
    # small blur on a 10 px-thick pen reads as a hard dark stripe (vision pass:
    # "blocky rectangle shadow" / "solid dark stripe"), not as contact with a
    # surface. The pen silhouette is reused for both layers.
    mask = canvas.getchannel("A")
    core = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    core.paste(Image.new("RGBA", canvas.size, (0, 0, 0, 150)), (0, 0), mask)
    core = core.filter(ImageFilter.GaussianBlur(4.0))
    penumbra = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    penumbra.paste(Image.new("RGBA", canvas.size, (0, 0, 0, 80)), (0, 0), mask)
    penumbra = penumbra.filter(ImageFilter.GaussianBlur(16.0))
    shadow = Image.alpha_composite(penumbra, core)
    shadow.save(os.path.join(OUT, f"pen_{d['name']}_shadow.png"))


def main() -> None:
    for d in DESIGNS:
        make_pen(d)
        for suffix in ("", "_shadow"):
            p = os.path.join(OUT, f"pen_{d['name']}{suffix}.png")
            with open(p, "rb") as fh:
                data = fh.read()
            print(f"pen_{d['name']}{suffix}.png  {os.path.getsize(p):7d} B  md5 {hashlib.md5(data).hexdigest()}")


if __name__ == "__main__":
    main()
