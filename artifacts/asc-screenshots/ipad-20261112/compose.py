#!/usr/bin/env python3
"""Compose the 13-inch iPad App Store frames (2064x2752) from raw iPad captures.

Raw frames: raw/<locale>/<frame>.png (2064x2752 simulator captures).
Output:     out/<locale>/<frame>.png
The device bleeds off the bottom edge so the empty lower part of the screen is
cropped. Style matches the iPhone set: pale mint gradient, one large dark-teal header of
at most two lines, the real screen in a black device bezel.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
CANVAS = (2064, 2752)
TOP = (238, 248, 245)
BOTTOM = (203, 232, 227)
INK = (23, 63, 66)
FONT = "/System/Library/Fonts/Avenir Next.ttc"
FONT_INDEX = 7  # Avenir Next Regular
HEADER_BOX = (110, 110, 1844, 430)  # x, y, w, h
MAX_SIZE, MIN_SIZE = 200, 120
BEZEL = 34
SCREEN_W = 1780
DEVICE_TOP = 600


def gradient() -> Image.Image:
    img = Image.new("RGB", CANVAS)
    px = ImageDraw.Draw(img)
    for y in range(CANVAS[1]):
        t = y / (CANVAS[1] - 1)
        px.line([(0, y), (CANVAS[0], y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))
    return img


def font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT, size, index=FONT_INDEX)


def wrap(draw: ImageDraw.ImageDraw, text: str, size: int, width: int) -> list[str]:
    f = font(size)
    lines: list[str] = []
    for part in text.split("\n"):
        line = ""
        for word in part.split(" "):
            trial = f"{line} {word}".strip()
            if draw.textlength(trial, font=f) <= width or not line:
                line = trial
            else:
                lines.append(line)
                line = word
        lines.append(line)
    return lines


def draw_header(img: Image.Image, text: str) -> None:
    draw = ImageDraw.Draw(img)
    x, y, w, h = HEADER_BOX
    for size in range(MAX_SIZE, MIN_SIZE - 1, -4):
        lines = wrap(draw, text, size, w)
        if len(lines) <= 2 and len(lines) * size * 1.12 <= h:
            break
    else:
        raise SystemExit(f"header does not fit in two lines: {text!r}")
    f = font(size)
    lead = size * 1.12
    top = y + (h - lead * len(lines)) / 2
    for i, line in enumerate(lines):
        width = draw.textlength(line, font=f)
        draw.text((x + (w - width) / 2, top + i * lead), line, font=f, fill=INK)


def device(raw: Image.Image) -> Image.Image:
    screen_h = round(SCREEN_W * raw.height / raw.width)
    screen = raw.convert("RGB").resize((SCREEN_W, screen_h), Image.LANCZOS)
    w, h = SCREEN_W + 2 * BEZEL, screen_h + 2 * BEZEL
    radius_outer, radius_inner = 100, 100 - BEZEL
    scale = 4
    body = Image.new("L", (w * scale, h * scale), 0)
    ImageDraw.Draw(body).rounded_rectangle((0, 0, w * scale - 1, h * scale - 1), radius_outer * scale, fill=255)
    body = body.resize((w, h), Image.LANCZOS)
    inner = Image.new("L", (SCREEN_W * scale, screen_h * scale), 0)
    ImageDraw.Draw(inner).rounded_rectangle((0, 0, SCREEN_W * scale - 1, screen_h * scale - 1), radius_inner * scale, fill=255)
    inner = inner.resize((SCREEN_W, screen_h), Image.LANCZOS)
    dev = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dev.paste(Image.new("RGBA", (w, h), (12, 14, 16, 255)), (0, 0), body)
    dev.paste(screen, (BEZEL, BEZEL), inner)
    return dev


def compose(raw_path: Path, header: str, out_path: Path) -> None:
    raw = Image.open(raw_path)
    if raw.size != CANVAS:
        raise SystemExit(f"{raw_path}: raw is {raw.size}, expected {CANVAS}")
    img = gradient()
    draw_header(img, header)
    dev = device(raw)
    top = DEVICE_TOP
    img.paste(dev, ((CANVAS[0] - dev.width) // 2, top), dev)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_path, "PNG")


def main() -> None:
    headers = json.loads((HERE / "headers.json").read_text())
    locales = sys.argv[1:] or list(headers)
    for loc in locales:
        for frame, text in headers[loc].items():
            raw = HERE / "raw" / loc / frame
            if not raw.exists():
                print(f"skip {loc}/{frame}: no raw")
                continue
            compose(raw, text, HERE / "out" / loc / frame)
            print(f"ok {loc}/{frame}")


if __name__ == "__main__":
    main()
