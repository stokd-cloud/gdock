#!/usr/bin/env python3
"""Brand consistency guard for Ghostty Dock thin-skin rebrand."""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

def main() -> int:
    errors = []
    plist = (ROOT / "Resources/Info.plist").read_text(encoding="utf-8")
    if "manaflow-ai" in plist:
        errors.append("Resources/Info.plist still references manaflow-ai")
    if "<key>SUEnableAutomaticChecks</key>\n\t<true/>" in plist:
        errors.append("SUEnableAutomaticChecks still true")
    pbx = (ROOT / "cmux.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
    if "avjcgKibf1FTvhIjLBxhd+0HSpsXU4D0IGlVk8cgqRc=" in pbx:
        errors.append("manaflow SPARKLE_PUBLIC_KEY still present")
    if 'PRODUCT_BUNDLE_IDENTIFIER = com.cmuxterm' in pbx:
        errors.append("com.cmuxterm PRODUCT_BUNDLE_IDENTIFIER still present")
    if 'PRODUCT_NAME = gdock;' not in pbx:
        errors.append("CLI PRODUCT_NAME gdock missing")
    if "Ghostty Dock" not in pbx:
        errors.append("Ghostty Dock PRODUCT_NAME missing")
    # CMUX_ env names must still exist in Sources (smoke: do not require zero renames)
    sources = (ROOT / "Sources").rglob("*.swift")
    cmux_env = 0
    for f in sources:
        try:
            text = f.read_text(encoding="utf-8")
        except Exception:
            continue
        cmux_env += len(re.findall(r"CMUX_[A-Z0-9_]+", text))
    if cmux_env < 100:
        errors.append(f"CMUX_* env tokens suspiciously low ({cmux_env}); rename may have broken C4")
    if errors:
        for e in errors:
            print(f"FAIL: {e}")
        return 1
    print("check-brand: ok")
    return 0

if __name__ == "__main__":
    sys.exit(main())
