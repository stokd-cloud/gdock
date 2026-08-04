#!/usr/bin/env python3
"""Deterministic thin-skin brand rewrite for gdock.

Rewrites user-visible values only. Never touches:
- web/**
- CHANGELOG.md
- CMUX_* tokens
- xcstrings keys
- .sdef code= attributes
- Swift type names / filenames
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

# Values-only replacements (applied to text files and xcstrings string values).
VALUE_REPLACEMENTS = [
    # longer first
    (re.compile(r"~/.config/cmux"), "~/.config/ghostty-dock"),
    (re.compile(r"\bcmux DEV\b"), "gdock DEV"),
    (re.compile(r"\bcmux STAGING\b"), "gdock STAGING"),
    (re.compile(r"\bcmux NIGHTLY\b"), "gdock NIGHTLY"),
    (re.compile(r"\bQuit cmux\b"), "Quit gdock"),
    (re.compile(r"\bShow cmux\b"), "Show gdock"),
    (re.compile(r"\bcmux would like\b"), "gdock would like"),
    (re.compile(r"\bwithin cmux\b"), "within gdock"),
    (re.compile(r"\bthe cmux\b"), "the gdock"),
    (re.compile(r"\bA cmux\b"), "A gdock"),
    (re.compile(r"\bcmux\b"), "gdock"),  # last-resort prose token
]

# Do not rewrite these token contexts even inside values.
PROTECT_PATTERNS = [
    re.compile(r"CMUX_[A-Z0-9_]+"),
    re.compile(r"cmux\.json"),
    re.compile(r"cmux\.sock"),
    re.compile(r"cmuxd"),
    re.compile(r"\.cmux/"),
    re.compile(r"homebrew-cmux"),
    re.compile(r"com\.cmuxterm"),  # keychain etc. if any slip through
]


def protect(text: str) -> tuple[str, dict[str, str]]:
    placeholders: dict[str, str] = {}
    out = text
    i = 0
    for pat in PROTECT_PATTERNS:
        def repl(m, i=i):
            key = f"__BRAND_PROTECT_{len(placeholders)}__"
            placeholders[key] = m.group(0)
            return key
        out = pat.sub(repl, out)
    return out, placeholders


def unprotect(text: str, placeholders: dict[str, str]) -> str:
    for k, v in placeholders.items():
        text = text.replace(k, v)
    return text


def transform_text(text: str) -> str:
    protected, placeholders = protect(text)
    for pat, repl in VALUE_REPLACEMENTS:
        protected = pat.sub(repl, protected)
    # Fix double brand from re-runs
    protected = protected.replace("Ghostty gdock", "gdock")
    return unprotect(protected, placeholders)


def transform_xcstrings(path: pathlib.Path) -> bool:
    data = json.loads(path.read_text(encoding="utf-8"))
    strings = data.get("strings", {})
    changed = False
    for key, entry in strings.items():
        localizations = entry.get("localizations") or {}
        for locale, loc in localizations.items():
            unit = loc.get("stringUnit") or {}
            value = unit.get("value")
            if not isinstance(value, str):
                continue
            new_value = transform_text(value)
            if new_value != value:
                unit["value"] = new_value
                loc["stringUnit"] = unit
                localizations[locale] = loc
                changed = True
        entry["localizations"] = localizations
        strings[key] = entry
    if changed:
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return changed


def transform_file(path: pathlib.Path) -> bool:
    rel = path.relative_to(ROOT).as_posix()
    if rel.startswith("web/") or rel == "CHANGELOG.md":
        return False
    if path.suffix in {".xcstrings"}:
        return transform_xcstrings(path)
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return False
    new = transform_text(text)
    if new != text:
        path.write_text(new, encoding="utf-8")
        return True
    return False


DEFAULT_TARGETS = [
    "Resources/Localizable.xcstrings",
    "Resources/InfoPlist.xcstrings",
    "Resources/Info.plist",
    "Resources/cmux.sdef",
    "README.md",
]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="exit 1 if changes would be made")
    parser.add_argument("paths", nargs="*", help="optional subset of paths")
    args = parser.parse_args()
    targets = [ROOT / p for p in (args.paths or DEFAULT_TARGETS)]
    would = []
    for path in targets:
        if not path.exists():
            continue
        if args.check:
            # dry-run: copy transform in memory
            if path.suffix == ".xcstrings":
                data = json.loads(path.read_text(encoding="utf-8"))
                before = json.dumps(data, sort_keys=True)
                # shallow check via temp transform of values
                dirty = False
                for entry in (data.get("strings") or {}).values():
                    for loc in (entry.get("localizations") or {}).values():
                        unit = loc.get("stringUnit") or {}
                        value = unit.get("value")
                        if isinstance(value, str) and transform_text(value) != value:
                            dirty = True
                            break
                    if dirty:
                        break
                if dirty:
                    would.append(path)
            else:
                text = path.read_text(encoding="utf-8")
                if transform_text(text) != text:
                    would.append(path)
        else:
            if transform_file(path):
                would.append(path)
    if args.check:
        if would:
            for p in would:
                print(f"would change: {p.relative_to(ROOT)}")
            return 1
        print("apply-brand: clean")
        return 0
    for p in would:
        print(f"updated: {p.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
