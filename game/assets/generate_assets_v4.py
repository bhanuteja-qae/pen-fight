#!/usr/bin/env python3
"""Generate v4 detailed pen sprites for pen-fight (Phase 1c visual pass).

Models a REAL ballpoint pen seen from directly above (pens.com anatomy:
barrel, ink cartridge, nose cone, clip). v4 addresses the v3 art critique
from the vision loop:

  v3 flaws -> v4 fix
  ---------   --------
  flat red rectangle body -> strong cylindrical gradient (bright top edge,
                              dark bottom edge) + curved specular band
  clip = glued-on gray brick -> real clip: dark cap + mount band + curved
                              metal arm with gap, underside shadow, highlight
  blocky trapezoid cone -> smooth multi-point taper with metal gradient +
                              bright base ring + dark ball tip
  sticker-like ink line -> translucent tube with rounded ends, inner ink
                              glow, occlusion above it
  flat groove grip -> ribbed section with edge fade (wraps the cylinder)
  white sticker brand band -> subtle translucent band, no fake text
  no cap contrast -> dark cap (real pens: cap is darker plastic, barrel
                              shows the ink color)

Rendered at 4x supersample -> Lanczos down (smooth AA, no bricky pixels).

Run: .asset-venv/bin/python game/assets/generate_assets_v4.py
"""
import os
import random

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)))

SS = 4
W, H = 288, 56
SW, SH = W * SS, H * SS


def _canvas() -> Image.Image:
    return Image.new("RGBA", (SW, SH), (0, 0, 0, 0))


def _bleed(img: Image.Image) -> Image.Image:
    return img.resize((W, H), Image.LANCZOS)


def _hgrad(w: int, h: int, c0, c1) -> Image.Image:
    """Horizontal gradient RGBA."""
    g = Image.new("RGBA", (w, h))
    px = g.load()
    for x in range(w):
        t = x / max(w - 1, 1)
        px[x, 0] = (int(c0[0] + (c1[0] - c0[0]) * t),
                    int(c0[1] + (c1[1] - c0[1]) * t),
                    int(c0[2] + (c1[2] - c0[2]) * t),
                    int(c0[3] + (c1[3] - c0[3]) * t))
        for y in range(1, h):
            px[x, y] = px[x, 0]
    return g


def _vgrad(w: int, h: int, stops) -> Image.Image:
    """Vertical multi-stop gradient. stops = [(t, (r,g,b,a)), ...] t in [0,1]."""
    g = Image.new("RGBA", (w, h))
    px = g.load()
    def color_at(t):
        for i in range(len(stops) - 1):
            t0, c0 = stops[i]
            t1, c1 = stops[i + 1]
            if t0 <= t <= t1:
                k = (t - t0) / max(t1 - t0, 1e-6)
                return tuple(int(c0[j] + (c1[j] - c0[j]) * k) for j in range(4))
        return stops[-1][1]
    for y in range(h):
        t = y / max(h - 1, 1)
        c = color_at(t)
        for x in range(w):
            px[x, y] = c
    return g


def _paste(img: Image.Image, layer: Image.Image, x: int, y: int) -> None:
    img.alpha_composite(layer, (x, y))


def _blur(img: Image.Image, r: float) -> Image.Image:
    return img.filter(ImageFilter.GaussianBlur(r * SS))


def pen_sprite(hex_color: str, name: str, ink: str, cap: str = "26282e",
               seed: int = 0) -> None:
    rnd = random.Random(seed)
    img = _canvas()
    d = ImageDraw.Draw(img)

    base = tuple(int(hex_color[i:i + 2], 16) for i in (0, 2, 4))
    ink_c = tuple(int(ink[i:i + 2], 16) for i in (0, 2, 4))
    cap_c = tuple(int(cap[i:i + 2], 16) for i in (0, 2, 4))

    cy = SH // 2
    body_h = 32 * SS
    top = cy - body_h // 2
    bot = cy + body_h // 2

    # ---- CAP (left): dark plastic, slightly taller, rounded --------------------
    cap_x0, cap_x1 = 24 * SS, 66 * SS
    cap_grad = _vgrad(SW, SH, [
        (0.0, tuple(min(255, c + 34) for c in cap_c) + (255,)),
        (0.5, tuple(c for c in cap_c) + (255,)),
        (1.0, tuple(max(0, c - 58) for c in cap_c) + (255,)),
    ])
    cap_img = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    ImageDraw.Draw(cap_img).rounded_rectangle(
        [cap_x0, top - 2 * SS, cap_x1, bot + 2 * SS],
        radius=(bot + 2 * SS - top) // 2, fill=(255, 255, 255, 255))
    cap_l = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    cap_l.paste(cap_grad, (0, 0), mask=cap_img.split()[3])
    _paste(img, cap_l, 0, 0)

    # cap/barrel seam ring (molded)
    d.rounded_rectangle([cap_x1 - 3 * SS, top - 1 * SS, cap_x1 + 1 * SS, bot + 1 * SS],
                        radius=2 * SS, fill=tuple(max(0, c - 40) for c in cap_c) + (255,))
    d.rounded_rectangle([cap_x1 - 1 * SS, top - 1 * SS, cap_x1 + 2 * SS, bot + 1 * SS],
                        radius=1 * SS, fill=(255, 255, 255, 70))

    # ---- BARREL (main translucent colored body) --------------------------------
    bar_x0, bar_x1 = 62 * SS, 244 * SS
    # STRONG cylinder gradient: bright rim light at top edge -> color -> near
    # black bottom edge. Wide tonal range is what makes a cylinder read as
    # round instead of flat.
    bar_stops = [
        (0.00, tuple(min(255, c + 120) for c in base) + (255,)),
        (0.12, tuple(min(255, c + 64) for c in base) + (244,)),
        (0.45, tuple(min(255, c + 8) for c in base) + (235,)),
        (0.78, tuple(max(0, c - 66) for c in base) + (235,)),
        (0.94, tuple(max(0, c - 118) for c in base) + (250,)),
        (1.00, tuple(max(0, c - 148) for c in base) + (255,)),
    ]
    bar = _vgrad(SW, SH, bar_stops)
    bar_img = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    ImageDraw.Draw(bar_img).rounded_rectangle(
        [bar_x0, top, bar_x1, bot], radius=(bot - top) // 2, fill=(255, 255, 255, 255))
    bar_l = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    bar_l.paste(bar, (0, 0), mask=bar_img.split()[3])
    _paste(img, bar_l, 0, 0)

    # ambient occlusion: thin dark line hugging the very top edge above the
    # specular (the cylinder's contact with the cap/shadow)
    d.rectangle([bar_x0 + 2 * SS, top + 1 * SS, bar_x1 - 2 * SS, top + 2 * SS],
                fill=(0, 0, 0, 55))

    # ---- INK CARTRIDGE (glass tube through the translucent barrel) -------------
    tube_top = cy + 4 * SS
    tube_h = 17 * SS
    tube_x0, tube_x1 = bar_x0 + 8 * SS, bar_x1 - 8 * SS
    # glass tube: distinct dark outline + inner highlight + bottom shading, so
    # it reads as an OBJECT inside the barrel, not a painted stripe
    tube_img = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    td = ImageDraw.Draw(tube_img)
    td.rounded_rectangle([tube_x0, tube_top, tube_x1, tube_top + tube_h],
                         radius=tube_h // 2, fill=tuple(c for c in ink_c) + (225,))
    td.rectangle([tube_x0 + 4 * SS, tube_top + 2 * SS, tube_x1 - 4 * SS, tube_top + 5 * SS],
                 fill=tuple(min(255, c + 150) for c in ink_c) + (110,))  # liquid glint
    td.rectangle([tube_x0 + 4 * SS, tube_top + tube_h - 5 * SS, tube_x1 - 4 * SS, tube_top + tube_h - 2 * SS],
                 fill=(0, 0, 0, 80))                                       # ink shadow
    # glass edges: bright rim top, dark bottom
    td.rounded_rectangle([tube_x0, tube_top, tube_x1, tube_top + tube_h],
                         radius=tube_h // 2, outline=(255, 255, 255, 70), width=1 * SS)
    _paste(img, tube_img, 0, 0)

    # ---- CYLINDER SPECULAR: curved soft band near the top edge -----------------
    # A real cylinder highlight is bright at the center and fades at the ends.
    spec = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    sd = ImageDraw.Draw(spec)
    spec_y = top + 3 * SS
    # three stacked soft bands, center-heavy (fading at both ends via alpha)
    for i, (x0, x1, a) in enumerate([
            (bar_x0 + 26 * SS, bar_x1 - 26 * SS, 120),
            (bar_x0 + 10 * SS, bar_x1 - 10 * SS, 80),
            (bar_x0 + 2 * SS, bar_x1 - 2 * SS, 45)]):
        sd.rounded_rectangle([x0, spec_y + i * 3 * SS, x1, spec_y + i * 3 * SS + 4 * SS],
                             radius=2 * SS, fill=(255, 255, 255, a))
    _paste(img, _blur(spec, 2.0), 0, 0)
    # crisp thin top-edge rim light
    d.rectangle([bar_x0 + 2 * SS, top + 2 * SS, bar_x1 - 2 * SS, top + 3 * SS],
                fill=(255, 255, 255, 130))

    # ---- CLIP: dark mount + curved metal arm over the cap ----------------------
    # two-tone metal: bright top face over darker base, with cast shadow under
    # the arm so it reads as a bent bar floating over the cap, not a sticker
    arm = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    ad = ImageDraw.Draw(arm)
    arm_y = top - 10 * SS
    # base (dark) — the clip's thickness
    ad.rounded_rectangle([cap_x0 + 6 * SS, arm_y + 4 * SS, cap_x0 + 46 * SS, arm_y + 8 * SS],
                         radius=3 * SS, fill=(110, 114, 124, 255))
    # top face (bright metal)
    ad.rounded_rectangle([cap_x0 + 6 * SS, arm_y, cap_x0 + 46 * SS, arm_y + 5 * SS],
                         radius=2 * SS, fill=(186, 190, 200, 255))
    # specular streak along the top face
    ad.rounded_rectangle([cap_x0 + 9 * SS, arm_y + 1 * SS, cap_x0 + 42 * SS, arm_y + 3 * SS],
                         radius=1 * SS, fill=(240, 243, 250, 220))
    # hook tip: rounded and slightly wider, catches light
    ad.ellipse([cap_x0 + 41 * SS, arm_y - 2 * SS, cap_x0 + 50 * SS, arm_y + 9 * SS],
               fill=(172, 176, 186, 255))
    ad.ellipse([cap_x0 + 42 * SS, arm_y - 1 * SS, cap_x0 + 47 * SS, arm_y + 4 * SS],
               fill=(235, 238, 246, 220))
    _paste(img, arm, 0, 0)
    # cast shadow under the whole arm, onto the cap
    clip_shadow = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    ImageDraw.Draw(clip_shadow).rounded_rectangle(
        [cap_x0 + 8 * SS, top - 2 * SS, cap_x0 + 46 * SS, top + 5 * SS],
        radius=4 * SS, fill=(0, 0, 0, 110))
    _paste(img, _blur(clip_shadow, 2.0), 0, 0)
    # clip mount band on the cap (visible below the arm) — a separate silver
    # piece, so the clip reads as ATTACHED (vision critique v4: "clip lacks a
    # visible attachment point")
    d.rectangle([cap_x0 + 6 * SS, top - 3 * SS, cap_x0 + 13 * SS, bot + 3 * SS],
                fill=(96, 100, 110, 255))
    d.rounded_rectangle([cap_x0 + 6 * SS, top - 3 * SS, cap_x0 + 13 * SS, top + 2 * SS],
                        radius=2 * SS, fill=(186, 190, 200, 255))
    d.rounded_rectangle([cap_x0 + 6 * SS, top + 4 * SS, cap_x0 + 13 * SS, bot + 3 * SS],
                        radius=2 * SS, fill=(70, 73, 82, 255))

    # ---- GRIP: ribbed darker section before the cone ---------------------------
    grip_x0, grip_x1 = 244 * SS, 260 * SS
    grip = _vgrad(SW, SH, [
        (0.0, tuple(min(255, c + 30) for c in base) + (255,)),
        (0.5, tuple(c for c in base) + (255,)),
        (1.0, tuple(max(0, c - 66) for c in base) + (255,)),
    ])
    grip_img = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    ImageDraw.Draw(grip_img).rounded_rectangle(
        [grip_x0, top + 2 * SS, grip_x1, bot - 2 * SS],
        radius=(bot - top - 4 * SS) // 2, fill=(255, 255, 255, 255))
    grip_l = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    grip_l.paste(grip, (0, 0), mask=grip_img.split()[3])
    _paste(img, grip_l, 0, 0)
    # ridges that fade at the cylinder edges
    rr = max(SS, 1)
    rx = grip_x0 + 2 * SS
    while rx < grip_x1 - 2 * SS:
        ridge = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
        ImageDraw.Draw(ridge).rectangle(
            [rx, top + 4 * SS, rx + rr - 1, bot - 4 * SS], fill=(255, 255, 255, 70))
        _paste(img, ridge, 0, 0)
        # dark groove next to each ridge for depth
        groove = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
        ImageDraw.Draw(groove).rectangle(
            [rx + rr - 1, top + 4 * SS, rx + rr, bot - 4 * SS], fill=(0, 0, 0, 60))
        _paste(img, groove, 0, 0)
        rx += 3 * SS

    # ---- NOSE CONE: smooth metal taper + bright base ring + dark ball ----------
    cone_x0, cone_x1 = 260 * SS, 284 * SS
    cone = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    cd = ImageDraw.Draw(cone)
    # draw as stacked horizontal slices -> smooth curved taper
    steps = 40
    for i in range(steps):
        t = i / (steps - 1)  # 0 at base, 1 at tip
        y0 = top + 6 * SS + (bot - 6 * SS - (top + 6 * SS)) * t
        half = (bot - 6 * SS - (top + 6 * SS)) * 0.5 * (1.0 - 0.82 * t)
        # metal gradient: bright at base, darker toward the tip, plus top lit
        lum = 176 - int(70 * t)
        cd.rectangle([cone_x0 + t * 2 * SS, y0 - half, cone_x0 + cone_x1 - cone_x0 - t * 7 * SS, y0 + half],
                     fill=(lum, lum + 5, lum + 12, 255))
    # bright base ring where cone meets grip
    d.rounded_rectangle([cone_x0 - 2 * SS, top + 4 * SS, cone_x0 + 1 * SS, bot - 4 * SS],
                        radius=1 * SS, fill=(232, 236, 244, 220))
    # cone top highlight
    cone_hl = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    ImageDraw.Draw(cone_hl).rounded_rectangle(
        [cone_x0 + 3 * SS, top + 7 * SS, cone_x1 - 8 * SS, top + 11 * SS],
        radius=2 * SS, fill=(255, 255, 255, 110))
    _paste(img, _blur(cone_hl, 1.2), 0, 0)
    _paste(img, cone, 0, 0)
    # dark ball tip
    d.ellipse([cone_x1 - 3 * SS, cy - 4 * SS, cone_x1 + 3 * SS, cy + 4 * SS],
              fill=(24, 24, 28, 255))
    d.ellipse([cone_x1 - 2 * SS, cy - 3 * SS, cone_x1, cy - 1 * SS],
              fill=(120, 124, 130, 200))

    # ---- subtle brand band (translucent dark, no fake text) --------------------
    band = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    ImageDraw.Draw(band).rounded_rectangle(
        [110 * SS, top + 5 * SS, 154 * SS, bot - 5 * SS],
        radius=4 * SS, fill=(0, 0, 0, 34))
    ImageDraw.Draw(band).rounded_rectangle(
        [116 * SS, top + 9 * SS, 148 * SS, top + 13 * SS],
        radius=2 * SS, fill=(255, 255, 255, 46))
    ImageDraw.Draw(band).rounded_rectangle(
        [116 * SS, bot - 13 * SS, 148 * SS, bot - 9 * SS],
        radius=2 * SS, fill=(255, 255, 255, 30))
    _paste(img, band, 0, 0)

    # specular micro-sparkles along the top edge (procedural)
    for _ in range(5):
        sx = rnd.randint(80, 220) * SS
        sy = rnd.randint(top + 3 * SS, top + 7 * SS)
        r = rnd.randint(2, 3) * SS
        sp = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
        ImageDraw.Draw(sp).ellipse([sx, sy, sx + r, sy + r], fill=(255, 255, 255, 60))
        _paste(img, _blur(sp, 0.8), 0, 0)

    img = _bleed(img)
    img.save(os.path.join(OUT, name))


def shadow_sprite(name: str = "pen_shadow_v4.png") -> None:
    """Soft directional shadow under every pen (offset in the scene)."""
    sh = Image.new("RGBA", (W, H + 24), (0, 0, 0, 0))
    d = ImageDraw.Draw(sh)
    d.ellipse([6, 8, W - 10, H + 12], fill=(0, 0, 0, 130))
    sh = sh.filter(ImageFilter.GaussianBlur(7))
    px = sh.load()
    for y in range(sh.height):
        for x in range(sh.width):
            r, g, b, a = px[x, y]
            if a:
                fade = min(1.0, (y / sh.height) * 0.9 + (x / sh.width) * 0.35)
                px[x, y] = (r, g, b, int(a * (0.12 + 0.88 * fade)))
    sh.save(os.path.join(OUT, name))


if __name__ == "__main__":
    import hashlib

    pen_sprite("d84343", "pen_red_v4.png", ink="5f0f0f", cap="2c2e34", seed=11)
    pen_sprite("3d6fd8", "pen_blue_v4.png", ink="0d2a66", cap="24262c", seed=23)
    pen_sprite("3fae5a", "pen_green_v4.png", ink="0e5222", cap="2a2c32", seed=37)
    shadow_sprite()
    for f in ("pen_red_v4.png", "pen_blue_v4.png", "pen_green_v4.png", "pen_shadow_v4.png"):
        p = os.path.join(OUT, f)
        with open(p, "rb") as fh:
            data = fh.read()
        print(f, os.path.getsize(p), hashlib.md5(data).hexdigest())