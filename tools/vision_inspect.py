#!/usr/bin/env python3
"""Screenshot-loop vision inspector for pen-fight.

Sends a game frame (PNG) + question to deepseek/deepseek-v4-flash-vision-exp
on OpenRouter and prints the model's text answer.

Usage:
  python3 vision_inspect.py frame.png "where is the pen?"
  python3 vision_inspect.py --selftest          # prove the pipe works with a synthetic frame

Notes (learned the hard way, 2026-09-13):
  * vision-exp is a REASONING model: with max_tokens < ~400 the answer stays in
    the `reasoning` field and `content` is null, finish_reason='length'.
    Always request >= 400 and read message.content (fall back to reasoning).
  * Sending a PNG as data URL (base64 inline) works; no upload endpoint needed.
  * API key comes from OPENROUTER_API_KEY in ~/.hermes/.env (first non-comment match).
"""
import base64
import json
import os
import struct
import sys
import urllib.request
import zlib


MODEL = "deepseek/deepseek-v4-flash-vision-exp"
MAX_TOKENS = 512
OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"


def _api_key():
    env = os.path.expanduser("~/.hermes/.env")
    if os.path.exists(env):
        for line in open(env):
            if line.startswith("OPENROUTER_API_KEY="):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    try:
        d = json.load(open(os.path.expanduser("~/.hermes/profiles/clutch/auth.json")))
        return d.get("providers", {}).get("openrouter", {}).get("api_key", "")
    except Exception:
        return ""


def _png_bytes(path):
    """Byte-graphical fallback only used by --selftest (no PIL dependency on this box)."""
    if not path.startswith("GENERATED:"):
        with open(path, "rb") as f:
            return f.read()

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        c += struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        return c

    w, h = 160, 90
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            if y < 30:
                px = (0, 0, 200)          # table edge (blue band)
            elif 40 <= y < 52 and 20 <= x < 120:
                px = (220, 60, 20)        # pen (orange bar)
            else:
                px = (40, 40, 40)
            raw += bytes(px)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")


def inspect(png_path, question):
    key = _api_key()
    if not key:
        raise SystemExit("no OPENROUTER_API_KEY found in ~/.hermes/.env")
    b64 = base64.b64encode(_png_bytes(png_path)).decode()
    payload = {
        "model": MODEL,
        "messages": [{
            "role": "user",
            "content": [
                {"type": "text", "text": question},
                {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{b64}"}},
            ],
        }],
        "max_tokens": MAX_TOKENS,
    }
    req = urllib.request.Request(
        OPENROUTER_URL,
        data=json.dumps(payload).encode(),
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://hermes-agent.nousresearch.com",
            "X-Title": "pen-fight-loop",
        },
    )
    with urllib.request.urlopen(req, timeout=120) as r:
        resp = json.loads(r.read())
    msg = resp["choices"][0]["message"]
    finish = resp["choices"][0].get("finish_reason")
    text = msg.get("content") or msg.get("reasoning") or ""
    return {"model": resp.get("model"), "finish": finish, "answer": text.strip()}


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--selftest":
        out = inspect("GENERATED:selftest", "Reply with ONLY one short sentence: where is the orange bar relative to the blue bar? Do not explain.")
        print(f"model:   {out['model']}   finish: {out['finish']}")
        print(f"answer:  {out['answer']}")
        sys.exit(0 if out["answer"] else 1)
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    out = inspect(sys.argv[1], sys.argv[2])
    print(out["answer"])