#!/usr/bin/env python3
"""Android launcher icon and Play icon from the iOS app icon (no redrawing, so they never drift).

The iOS icon is a coral-to-magenta gradient square with a white head profile.
The adaptive icon takes a matching gradient as its background layer and the
head, keyed on its green channel (the gradient's green never passes ~115), as
the foreground. The iOS square maps onto the 72dp visible area of the 108dp
canvas, which keeps the head inside the safe zone. The same head in white is
the themed-icon monochrome layer. Also writes the 512px Play icon.
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "HeadacheLogger/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
RES = ROOT / "android/app/src/main/res"
DENSITIES = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}


def glyph(icon: Image.Image) -> Image.Image:
    """The head with the gradient keyed to transparency (soft edges kept)."""
    out = Image.new("RGBA", icon.size)
    src = icon.load()
    dst = out.load()
    for y in range(icon.height):
        for x in range(icon.width):
            g = src[x, y][1]
            alpha = max(0, min(255, round((g - 115) / (245 - 115) * 255)))
            dst[x, y] = (255, 255, 255, alpha)
    return out


def layer(art: Image.Image, px: int) -> Image.Image:
    canvas = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    inner = round(px * 72 / 108)
    canvas.paste(art.resize((inner, inner), Image.LANCZOS), ((px - inner) // 2, (px - inner) // 2))
    return canvas


def hexcolor(pixel: tuple[int, int, int]) -> str:
    return "#{:02X}{:02X}{:02X}".format(*pixel)


def main() -> None:
    icon = Image.open(SOURCE).convert("RGB")
    top_left = icon.getpixel((4, 4))
    bottom_right = icon.getpixel((icon.width - 5, icon.height - 5))
    head = glyph(icon)
    for name, px in DENSITIES.items():
        folder = RES / f"mipmap-{name}"
        folder.mkdir(parents=True, exist_ok=True)
        layer(head, px).save(folder / "ic_launcher_foreground.png")
        layer(head, px).save(folder / "ic_launcher_monochrome.png")
    drawable = RES / "drawable"
    drawable.mkdir(parents=True, exist_ok=True)
    (drawable / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">\n'
        f'    <gradient android:angle="315" android:startColor="{hexcolor(top_left)}" '
        f'android:endColor="{hexcolor(bottom_right)}" />\n</shape>\n'
    )
    xml = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
"""
    anydpi = RES / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(xml)
    (anydpi / "ic_launcher_round.xml").write_text(xml)
    assets = ROOT / "android/play-assets"
    assets.mkdir(parents=True, exist_ok=True)
    icon.resize((512, 512), Image.LANCZOS).save(assets / "icon-512.png")
    print("wrote adaptive icon layers and play-assets/icon-512.png")


if __name__ == "__main__":
    main()
