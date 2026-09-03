#!/usr/bin/env python3
"""Compatibility wrapper. Raster icons come from design/gdock-{light,dark}.png.

AX-GDOCK-ICONS-SOURCE: do not synthesize a glow from design/cmux-icon-chevron.png.
This entry point just runs scripts/generate_app_icons.py.
"""

from __future__ import annotations

import runpy
from pathlib import Path

if __name__ == "__main__":
    runpy.run_path(str(Path(__file__).with_name("generate_app_icons.py")), run_name="__main__")
