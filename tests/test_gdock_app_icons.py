#!/usr/bin/env python3
"""AX-GDOCK-ICONS-SOURCE: shipped raster icons match design/gdock-{light,dark}.png.

The canonical sources are 1024x1024 mockups (3D isometric cube on a light/dark
platform, transparent corners, no glow). AppIconLight/Dark, AppIcon.appiconset
512@2x(+_dark), and the iOS AppIcon/AppIconDark files must be pixel-identical
to those sources. Smaller sizes must exist at the documented pixel dimensions.
Debug 512@2x must keep the cube (not the old cmux chevron) under a DEV banner.
"""

from __future__ import annotations

import json
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
ICON_JSON = os.path.join(ROOT, "AppIcon.icon", "icon.json")
ICON_ASSETS = os.path.join(ROOT, "AppIcon.icon", "Assets")
IOS_ICONSETS = (
    os.path.join(ROOT, "ios", "cmux", "Assets.xcassets", "AppIcon.appiconset"),
    os.path.join(ROOT, "ios", "cmux", "Assets.xcassets", "AppIcon-Demo.appiconset"),
)

LIGHT_PLATFORM = (242, 240, 243)
DARK_PLATFORM = (40, 47, 57)
PLATFORM = (512, 850)
CUBE_TOP = (512, 100)
TOLERANCE = 16

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


def is_cube_cyan(pixel: tuple[int, int, int]) -> bool:
    return pixel[0] <= 120 and pixel[1] >= 180 and pixel[2] >= 220


def icon_layers(data: dict) -> list[dict]:
    layers: list[dict] = []
    for group in data.get("groups") or []:
        layers.extend(group.get("layers") or [])
    return layers


def spec_value(specs: list | None, appearance: str | None):
    for spec in specs or []:
        if appearance is None and "appearance" not in spec:
            return spec.get("value")
        if spec.get("appearance") == appearance:
            return spec.get("value")
    return None


def layer_hidden(layer: dict, appearance: str | None) -> bool:
    specialized = spec_value(layer.get("hidden-specializations"), appearance)
    if specialized is not None:
        return bool(specialized)
    if appearance is None:
        return bool(layer.get("hidden", False))
    return bool(layer.get("hidden", False))


def layer_glass(layer: dict) -> bool:
    if layer.get("glass") is True:
        return True
    return bool(spec_value(layer.get("glass-specializations"), "tinted"))


def find_layer(layers: list[dict], image_name: str) -> dict | None:
    for layer in layers:
        if layer.get("image-name") == image_name:
            return layer
    return None


def expect_icon_composer(light_src: Image.Image | None, dark_src: Image.Image | None) -> None:
    if not os.path.isfile(ICON_JSON):
        fail("missing AppIcon.icon/icon.json")
        return
    with open(ICON_JSON, encoding="utf-8") as handle:
        data = json.load(handle)

    default_fill = spec_value(data.get("fill-specializations"), None) or data.get("fill")
    dark_fill = spec_value(data.get("fill-specializations"), "dark")
    if default_fill not in ("system-light", "automatic"):
        fail(f"AppIcon.icon default fill {default_fill!r} is not system-light/automatic")
    if dark_fill != "system-dark":
        fail(f"AppIcon.icon dark fill {dark_fill!r} is not system-dark")

    layers = icon_layers(data)
    light_layer = find_layer(layers, "gdock-light.png")
    dark_layer = find_layer(layers, "gdock-dark.png")
    if light_layer is None:
        fail("AppIcon.icon has no Default layer gdock-light.png")
    else:
        if layer_hidden(light_layer, None):
            fail("gdock-light.png must be visible in Default")
        if not layer_hidden(light_layer, "dark"):
            fail("gdock-light.png must be hidden in Dark")
        if not layer_hidden(light_layer, "tinted"):
            fail("gdock-light.png must be hidden in Tinted/Clear")
    if dark_layer is None:
        fail("AppIcon.icon has no Dark layer gdock-dark.png")
    else:
        if not layer_hidden(dark_layer, None):
            fail("gdock-dark.png must be hidden in Default")
        if layer_hidden(dark_layer, "dark"):
            fail("gdock-dark.png must be visible in Dark")
        if not layer_hidden(dark_layer, "tinted"):
            fail("gdock-dark.png must be hidden in Tinted/Clear")

    glyph_layers = [
        layer
        for layer in layers
        if layer.get("image-name") not in {"gdock-light.png", "gdock-dark.png"}
        and layer_glass(layer)
    ]
    if not glyph_layers:
        fail("AppIcon.icon has no glass-enabled cube glyph for Tinted/Clear")
    else:
        glyph = glyph_layers[0]
        if not layer_hidden(glyph, None):
            fail("cube glyph must be hidden in Default")
        if not layer_hidden(glyph, "dark"):
            fail("cube glyph must be hidden in Dark")
        if layer_hidden(glyph, "tinted"):
            fail("cube glyph must be visible in Tinted/Clear")

    light_asset = load(os.path.join(ICON_ASSETS, "gdock-light.png"))
    dark_asset = load(os.path.join(ICON_ASSETS, "gdock-dark.png"))
    if light_src is not None and light_asset is not None:
        pixels_equal(light_src, light_asset, "AppIcon.icon/Assets/gdock-light.png")
    if dark_src is not None and dark_asset is not None:
        pixels_equal(dark_src, dark_asset, "AppIcon.icon/Assets/gdock-dark.png")


def expect_source(path: str, platform: tuple[int, int, int], label: str) -> Image.Image | None:
    img = load(path)
    if img is None:
        return None
    if img.size != (1024, 1024):
        fail(f"{label}: size {img.size} != (1024, 1024)")
    if img.getpixel((2, 2))[3] != 0:
        fail(f"{label}: corner (2,2) must stay transparent")
    actual_platform = rgb(img.getpixel(PLATFORM))
    if not close(actual_platform, platform):
        fail(f"{label}: platform {PLATFORM} {actual_platform} != {platform} (±{TOLERANCE})")
    actual_cube = rgb(img.getpixel(CUBE_TOP))
    if not is_cube_cyan(actual_cube):
        fail(
            f"{label}: cube-top {CUBE_TOP} {actual_cube} is not cyan "
            "(R≤120, G≥180, B≥220)"
        )
    return img


def main() -> int:
    light_src = expect_source(LIGHT_SRC, LIGHT_PLATFORM, "design/gdock-light.png")
    dark_src = expect_source(DARK_SRC, DARK_PLATFORM, "design/gdock-dark.png")
    light_set = expect_source(LIGHT_IMAGESET, LIGHT_PLATFORM, "AppIconLight.png")
    dark_set = expect_source(DARK_IMAGESET, DARK_PLATFORM, "AppIconDark.png")

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

    expect_icon_composer(light_src, dark_src)

    debug = load(DEBUG_1024)
    if debug is not None:
        if debug.size != (1024, 1024):
            fail(f"AppIcon-Debug 512@2x.png: size {debug.size} != (1024, 1024)")
        face = rgb(debug.getpixel(CUBE_TOP))
        if not is_cube_cyan(face):
            fail(
                f"AppIcon-Debug 512@2x.png: cube-top {CUBE_TOP} {face} is not cyan "
                "(still the old chevron, or DEV banner covers the cube)"
            )

    if FAILURES:
        print(f"{len(FAILURES)} failure(s)")
        return 1
    print("gdock app icon source regression tests OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
