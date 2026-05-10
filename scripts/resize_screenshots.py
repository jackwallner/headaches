#!/usr/bin/env python3
"""
Resize IMG screenshot files to App Store screenshot dimensions.
Valid sizes: 1242×2688, 2688×1242, 1284×2778, 2778×1284
Usage: python resize_screenshots.py [--output-dir DIR]
"""

import sys
from pathlib import Path
from PIL import Image

# App Store screenshot dimensions
VALID_DIMENSIONS = [
    (1242, 2688),  # iPhone XS Max/11 Pro Max portrait
    (2688, 1242),  # iPhone XS Max/11 Pro Max landscape
    (1284, 2778),  # iPhone 12/13/14 Pro Max portrait
    (2778, 1284),  # iPhone 12/13/14 Pro Max landscape
]


def get_target_size(width: int, height: int) -> tuple[int, int]:
    """Determine target size based on orientation and closest match."""
    is_portrait = height > width

    if is_portrait:
        # Choose between 1242x2688 and 1284x2778 based on aspect ratio
        aspect = height / width
        target_1 = 2688 / 1242  # ~2.165
        target_2 = 2778 / 1284  # ~2.164
        if abs(aspect - target_2) < abs(aspect - target_1):
            return (1284, 2778)
        return (1242, 2688)
    else:
        # Choose between 2688x1242 and 2778x1284
        aspect = width / height
        target_1 = 2688 / 1242
        target_2 = 2778 / 1284
        if abs(aspect - target_2) < abs(aspect - target_1):
            return (2778, 1284)
        return (2688, 1242)


def resize_image(input_path: Path, output_path: Path) -> None:
    """Resize image to App Store screenshot dimensions."""
    with Image.open(input_path) as img:
        width, height = img.size
        target = get_target_size(width, height)

        if (width, height) == target:
            print(f"Skipping {input_path.name} (already {width}×{height}px)")
            return

        resized = img.resize(target, Image.LANCZOS)
        resized.save(output_path, optimize=True)
        print(f"Resized {input_path.name} -> {target[0]}×{target[1]}px")


def main():
    output_dir = Path("resized")

    if "--output-dir" in sys.argv:
        idx = sys.argv.index("--output-dir")
        if idx + 1 < len(sys.argv):
            output_dir = Path(sys.argv[idx + 1])

    img_files = list(Path.cwd().glob("IMG*")) + list(Path.cwd().glob("img*"))
    img_files = [f for f in img_files if f.suffix.lower() in (".png", ".jpg", ".jpeg")]

    if not img_files:
        print("No IMG files found")
        return

    output_dir.mkdir(exist_ok=True)

    for img_path in img_files:
        out_path = output_dir / f"{img_path.stem}_resized{img_path.suffix}"
        resize_image(img_path, out_path)

    print(f"\nDone. Resized images saved to: {output_dir}")


if __name__ == "__main__":
    main()
