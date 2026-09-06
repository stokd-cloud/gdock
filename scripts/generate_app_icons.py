#!/usr/bin/env python3
"""Generate gdock raster app icons from design/gdock-{light,dark}.png.

AX-GDOCK-ICONS-SOURCE: those two 1024x1024 files are the canonical light and
dark sources. This script resizes them into AppIcon.appiconset, copies them
into the AppIconLight/Dark imagesets and iOS AppIcon sets, and overlays DEV /
NIGHTLY banners for the Debug and Nightly icon sets.

Do not synthesize a glow or rebuild the mark from design/cmux-icon-chevron.png.

Also copies the light/dark mockups and a glass cube glyph into AppIcon.icon/Assets
for Tahoe Default / Dark / Tinted+Clear appearances.
"""

from __future__ import annotations

import os
import shutil

from PIL import Image, ImageDraw, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

LIGHT_SRC = os.path.join(REPO, "design", "gdock-light.png")
DARK_SRC = os.path.join(REPO, "design", "gdock-dark.png")
CUBE_GLYPH = os.path.join(REPO, "design", "ghostty-dock-icon-v2.png")

APPICONSET = os.path.join(REPO, "Assets.xcassets", "AppIcon.appiconset")
DEBUG_SET = os.path.join(REPO, "Assets.xcassets", "AppIcon-Debug.appiconset")
NIGHTLY_SET = os.path.join(REPO, "Assets.xcassets", "AppIcon-Nightly.appiconset")
LIGHT_IMAGESET = os.path.join(
    REPO, "Assets.xcassets", "AppIconLight.imageset", "AppIconLight.png"
)
DARK_IMAGESET = os.path.join(
    REPO, "Assets.xcassets", "AppIconDark.imageset", "AppIconDark.png"
)
IOS_SETS = (
    os.path.join(REPO, "ios", "cmux", "Assets.xcassets", "AppIcon.appiconset"),
    os.path.join(REPO, "ios", "cmux", "Assets.xcassets", "AppIcon-Demo.appiconset"),
)
ICON_ASSETS = os.path.join(REPO, "AppIcon.icon", "Assets")

ORANGE = (255, 107, 0, 255)
PURPLE = (140, 60, 220, 255)

SIZES = [
    ("16.png", 16),
    ("16@2x.png", 32),
    ("32.png", 32),
    ("32@2x.png", 64),
    ("128.png", 128),
    ("128@2x.png", 256),
    ("256.png", 256),
    ("256@2x.png", 512),
    ("512.png", 512),
    ("512@2x.png", 1024),
]


def require_source(path: str) -> None:
    if not os.path.isfile(path):
        raise SystemExit(f"missing canonical icon source: {path}")


def copy_1024(src: str, dst: str) -> None:
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(src, dst)
    print(f"  copy {os.path.relpath(dst, REPO)}")


def write_resized(src_img: Image.Image, dst: str, size: int) -> None:
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if src_img.size == (size, size):
        src_img.save(dst, "PNG")
    else:
        src_img.resize((size, size), Image.LANCZOS).save(dst, "PNG")
    print(f"  {os.path.relpath(dst, REPO)} ({size}x{size})")


def banner_font(size: int) -> ImageFont.ImageFont:
    for path in (
        "/System/Library/Fonts/SFCompact-Bold.otf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ):
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def overlay_banner(base: Image.Image, text: str, color: tuple[int, int, int, int]) -> Image.Image:
    img = base.convert("RGBA").copy()
    w, h = img.size
    banner_y = int(h * 0.82)
    draw = ImageDraw.Draw(img)
    draw.rectangle([0, banner_y, w, h], fill=color)
    font_size = max(int((h - banner_y) * 0.55), 6)
    font = banner_font(font_size)
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = (w - tw) // 2 - bbox[0]
    ty = banner_y + ((h - banner_y) - th) // 2 - bbox[1]
    draw.text((tx, ty), text, fill=(255, 255, 255, 255), font=font)
    return img


def write_set(src_img: Image.Image, dest_dir: str, suffix: str = "") -> None:
    for filename, pixels in SIZES:
        if suffix:
            stem, ext = os.path.splitext(filename)
            filename = f"{stem}{suffix}{ext}"
        write_resized(src_img, os.path.join(dest_dir, filename), pixels)


def write_tinted(dest: str) -> None:
    """iOS tinted appearance: white cube glyph on a transparent 1024 canvas."""
    canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    if os.path.isfile(CUBE_GLYPH):
        glyph = Image.open(CUBE_GLYPH).convert("RGBA")
        target = 620
        scale = target / max(glyph.size)
        new_size = (max(1, int(glyph.width * scale)), max(1, int(glyph.height * scale)))
        glyph = glyph.resize(new_size, Image.LANCZOS)
        px = glyph.load()
        for y in range(glyph.height):
            for x in range(glyph.width):
                _, _, _, a = px[x, y]
                if a:
                    px[x, y] = (255, 255, 255, a)
        ox = (1024 - glyph.width) // 2
        oy = (1024 - glyph.height) // 2
        canvas.alpha_composite(glyph, (ox, oy))
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    canvas.save(dest, "PNG")
    print(f"  {os.path.relpath(dest, REPO)} (tinted)")


def main() -> int:
    require_source(LIGHT_SRC)
    require_source(DARK_SRC)

    light = Image.open(LIGHT_SRC).convert("RGBA")
    dark = Image.open(DARK_SRC).convert("RGBA")
    if light.size != (1024, 1024) or dark.size != (1024, 1024):
        raise SystemExit(
            f"canonical sources must be 1024x1024; got light={light.size} dark={dark.size}"
        )

    print("AppIcon.appiconset:")
    write_set(light, APPICONSET)
    write_set(dark, APPICONSET, suffix="_dark")

    print("imagesets:")
    copy_1024(LIGHT_SRC, LIGHT_IMAGESET)
    copy_1024(DARK_SRC, DARK_IMAGESET)
    copy_1024(LIGHT_SRC, os.path.join(REPO, "design", "512@2x.png"))
    copy_1024(DARK_SRC, os.path.join(REPO, "design", "512@2x_dark.png"))

    print("iOS:")
    for iconset in IOS_SETS:
        copy_1024(LIGHT_SRC, os.path.join(iconset, "AppIcon.png"))
        copy_1024(DARK_SRC, os.path.join(iconset, "AppIconDark.png"))
        write_tinted(os.path.join(iconset, "AppIconTinted.png"))

    print("AppIcon-Debug:")
    debug_1024 = overlay_banner(light, "DEV", ORANGE)
    write_set(debug_1024, DEBUG_SET)

    print("AppIcon-Nightly:")
    nightly_1024 = overlay_banner(light, "NIGHTLY", PURPLE)
    write_set(nightly_1024, NIGHTLY_SET)

    print("AppIcon.icon:")
    copy_1024(LIGHT_SRC, os.path.join(ICON_ASSETS, "gdock-light.png"))
    copy_1024(DARK_SRC, os.path.join(ICON_ASSETS, "gdock-dark.png"))
    write_tinted(os.path.join(ICON_ASSETS, "cube-glyph.png"))

    print("generated raster icons from design/gdock-{light,dark}.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
