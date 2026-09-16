#!/usr/bin/env python3
"""Generate pen skins with NB2 (Google Gemini 3.1 Flash Image) for pen-fight.

WHY THIS EXISTS
    The shipped skins (game/assets/generate_pens_real.py) are drawn
    procedurally. This generator asks NB2 for the MATERIAL and the
    per-identity look, then normalises the result through the same proven
    pipeline: key the background to alpha -> crop to the drawn alpha bbox ->
    resize -> centre in a 600x100 canvas.

    The normalisation is what makes a generative image usable at all here.
    Measured: NB2 returns the pen band at ~6-13:1, and no vendor model emits
    the game's 18:1 footprint, so the code - not the model - is what puts the
    sprite on the physics capsule (PenBody half_len 85 + radius 5 = 180x10
    on screen at PEN_SPRITE_SCALE 1/3).

    Default authoring is the capsule-exact 540x30 (-> 180x10 on screen). The
    models set overrides that per design via MODEL_THICK: REAL pens and
    markers are fatter than 18:1, and ironing them onto the capsule made
    them read squeezed -- so each model is authored at its own thickness
    (the marker gets real width) and may overhang the capsule slightly.

    The pen reads left-to-right exactly like the procedural art: cap + clip
    at the LEFT, writing tip at the RIGHT. The prompt pins that, and the
    bbox-fit does the rest.

    Two design sets:
      * identities (default): the four colour identities, referenced against
        the shipped procedural sprites.
      * models (--set models): the four REAL pen models picked by the user
        (Bic Cristal / Parker Jotter / Sharpie / Uni-ball Signo DX),
        referenced against the CC-licensed photos in nb2/refs/ (see
        nb2/refs/CREDITS.txt).

    Outputs land in game/assets/nb2/ (or nb2/models/ for the model set) so
    the shipped skins are never touched. Capture them in the real scene with
    game/tests/nb2_shots.gd (identities) or game/tests/models_shots.gd
    (models).

Run (needs GOOGLE_API_KEY; reads only the key NAME from the profile .env):
    .asset-venv/bin/python game/assets/generate_pens_nb2.py [--only amber]
    .asset-venv/bin/python game/assets/generate_pens_nb2.py --set models [--only bic]
    .asset-venv/bin/python game/assets/generate_pens_nb2.py --set models --only sharpie --stretch 1.6
        (--stretch is a test knob: pre-stretches the reference horizontally;
         NB2 echoes reference composition, so a stretched ref can come back
         as a longer, slimmer pen.)

Outputs, per design:  pen_<name>.png  +  pen_<name>_shadow.png
plus the raw model output raw_<name>.png for provenance. The shadow is
authored from the generated silhouette with the same two-layer routine as
generate_pens_real.py, so a generated skin is never shipped without a
matching contact shadow.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import os
import re
import sys
import urllib.error
import urllib.request
from collections import deque

from PIL import Image, ImageFilter

BASE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(BASE, "nb2")
OUT_MODELS = os.path.join(BASE, "nb2", "models")
ENV_PATH = os.path.expanduser("~/.hermes/profiles/clutch/.env")
MODEL = "gemini-3.1-flash-image"
ENDPOINT = ("https://generativelanguage.googleapis.com/v1beta/models/"
            f"{MODEL}:generateContent")

CONTENT_W, CONTENT_H = 540, 30
CANVAS_W, CANVAS_H = 600, 100

# The shipped procedural sprite is handed to NB2 as the identity reference:
# same rough silhouette, same left-to-right anatomy, same colour family.
REFS = {
    "amber": "pen_amber.png",
    "cobalt": "pen_cobalt.png",
    "graphite": "pen_graphite.png",
    "ivory": "pen_ivory.png",
}

# Per-identity material direction. Kept short and physical: NB2 responds to
# material and lighting words, not to layout words.
IDENTITY = {
    "amber": ("glossy translucent amber-orange plastic barrel with a visible "
              "dark amber ink tube inside it, dark charcoal grey push-button "
              "cap"),
    "cobalt": ("glossy translucent cobalt blue plastic barrel with a visible "
               "deep navy ink tube inside it, matching cobalt blue cap"),
    "graphite": ("matte charcoal grey barrel with a softly brushed finish, "
                 "matching dark graphite cap, low sheen"),
    "ivory": ("matte ivory cream barrel with a soft pearl finish, matching "
              "pale ivory cap, warm champagne-gold metal nose cone"),
}

PROMPT = """A single {identity} — a real ballpoint pen photographed from directly above (top-down, 90 degrees), lying perfectly horizontal across the frame.

The pen points LEFT TO RIGHT: the rounded push-button cap and its metal clip are at the LEFT end, and the tapered metal nose cone with the writing tip is at the RIGHT end.

The pen is the ONLY object in the image, centred, filling the full width of the frame edge to edge, in sharp focus.

Background: a plain flat uniform mid-grey (#808080) background, completely empty, with NO shadow under the pen, no reflections on the surface, no other props, no text, no watermark, no border.

Lighting: soft even studio light from above. Keep the pen's own form shading so the cylinder reads as glossy plastic, but cast NO shadow onto the grey background."""

# --- models set: the four real pens, referenced by the photos in nb2/refs/ --
MODEL_REFS = {
    "bic":      ("refs/ref_bic.jpg",     "image/jpeg"),
    "jotter":   ("refs/ref_jotter.jpg",  "image/jpeg"),
    "sharpie":  ("refs/ref_sharpie.jpg", "image/jpeg"),
    "uniball":  ("refs/ref_uniball.jpg", "image/jpeg"),
}

MODEL_IDENTITY = {
    "bic": ("classic clear-bodied ballpoint pen with a transparent hexagonal "
            "barrel showing blue ink inside, a gold metal tip, and a blue "
            "plastic cap"),
    "jotter": ("slim all-metal ballpoint pen with a polished chrome steel "
               "barrel, a chrome cap with a flat pocket clip, and a tapered "
               "chrome nose cone"),
    "sharpie": ("permanent felt-tip marker with a solid black barrel and a "
                "matching black cap"),
    "uniball": ("slim gel pen with a clear transparent barrel, a black rubber "
                "grip section, a black cap with a metal clip, and a silver "
                "metal nose cone"),
}

# On-screen authoring thickness (px) per real pen. The capsule is 180x10 and
# the sprite displays at 1/3 scale, so 3 px of content = 1 px on screen.
# Slim pens get a little more body than the capsule; the marker gets real
# width (a Sharpie is ~8:1 in reality -- it must read fatter than the pens).
MODEL_THICK = {"bic": 11, "jotter": 11, "sharpie": 15, "uniball": 11}

MODEL_PROMPT = """A single {identity} — a real pen photographed from directly above (top-down, 90 degrees), lying perfectly horizontal across the frame.

The pen points LEFT TO RIGHT: the cap is at the LEFT end, and the writing tip is at the RIGHT end. The cap is attached to the pen — one single pen only, no loose parts, no second object.

The pen is the ONLY object in the image, centred, filling the full width of the frame edge to edge, both ends fully visible. The pen is very long and slender — much longer and thinner than in a typical product photo: its visible thickness is only about one fifteenth of its length. Slim, sleek, elongated. Render it in razor-sharp focus with crisp, high-contrast edges — no blur, no soft focus, no haze, no depth-of-field falloff. Match the reference image's colours and materials.

Background: a plain flat uniform mid-grey (#808080) background, completely empty, with NO shadow under the pen, no reflections on the surface, no other props, no text, no logos, no watermark, no border.

Lighting: soft even studio light from above. Keep the pen's own form shading so the materials read clearly, but cast NO shadow onto the grey background."""


def _load_key() -> str:
    """Read the Google key value from env or the profile .env (name only, never logs it)."""
    if os.environ.get("GOOGLE_API_KEY"):
        return os.environ["GOOGLE_API_KEY"]
    if os.path.exists(ENV_PATH):
        with open(ENV_PATH) as fh:
            for line in fh:
                m = re.match(r"\s*(?:export\s+)?GOOGLE_API_KEY\s*=\s*(.+?)\s*$", line)
                if m and not line.lstrip().startswith("#"):
                    return m.group(1).strip().strip('"').strip("'")
    sys.exit("GOOGLE_API_KEY not found (env or profile .env)")


def generate(design: str, key: str, design_set: str = "identities",
             stretch: float = 1.0) -> Image.Image:
    """One NB2 call -> decoded PNG image. stretch pre-stretches the ref horizontally."""
    if design_set == "models":
        rel, mime = MODEL_REFS[design]
        if design == "jotter":
            # The supplied photo's specular highlight + cast shadow were
            # misread by NB2 as a SECOND pen (V-shaped two-pen output). The
            # photo is pre-levelled onto flat grey (ref_jotter_flat2.jpg) and
            # the single-pen reading is spelled out below.
            rel = "refs/ref_jotter_flat2.jpg"
        ref_path = os.path.join(BASE, "nb2", rel)
        out_dir = OUT_MODELS
        prompt = MODEL_PROMPT.format(identity=MODEL_IDENTITY[design])
        if design == "jotter":
            prompt += (
                "\n\nIMPORTANT: exactly ONE single pen — do NOT duplicate it: no "
                "mirrored copy, no second pen, no V shape, nothing fused to the "
                "tip. The pen is perfectly STRAIGHT, lying horizontally at "
                "0 degrees (left to right), never diagonal. The reference "
                "photo's cast shadow and bright highlight along the barrel are "
                "photographic lighting on ONE pen — never draw them as separate "
                "objects or as a second edge. The barrel is solid polished "
                "chrome all around, not transparent or see-through. The "
                "background is this brief's flat uniform mid-grey (#808080), "
                "perfectly clean — ignore any texture, blotches or shadow "
                "visible in the reference. Render the pen in COOL SILVER "
                "polished chrome / steel: the warm golden-brown cast in the "
                "reference is the photo's ambient lighting, NOT the pen's "
                "colour — do not make the pen gold, brass, copper or "
                "rose-gold.")
        if design == "uniball":
            prompt += (
                "\n\nRender with PRODUCTION sharpness: crisp, high-contrast "
                "edges, no blur, no soft-focus. The black rubber grip, the "
                "black cap and the metal clip must be sharply defined against "
                "the barrel and the background.")
        if design == "sharpie":
            prompt += (
                "\n\nThe marker lies PERFECTLY HORIZONTAL (0 degrees, left to "
                "right — never diagonal). The black cap with its pocket clip "
                "is at the LEFT end; the black marker body is at the RIGHT "
                "end. Glossy jet-black finish. Crisp, clean silhouette edges; "
                "one single marker only.")
    else:
        ref_path = os.path.join(BASE, REFS[design])
        out_dir = OUT
        mime = "image/png"
        prompt = PROMPT.format(identity=IDENTITY[design])

    parts: list[dict] = []
    if os.path.exists(ref_path):
        with open(ref_path, "rb") as fh:
            ref_bytes = fh.read()
        if stretch != 1.0:
            ref_img = Image.open(io.BytesIO(ref_bytes)).convert("RGB")
            ref_img = ref_img.resize(
                (max(1, round(ref_img.width * stretch)), ref_img.height),
                Image.LANCZOS)
            buf = io.BytesIO()
            ref_img.save(buf, "PNG")
            ref_bytes = buf.getvalue()
            mime = "image/png"
        ref_b64 = base64.b64encode(ref_bytes).decode()
        parts.append({"text": "This is the pen design to match (reference):"})
        parts.append({"inline_data": {"mime_type": mime, "data": ref_b64}})
    parts.append({"text": prompt})

    body = json.dumps({
        "contents": [{"parts": parts}],
        "generationConfig": {"responseModalities": ["IMAGE"]},
    }).encode()

    req = urllib.request.Request(
        ENDPOINT, data=body,
        headers={"Content-Type": "application/json", "x-goog-api-key": key})
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            payload = json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        sys.exit(f"NB2 HTTP {exc.code}: {exc.read().decode()[:600]}")

    for cand in payload.get("candidates", []):
        for part in cand.get("content", {}).get("parts", []):
            blob = part.get("inline_data") or part.get("inlineData")
            if blob and blob.get("data"):
                raw = base64.b64decode(blob["data"])
                os.makedirs(out_dir, exist_ok=True)
                raw_path = os.path.join(out_dir, f"raw_{design}.png")
                with open(raw_path, "wb") as fh:
                    fh.write(raw)
                print(f"  NB2 raw -> {raw_path} ({len(raw)} B)")
                return Image.open(raw_path).convert("RGBA")
    sys.exit(f"NB2 returned no image part: {json.dumps(payload)[:600]}")


def key_to_alpha(img: Image.Image) -> Image.Image:
    """Flood-fill the background to transparent instead of colour-thresholding.

    The skill's rule: thresholding a photoreal render eats the pen's own dark
    pixels. Flood-fill from the border keys exactly the CONNECTED background
    region, so a grey pen on a grey backdrop survives intact.
    """
    img = img.convert("RGBA")
    if img.size[0] > 2200:  # clamp for BFS speed; 540-wide target needs no more
        h = max(1, round(img.size[1] * 2200 / img.size[0]))
        img = img.resize((2200, h), Image.LANCZOS)
    w, h = img.size
    px = img.load()

    # Background reference = median of a border ring sample.
    samples = []
    for x in range(0, w, max(1, w // 40)):
        for y in (0, 1, 2, h - 3, h - 2, h - 1):
            samples.append(px[x, y][:3])
    for y in range(0, h, max(1, h // 40)):
        for x in (0, 1, 2, w - 3, w - 2, w - 1):
            samples.append(px[x, y][:3])
    bg = tuple(sorted(c[i] for c in samples)[len(samples) // 2] for i in range(3))

    tol = 42  # generous: photoreal backdrops are not uniform, but the pen is

    def is_bg(c) -> bool:
        return (abs(c[0] - bg[0]) + abs(c[1] - bg[1]) + abs(c[2] - bg[2])) <= tol * 3

    # BFS from every border pixel that matches the background colour.
    seen = bytearray(w * h)
    q: deque = deque()
    for x in range(w):
        for y in (0, h - 1):
            if is_bg(px[x, y][:3]) and not seen[y * w + x]:
                seen[y * w + x] = 1
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if is_bg(px[x, y][:3]) and not seen[y * w + x]:
                seen[y * w + x] = 1
                q.append((x, y))
    while q:
        x, y = q.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h:
                i = ny * w + nx
                if not seen[i] and is_bg(px[nx, ny][:3]):
                    seen[i] = 1
                    q.append((nx, ny))

    # Flood-filled background -> 0; everything else keeps colour + soft edge.
    mask = Image.new("L", (w, h), 255)
    mp = mask.load()
    for i in range(w * h):
        if seen[i]:
            mp[i % w, i // w] = 0
    mask = mask.filter(ImageFilter.GaussianBlur(0.6))
    out = img.copy()
    out.putalpha(mask)
    return out


def normalize(img: Image.Image, thickness: int | None = None) -> Image.Image:
    """alpha -> bbox -> 540 x (3 x thickness) -> centred in 600x100.

    thickness = intended on-screen thickness in px. None -> capsule-exact
    540x30 (identities). The models set passes per-design thickness so real
    pens keep their proportions instead of being flattened onto 18:1. A
    light unsharp on the RGB channels recovers small-scale crispness after
    the heavy downscale; alpha stays soft so silhouette AA remains clean.
    """
    h = CONTENT_H if thickness is None else thickness * 3
    alpha = img.getchannel("A")
    bbox = alpha.point(lambda v: 255 if v > 40 else 0).getbbox()
    if bbox is None:
        sys.exit("normalize: the keyed image is fully transparent")
    pen = img.crop(bbox).resize((CONTENT_W, h), Image.LANCZOS)
    rgb = pen.convert("RGB").filter(
        ImageFilter.UnsharpMask(radius=1.2, percent=70, threshold=3))
    pen = Image.merge("RGBA", (*rgb.split(), pen.getchannel("A")))
    canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    canvas.alpha_composite(pen, ((CANVAS_W - CONTENT_W) // 2,
                                 (CANVAS_H - h) // 2))
    return canvas


def make_shadow(canvas: Image.Image) -> Image.Image:
    """Two-layer contact shadow from the skin's own silhouette.

    Identical routine to generate_pens_real.py: a tight core + a wide
    penumbra. A single small blur on a thin pen reads as a hard dark
    stripe, not as contact with a surface.
    """
    mask = canvas.getchannel("A")
    core = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    core.paste(Image.new("RGBA", canvas.size, (0, 0, 0, 150)), (0, 0), mask)
    core = core.filter(ImageFilter.GaussianBlur(4.0))
    penumbra = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    penumbra.paste(Image.new("RGBA", canvas.size, (0, 0, 0, 80)), (0, 0), mask)
    penumbra = penumbra.filter(ImageFilter.GaussianBlur(16.0))
    return Image.alpha_composite(penumbra, core)


def measure(canvas: Image.Image) -> tuple[tuple, float]:
    """Report the content bbox + raw model aspect, so the fit is proven not assumed."""
    bbox = canvas.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
    w = bbox[2] - bbox[0]
    h = bbox[3] - bbox[1]
    return bbox, (w / h if h else 0.0)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="comma-separated design names")
    ap.add_argument("--set", default="identities",
                    choices=("identities", "models"),
                    help="identities = shipped-look colour set (default); "
                         "models = real-pen photo set (refs/ in nb2/)")
    ap.add_argument("--stretch", type=float, default=1.0,
                    help="test knob: pre-stretch the reference horizontally "
                         "by this factor before sending it to NB2")
    args = ap.parse_args()

    refs = MODEL_REFS if args.set == "models" else REFS
    out_dir = OUT_MODELS if args.set == "models" else OUT
    want = [s.strip() for s in args.only.split(",") if s.strip()] or list(refs)
    os.makedirs(out_dir, exist_ok=True)
    key = _load_key()

    for design in want:
        if design not in refs:
            sys.exit(f"unknown design: {design}")
        print(f"[{design}] NB2 generating ({args.set} set) ...")
        raw = generate(design, key, args.set, args.stretch)
        keyed = key_to_alpha(raw)
        thickness = MODEL_THICK.get(design) if args.set == "models" else None
        canvas = normalize(keyed, thickness)
        bbox, aspect = measure(canvas)
        want_h = CONTENT_H if thickness is None else thickness * 3
        pen_path = os.path.join(out_dir, f"pen_{design}.png")
        canvas.save(pen_path)
        shadow_path = os.path.join(out_dir, f"pen_{design}_shadow.png")
        make_shadow(canvas).save(shadow_path)
        print(f"  content bbox {bbox}  -> {bbox[2]-bbox[0]}x{bbox[3]-bbox[1]} "
              f"(want 540x{want_h})   raw aspect {aspect:.2f}:1   "
              f"shadow {os.path.getsize(shadow_path)} B")
        with open(pen_path, "rb") as fh:
            print(f"  pen_{design}.png  {os.path.getsize(pen_path)} B  "
                  f"md5 {hashlib.md5(fh.read()).hexdigest()}")


if __name__ == "__main__":
    main()
