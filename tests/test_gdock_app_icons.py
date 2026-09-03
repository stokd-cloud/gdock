#!/usr/bin/env python3
"""AX-GDOCK-ICONS-SOURCE: shipped raster icons match design/gdock-{light,dark}.png.

The canonical sources are 1024x1024 mockups (cube on silver/black squircle, no
glow). AppIconLight/Dark, AppIcon.appiconset 512@2x(+_dark), and the iOS
AppIcon/AppIconDark files must be pixel-identical to those sources. Smaller
sizes must exist at the documented pixel dimensions. Debug 512@2x must keep the
cube (not the old cmux chevron) under a DEV banner.
"""

from __future__ import annotations

import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

LIGHT_SRC = os.path.join(ROOT, "design", "gdock-light.png")
DARK_SRC = os.path.join(ROOT, "design", "gdock-dark.png")
LIGHT_IMAGESET = os.path.join(
    ROOT, "Assets.xcassets", "AppIconLight.imageset", "AppIconLight.png"
)
DARK_IMAGESET = os.path.join(
    ROOT, "Assets.xcassets", "AppIconDark.imageset", "AppIconDark.png"
)
APPICONSET = os.path.join(ROOT, "Assets.xcassets", "AppIcon.appiconset")
DEBUG_1024 = os.path.join(
    ROOT, "Assets.xcassets", "AppIcon-Debug.appiconset", "512@2x.png"
)
IOS_ICONSETS = (
    os.path.join(ROOT, "ios", "cmux", "Assets.xcassets", "AppIcon.appiconset"),
    os.path.join(ROOT, "ios", "cmux", "Assets.xcassets", "AppIcon-Demo.appiconset"),
)

LIGHT_CENTER = (224, 224, 224)
DARK_CENTER = (31, 31, 31)
CUBE_LEFT = (5, 207, 255)
CENTER = (512, 512)
LEFT_FACE = (300, 512)
TOLERANCE = 8

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

FAILURES: list[str] = []


def fail(message: str) -> None:
    FAILURES.append(message)
    print(f"FAIL: {message}")


def rgb(pixel: tuple[int, ...]) -> tuple[int, int, int]:
    return (pixel[0], pixel[1], pixel[2])


def close(actual: tuple[int, int, int], expected: tuple[int, int, int], tol: int = TOLERANCE) -> bool:
    return all(abs(a - e) <= tol for a, e in zip(actual, expected))


def load(path: str) -> Image.Image | None:
    if not os.path.isfile(path):
        fail(f"missing {os.path.relpath(path, ROOT)}")
        return None
    return Image.open(path).convert("RGBA")


def pixels_equal(a: Image.Image, b: Image.Image, label: str) -> None:
    if a.size != b.size:
        fail(f"{label}: size {a.size} != {b.size}")
        return
    if a.tobytes() != b.tobytes():
        fail(f"{label}: pixels differ")


def expect_center(path: str, expected: tuple[int, int, int], label: str) -> Image.Image | None:
    img = load(path)
    if img is None:
        return None
    if img.size != (1024, 1024):
        fail(f"{label}: size {img.size} != (1024, 1024)")
    actual = rgb(img.getpixel(CENTER))
    if not close(actual, expected):
        fail(f"{label}: center {actual} != {expected} (±{TOLERANCE})")
    return img


def main() -> int:
    light_src = expect_center(LIGHT_SRC, LIGHT_CENTER, "design/gdock-light.png")
    dark_src = expect_center(DARK_SRC, DARK_CENTER, "design/gdock-dark.png")
    light_set = expect_center(LIGHT_IMAGESET, LIGHT_CENTER, "AppIconLight.png")
    dark_set = expect_center(DARK_IMAGESET, DARK_CENTER, "AppIconDark.png")

    if light_src is not None and light_set is not None:
        pixels_equal(light_src, light_set, "AppIconLight.png vs design/gdock-light.png")
    if dark_src is not None and dark_set is not None:
        pixels_equal(dark_src, dark_set, "AppIconDark.png vs design/gdock-dark.png")

    light_1024 = load(os.path.join(APPICONSET, "512@2x.png"))
    dark_1024 = load(os.path.join(APPICONSET, "512@2x_dark.png"))
    if light_src is not None and light_1024 is not None:
        pixels_equal(light_src, light_1024, "512@2x.png vs design/gdock-light.png")
    if dark_src is not None and dark_1024 is not None:
        pixels_equal(dark_src, dark_1024, "512@2x_dark.png vs design/gdock-dark.png")

    for filename, pixels in SIZES:
        for name in (filename, f"{os.path.splitext(filename)[0]}_dark.png"):
            path = os.path.join(APPICONSET, name)
            img = load(path)
            if img is None:
                continue
            if img.size != (pixels, pixels):
                fail(f"{os.path.relpath(path, ROOT)}: size {img.size} != ({pixels}, {pixels})")

    for iconset in IOS_ICONSETS:
        ios_light = load(os.path.join(iconset, "AppIcon.png"))
        ios_dark = load(os.path.join(iconset, "AppIconDark.png"))
        label = os.path.relpath(iconset, ROOT)
        if light_src is not None and ios_light is not None:
            pixels_equal(light_src, ios_light, f"{label}/AppIcon.png vs design/gdock-light.png")
        if dark_src is not None and ios_dark is not None:
            pixels_equal(dark_src, ios_dark, f"{label}/AppIconDark.png vs design/gdock-dark.png")

    debug = load(DEBUG_1024)
    if debug is not None:
        if debug.size != (1024, 1024):
            fail(f"AppIcon-Debug 512@2x.png: size {debug.size} != (1024, 1024)")
        face = rgb(debug.getpixel(LEFT_FACE))
        if not close(face, CUBE_LEFT):
            fail(
                f"AppIcon-Debug 512@2x.png: left cube face {face} != {CUBE_LEFT} "
                "(still the old chevron, or not derived from the new light mockup)"
            )

    if FAILURES:
        print(f"{len(FAILURES)} failure(s)")
        return 1
    print("gdock app icon source regression tests OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
