#!/usr/bin/env python3
"""Composite raw Android captures into Google Play screenshots and the feature graphic.

Raw 1080x2400 emulator captures (android/play-assets/raw/) become 1080x1920
portrait screenshots (Play rejects anything longer than 2:1) with a short
headline above each, in the app's coral brand. Also writes the 1024x500
feature graphic from the 512px Play icon.

Usage: python3 scripts/play_screenshot_compositor.py
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "android" / "play-assets" / "raw"
OUT = ROOT / "android" / "play-assets" / "screenshots"
FEATURE = ROOT / "android" / "play-assets" / "feature-graphic.png"
ICON = ROOT / "android" / "play-assets" / "icon-512.png"
SFNS = "/System/Library/Fonts/SFNS.ttf"

BRAND = (242, 64, 92)
BRAND_DEEP = (219, 41, 110)
PAPER = (251, 246, 246)
PAPER_DEEP = (246, 236, 238)
INK = (28, 24, 28)
INK_SECONDARY = (102, 92, 98)

W, H = 1080, 1920
TOP = 92
HEADLINE = 72
LINE = 86
RULE_Y = TOP + 56 + 2 * LINE + 20
SHOT_TOP = RULE_Y + 46
SHOT_H = H - SHOT_TOP - 52
SHOT_W = round(SHOT_H * 1080 / 2400)
CORNER = 54


@dataclass(frozen=True)
class Shot:
    raw: str
    out: str
    eyebrow: str
    headline: str


SHOTS = [
    Shot("01_home.png", "01_one_tap.png", "ONE TAP", "Log a headache the moment it starts"),
    Shot("02_history.png", "02_history.png", "HISTORY", "Keep a clear record for your doctor"),
    Shot("03_patterns.png", "03_patterns.png", "PATTERNS", "See which triggers are yours"),
    Shot("04_alerts.png", "04_alerts.png", "ALERTS", "A heads-up before risky weather"),
    Shot("05_details.png", "05_insight.png", "INSIGHTS", "Every pattern explained with a chart"),
]


def sans(size: int, weight: str = "Semibold") -> ImageFont.FreeTypeFont:
    font = ImageFont.truetype(SFNS, size)
    try:
        font.set_variation_by_name(weight)
    except (OSError, ValueError):
        pass
    return font


def rounded_mask(size: tuple, radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([(0, 0), (size[0] - 1, size[1] - 1)], radius=radius, fill=255)
    return mask


def wrap(text: str, font: ImageFont.FreeTypeFont, max_width: int, draw: ImageDraw.ImageDraw) -> list:
    lines, line = [], ""
    for word in text.split():
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=font) <= max_width:
            line = trial
        else:
            lines.append(line)
            line = word
    lines.append(line)
    if len(lines) > 2:
        raise ValueError(f"headline wraps to {len(lines)} lines: {text}")
    return lines


def background(size: tuple) -> Image.Image:
    width, height = size
    img = Image.new("RGB", size, PAPER)
    draw = ImageDraw.Draw(img)
    for y in range(height):
        t = y / height
        draw.line([(0, y), (width, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(PAPER, PAPER_DEEP)))
    # Pad the glow canvas so the blur fades out instead of clipping into a hard band.
    glow = Image.new("RGBA", (2000, 2000), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([(300, 300), (1700, 1700)], fill=(*BRAND, 26))
    glow = glow.filter(ImageFilter.GaussianBlur(160))
    img.paste(glow, (width // 2 - 1000, -920), glow)
    return img


def render(shot: Shot) -> Path:
    canvas = background((W, H))
    draw = ImageDraw.Draw(canvas, "RGBA")
    eyebrow_font = sans(26, "Heavy")
    spaced = " ".join(shot.eyebrow)
    eb_w = draw.textlength(spaced, font=eyebrow_font)
    draw.text(((W - eb_w) / 2, TOP), spaced, font=eyebrow_font, fill=(*BRAND, 240))

    font = sans(HEADLINE, "Bold")
    lines = wrap(shot.headline, font, W - 160, draw)
    top = TOP + 56 + (2 - len(lines)) * LINE / 2
    for i, line in enumerate(lines):
        draw.text(((W - draw.textlength(line, font=font)) / 2, top + i * LINE), line, font=font, fill=INK)
    draw.rounded_rectangle([(W / 2 - 44, RULE_Y), (W / 2 + 44, RULE_Y + 5)], radius=3, fill=BRAND)

    raw = Image.open(RAW / shot.raw).convert("RGB")
    if raw.size != (1080, 2400):
        raise ValueError(f"{shot.raw} is {raw.size}, expected 1080x2400")
    scaled = raw.resize((SHOT_W, SHOT_H), Image.LANCZOS)
    left = (W - SHOT_W) // 2
    shadow = Image.new("RGBA", (SHOT_W + 100, SHOT_H + 100), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([(50, 62), (50 + SHOT_W, 62 + SHOT_H)], radius=CORNER, fill=(40, 10, 20, 64))
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    canvas.paste(shadow, (left - 50, SHOT_TOP - 50), shadow)
    canvas.paste(scaled, (left, SHOT_TOP), rounded_mask((SHOT_W, SHOT_H), CORNER))
    ImageDraw.Draw(canvas, "RGBA").rounded_rectangle(
        [(left, SHOT_TOP), (left + SHOT_W, SHOT_TOP + SHOT_H)], radius=CORNER, outline=(*BRAND, 110), width=3)

    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / shot.out
    canvas.save(path, "PNG")
    return path


def feature_graphic() -> Path:
    canvas = background((1024, 500))
    draw = ImageDraw.Draw(canvas, "RGBA")
    icon = Image.open(ICON).convert("RGB").resize((240, 240), Image.LANCZOS)
    canvas.paste(icon, (80, 130), rounded_mask((240, 240), 54))
    draw.text((370, 150), "One Tap", font=sans(64, "Bold"), fill=INK)
    draw.text((370, 222), "Headache Tracker", font=sans(64, "Bold"), fill=INK)
    draw.rounded_rectangle([(374, 312), (454, 317)], radius=3, fill=BRAND)
    tagline = sans(30, "Semibold")
    draw.text((372, 336), "Log in one tap. Spot your triggers.", font=tagline, fill=INK_SECONDARY)
    canvas.save(FEATURE, "PNG")
    return FEATURE


def main() -> None:
    for shot in SHOTS:
        path = render(shot)
        print(f"wrote {path.relative_to(ROOT)} {Image.open(path).size}")
    path = feature_graphic()
    print(f"wrote {path.relative_to(ROOT)} {Image.open(path).size}")


if __name__ == "__main__":
    main()
