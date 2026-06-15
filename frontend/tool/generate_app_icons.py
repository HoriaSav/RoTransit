#!/usr/bin/env python3
"""Generate app icon assets from assets/New_app_icon.png.

All launcher assets are derived from the same rounded icon used in-app
(`app_icon.png`), with extra padding only for Android adaptive foreground
so the OS mask does not crop/zoom the logo.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
SOURCE = ASSETS / "New_app_icon.png"
IN_APP_SIZE = 512
LAUNCHER_SIZE = 1024
# Matches ClipRRect(borderRadius: 8) on the 36px header icon (8/36 ≈ 22%).
CORNER_RADIUS_RATIO = 0.22
LAUNCHER_BACKGROUND = (0x1C, 0x2D, 0x49)
# Keep logo inside Android adaptive icon safe zone (~66% diameter).
ADAPTIVE_FOREGROUND_SCALE = 0.58


def _square_canvas(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    width, height = rgba.size
    side = max(width, height)
    corner = rgba.getpixel((0, 0))
    background = corner if len(corner) == 4 else (*corner[:3], 255)
    canvas = Image.new("RGBA", (side, side), background)
    canvas.paste(rgba, ((side - width) // 2, (side - height) // 2), rgba)
    return canvas


def _rounded_rect_mask(size: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    radius = max(1, round(size * CORNER_RADIUS_RATIO))
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def _canonical_rounded_icon(image: Image.Image, size: int) -> Image.Image:
    """Same shape as the in-app header icon."""
    squared = _square_canvas(image).resize((size, size), Image.Resampling.LANCZOS)
    mask = _rounded_rect_mask(size)
    output = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    output.paste(squared, (0, 0), mask)
    return output


def _composite_on_background(rgba: Image.Image, bg_rgb: tuple[int, int, int]) -> Image.Image:
    background = Image.new("RGBA", rgba.size, (*bg_rgb, 255))
    background.alpha_composite(rgba)
    return background


def _adaptive_foreground(image: Image.Image, size: int) -> Image.Image:
    """Padded foreground so Android's launcher mask does not zoom/crop the bus."""
    canonical = _canonical_rounded_icon(image, size)
    inner_size = max(1, round(size * ADAPTIVE_FOREGROUND_SCALE))
    scaled = canonical.resize((inner_size, inner_size), Image.Resampling.LANCZOS)
    output = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    offset = (size - inner_size) // 2
    output.paste(scaled, (offset, offset), scaled)
    return output


def main() -> None:
    if not SOURCE.exists():
        raise SystemExit(f"Missing source icon: {SOURCE}")

    source = Image.open(SOURCE)
    in_app = _canonical_rounded_icon(source, IN_APP_SIZE)
    launcher_rounded = _canonical_rounded_icon(source, LAUNCHER_SIZE)
    launcher_opaque = _composite_on_background(launcher_rounded, LAUNCHER_BACKGROUND)
    adaptive_foreground = _adaptive_foreground(source, LAUNCHER_SIZE)

    outputs = {
        ASSETS / "app_icon.png": in_app,
        ASSETS / "launcher_icon.png": launcher_opaque,
        ASSETS / "adaptive_icon_foreground.png": adaptive_foreground,
        # Legacy aliases kept for reference / tooling.
        ASSETS / "rounded_app_icon.png": launcher_rounded,
        ASSETS / "rounded_app_icon_launcher.png": adaptive_foreground,
    }

    for path, image in outputs.items():
        image.save(path, format="PNG", optimize=True)
        print(f"wrote {path.relative_to(ROOT)} ({image.size[0]}x{image.size[1]})")


if __name__ == "__main__":
    main()
