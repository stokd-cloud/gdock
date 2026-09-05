# PRD: gdock Auto Splitter

## 0. Source Context

**Derived From:** User request on 2026-08-11 for Auto Split Rows, Auto Split Columns,
Cmd+Y Auto Split, and a toggleable Force Auto Splitter mode.
**Feature Name:** gdock Auto Splitter
**PRD Owner:** Brian Stoker
**Last Updated:** 2026-08-11
**Repository:** `stokd-cloud/gdock` (ghostty-dock fork of `manaflow-ai/cmux`), branch `main`
**Landing:** fork-only on `main`

### Summary

Add a parameterized Auto Split action to gdock. Auto Split uses two new settings,
`gdock.autoSplitRows` and `gdock.autoSplitColumns`, defaulting to `2` and `2`.
Cmd+Y triggers Auto Split against the focused pane. Auto Split behaves like the
current Split Quad action except the target topology is `rows x columns` instead
of always `2 x 2`.

Add a third setting, `gdock.forceAutoSplitter`, default off. With the setting off,
the existing Split Quad button remains visually and behaviorally unchanged. With
the setting on, the last split button visually becomes Auto Split and invokes the
configured rows/columns shape instead of the fixed 2x2 Split Quad recipe.

### Source Inventory

| Source | Role |
|---|---|
| `docs/gdock-agent-conventions.md` | Fork-owned setting and palette id prefix rules |
| `Packages/macOS/CmuxSettings/Sources/CmuxSettings/Keys/GdockCatalogSection.swift` | Existing `gdock.*` setting catalog home |
| `Sources/GdockAutoWorkspaceGroupModeSettings.swift` | Existing gdock runtime setting accessor pattern |
| `Sources/KeyboardShortcutSettings.swift` | App shortcut action registry and current `splitQuad` default |
| `Packages/macOS/CmuxSettings/Sources/CmuxSettings/Values/ShortcutAction*.swift` | Settings package shortcut registry/defaults |
| `Sources/QuadSplitAction.swift` | Current 2x2 mutation recipe, vetoes, and tab-bar button |
| `Sources/QuadSplitAdapters.swift` | Shared Split Quad adapter/routing inventory |
| `Sources/CmuxSurfaceTabBarBuiltInAction.swift` and `Sources/CmuxConfig.swift` | Surface-tab-bar built-in action and config resolution |
| `Sources/AppDelegate.swift`, `Sources/Workspace.swift`, `Sources/GhosttyTerminalView.swift` | Shortcut/menu/context/tab-bar Split Quad entrypoints |
| `web/data/cmux.schema.json`, `web/data/cmux-shortcuts.ts`, `docs/configuration.md` | Config schema and user docs surfaces |
| `Resources/Localizable.xcstrings` | macOS string catalog; currently carries 20 locale codes |
| `cmuxTests/QuadSplit*Tests.swift` | Existing Split Quad behavioral and routing coverage |

### Current Implementation Facts

- `splitQuad` already exists in `KeyboardShortcutSettings.Action`, the settings
  package `ShortcutAction`, command palette, View menu, context menu, CLI/socket
  split path, and split-tab-bar custom action path.
- `splitQuad` is intentionally unbound by default today. A repo search found no
  current exact default Cmd+Y binding; the implementation must still add a test
  proving the new default does not collide.
- Existing Split Quad uses one shared action/adapters path. Auto Split must reuse
  that ownership/routing model instead of duplicating per-entrypoint logic.
- Remote tmux embedded panes currently filter the custom Split Quad button and
  refuse quad locally. Auto Split owes the same no-local-partial behavior.

---

## 1. Objectives & Constraints

### Objectives

- Add `gdock.autoSplitRows` and `gdock.autoSplitColumns` settings, default `2`,
  visible in Settings and supported in `cmux.json`.
- Add `gdock.forceAutoSplitter`, default `false`, visible as a toggle in Settings
  and command palette using the `palette.toggleSetting.gdock.*` prefix.
- Add an Auto Split shortcut action defaulting to Cmd+Y, editable in Settings and
  configurable in `shortcuts.bindings`.
- Implement one shared Auto Split action path that works for main panes and Dock
  panes, preserves the target pane content, fills the remaining cells with new
  terminals, and focuses the bottom-right cell by default.
- Preserve current Split Quad behavior when `gdock.forceAutoSplitter` is false.
- When `gdock.forceAutoSplitter` is true, render the last split button as Auto
  Split with a distinct icon/badge/tooltip and invoke the configured Auto Split
  shape from that button.

### Constraints

- All new fork-owned settings use the `gdock.` prefix and live in
  `GdockCatalogSection` or another `gdock.*` catalog section.
- New command-palette command ids use `palette.gdock.` for one-shot commands and
  `palette.toggleSetting.gdock.` for settings toggles.
- Rows and columns are positive integers. Runtime clamps persisted/configured
  values to `1...6`; `1 x 1` is a no-op that does not mutate the pane tree.
- A configured split creates at most 36 cells. Values outside range never crash
  and never create unbounded panes from a malformed `cmux.json`.
- The existing explicit Split Quad surfaces remain 2x2: View menu, context menu,
  `palette.terminalSplitQuad`, `splitQuad` shortcut if user-bound, and CLI/socket
  `quad` direction. Force mode affects the last split-tab-bar button only.
- If a custom surface-tab-bar configuration includes the built-in `cmux.splitQuad`
  button, its presentation/action follows `gdock.forceAutoSplitter`. If a custom
  configuration removes that button, force mode does not reinsert it.
- Auto Split must reuse the current Dock/main ownership rules: a Dock-owned
  request never falls through to the main workspace after a Dock failure.
- Remote tmux mirror/embedded lanes do not receive a local Auto Split grid.
- All user-facing strings are localized for every locale present in the touched
  `.xcstrings` catalog, not just English fallback/default text.
- New `cmuxTests/` files are wired into `cmux.xcodeproj`; `reload.sh` alone is
  not test-target validation.
- No `vendor/bonsplit` or Ghostty submodule changes are required.

### Scope Inventory

- Settings catalog/runtime accessors for three new `gdock.*` keys.
- Settings UI rows and command-palette toggle for Force Auto Splitter.
- Shortcut registries in the app target, settings package, schema, docs, and web
  shortcut data.
- Shared Auto Split mutation and adapter/routing path for main and Dock panes.
- Surface-tab-bar button presentation/action swap under force mode.
- Localized strings, docs, focused unit/integration tests, and tagged build.

### Non-Goals

- Remote tmux auto-grid support.
- Browser pane auto-grid creation.
- Arbitrary per-cell command templates.
- Workspace layout templates or saved startup layouts.
- Upstream cmux PRs.
- `vendor/bonsplit`, Ghostty, or submodule changes.

---

## 1.5 Required Toolchain

| Tool | Min Version | Install Command | Verify Command |
|------|-------------|-----------------|----------------|
| macOS | 14.0 | OS | `sw_vers -productVersion` |
| Xcode | 15.0 | App Store | `xcodebuild -version` |
| Swift | 6.0 | Bundled with Xcode | `swift --version` |
| Python 3 | 3.9 | Xcode CLT | `python3 --version` |
| stokd CLI | current | `curl -fsSL https://stokd.cloud/install \| sh` | `stokd --version` |

Working directory for all Verification Commands: gdock repo root.

Prefer `CMUX_SKIP_ZIG_BUILD=1` on tagged reloads when host Zig does not match the
GhosttyKit pin.

---

## 2. Contract

**VAL-SETTINGS-001** - Auto Split settings are gdock-owned, bounded, and user-configurable.
Surface: library
Needs: none
Behavior: Missing user config returns rows `2`, columns `2`, force `false`;
  persisted/UserDefaults and `cmux.json` values override those defaults; invalid
  row/column values are clamped to `1...6`; `1 x 1` is treated as a no-op shape.
Evidence: Focused settings tests, schema validation, Settings UI inspection, and
  `cmux.json` readback showing `gdock.autoSplitRows`, `gdock.autoSplitColumns`,
  and `gdock.forceAutoSplitter`.
Rigor: R2
Why: Behavior changes settings persistence and user-facing configuration, so it
  needs persisted evidence and independent validation beyond implementer logs.
Fail: Missing keys, wrong defaults, unbounded pane counts, or fork-owned keys
  placed under upstream prefixes.

**VAL-SHORTCUT-001** - Cmd+Y triggers Auto Split through the configurable shortcut system.
Surface: artifact
Needs: VAL-SETTINGS-001
Behavior: With no user override, Cmd+Y invokes Auto Split for the focused main or
  Dock pane; the action is visible/editable in Settings, supported by
  `shortcuts.bindings`, documented in shortcut data/docs, and has no default
  shortcut collision. User overrides and explicit unbinds take precedence.
Evidence: Shortcut registry tests, NSEvent routing tests, settings package tests,
  schema enum validation, and docs/shortcut data diff.
Rigor: R2
Why: A default keyboard shortcut is a product-wide input contract that must be
  independently validated against conflict and routing behavior.
Fail: Cmd+Y does nothing, collides with another default action, bypasses
  `KeyboardShortcutSettings`, or cannot be customized/unbound.

**VAL-AUTOSPLIT-001** - Auto Split creates the configured terminal grid through one shared path.
Surface: library
Needs: VAL-SETTINGS-001
Behavior: Auto Split replaces the focused source pane with a deterministic
  `rows x columns` terminal grid; preserves the original surface in the top-left
  cell; creates the remaining cells as new terminals; focuses the bottom-right
  cell by default; returns failure without local partial mutation for known vetoes
  and remote-tmux unsupported lanes.
Evidence: Table-driven main/Dock Auto Split tests for `1 x 2`, `2 x 1`, `2 x 2`,
  `2 x 3`, and clamped invalid values; existing Split Quad tests remain green by
  delegating 2x2 behavior through the same action family.
Rigor: R2
Why: The pane tree mutation affects live terminals and Dock ownership; validator
  coverage must prove topology and failure behavior, not just symbol presence.
Fail: Duplicate per-entrypoint algorithms, partial remote/local grids on veto,
  lost original surface, wrong focus target, or Split Quad regressions.

**VAL-FORCE-001** - Force Auto Splitter changes only the last split button into Auto Split.
Surface: artifact
Needs: VAL-SETTINGS-001, VAL-AUTOSPLIT-001
Behavior: With `gdock.forceAutoSplitter == false`, the last split-tab-bar button
  remains the current Split Quad button and produces a 2x2 grid. With
  `gdock.forceAutoSplitter == true`, that button renders as Auto Split with a
  distinct icon/badge/tooltip that reflects the configured rows/columns, and
  clicking it invokes Auto Split. Explicit Split Quad menu/palette/context/CLI
  paths continue to produce a fixed 2x2 grid.
Evidence: Button model tests, Dock appearance tests, tab-bar custom-action tests,
  and a tagged DEBUG dogfood command/screenshot showing the off/on visual and
  topology difference.
Rigor: R2
Why: This is visible UI behavior with compatibility risk for existing Split Quad
  entrypoints, so both visual state and mutation target must be validated.
Fail: Force off changes current UI, force on still creates only 2x2, explicit
  Split Quad surfaces are silently remapped, or the button text/icon is not
  accessibility/localization safe.

**VAL-I18N-DOCS-001** - User-facing strings, docs, and build gates cover the feature.
Surface: artifact
Needs: VAL-SETTINGS-001, VAL-SHORTCUT-001, VAL-FORCE-001
Behavior: New Settings rows, command-palette entries, shortcut labels, tooltips,
  context/help text, docs, schema descriptions, and web shortcut data are present
  and localized according to each touched artifact's supported locales; focused
  tests are wired and a tagged gdock build succeeds.
Evidence: Localization catalog parser output, docs/schema grep, `./scripts/lint-pbxproj-test-wiring.sh`,
  focused test commands, and `CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag gdock-auto-splitter`.
Rigor: R2
Why: Documentation and localization are user-facing contract surfaces and build
  validation must prove the app and test target both compile.
Fail: Bare English UI strings, missing locale entries, unwired tests, stale
  docs/schema, or relying on `defaultValue` as translation coverage.

---

## 3. Execution Topology

## Phase 1: Ship Auto Splitter
**Purpose:** One unattended pass that adds the settings, shared Auto Split action,
shortcut, force-button behavior, localization/docs, and validation.

### 1.1 Add gdock Auto Split settings
**Targets:** VAL-SETTINGS-001
**Dependencies:** []

**Implementation Details**
- Add `gdock.autoSplitRows`, `gdock.autoSplitColumns`, and
  `gdock.forceAutoSplitter` to `GdockCatalogSection`.
- Add a runtime accessor, tentatively `GdockAutoSplitterSettings`, mirroring the
  existing `GdockAutoWorkspaceGroupModeSettings` pattern.
- Define shared constants for row/column defaults and bounds:
  default rows `2`, default columns `2`, min `1`, max `6`.
- Add Settings UI controls: numeric steppers/inputs for rows and columns, and a
  toggle for Force Auto Splitter. Values write through the settings store, not
  ad hoc UserDefaults calls from views.
- Add command-palette toggle descriptor
  `palette.toggleSetting.gdock.forceAutoSplitter`.
- Update schema/config support so `cmux.json` recognizes the three keys.
- Failure modes: missing config returns defaults; invalid config clamps; settings
  view never mutates state from body computations.

**Acceptance Criteria**
- AC-1.1.a: With empty defaults/config, settings resolve to rows `2`, columns `2`,
  force `false`.
- AC-1.1.b: Values below `1` clamp to `1`; values above `6` clamp to `6`.
- AC-1.1.c: `cmux.json` supports `gdock.autoSplitRows`,
  `gdock.autoSplitColumns`, and `gdock.forceAutoSplitter` without unknown-key
  validation errors.
- AC-1.1.d: Settings UI exposes two numeric controls and one toggle, all
  localized and live-updating the same catalog keys.
- AC-1.1.e: New tests are present in the target; `./scripts/lint-pbxproj-test-wiring.sh`
  exits 0.

**Acceptance Tests**
- Test-1.1.a: Unit/TDD - add `AutoSplitSettingsTests` and observe red before
  implementation, then green after implementation.
- Test-1.1.b: Unit - table-driven clamp cases for rows and columns.
- Test-1.1.c: Integration - JSON settings store accepts/readbacks the new keys.
- Test-1.1.d: UI/model - Settings section exposes localized rows/columns/toggle
  descriptors and writes the catalog keys.
- Test-1.1.e: Regression - pbxproj wiring script confirms new tests compile.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'gdock\.autoSplitRows|gdock\.autoSplitColumns|gdock\.forceAutoSplitter' \
  Packages/macOS/CmuxSettings Sources web/data docs Resources
./scripts/lint-pbxproj-test-wiring.sh
CMUX_SKIP_ZIG_BUILD=1 ./scripts/test-unit.sh \
  -only-testing:cmuxTests/AutoSplitSettingsTests test
```

### 1.2 Implement the shared Auto Split action
**Targets:** VAL-AUTOSPLIT-001
**Dependencies:** ["1.1"]

**Implementation Details**
- Add a shared action/model path, tentatively `AutoSplitAction`, that accepts a
  resolved rows/columns shape and a target owner.
- Keep the existing Split Quad behavior by either delegating `2 x 2` to the new
  generalized action or by sharing a lower-level grid builder. Do not copy a
  separate mutation algorithm into each entrypoint.
- Preserve current known veto behavior from `QuadSplitAction` where applicable:
  missing target, split-disabled, canvas mode, noninteractive/transient focus,
  remote mirror/connecting/disconnected/unresolved, empty Dock source, and
  delegate restrictions.
- For a successful `rows x columns` split, preserve the original source surface
  in the top-left cell, create terminal surfaces for the remaining cells, and
  focus the bottom-right cell unless the caller requested focus restoration.
- `1 x 1` returns false/no-op without beeping from model code; UI callers decide
  whether to present feedback.
- Record enough DEBUG instrumentation for dogfood to collect before/after pane
  counts and owner kind without invoking a test-only alternate algorithm.

**Acceptance Criteria**
- AC-1.2.a: `2 x 2` Auto Split yields the same observable pane count, source
  preservation, and focus result as current Split Quad.
- AC-1.2.b: `1 x 2`, `2 x 1`, and `2 x 3` produce the expected pane counts and
  row/column topology in main workspace tests.
- AC-1.2.c: Dock-targeted Auto Split mutates Dock only and never grows the main
  workspace tree.
- AC-1.2.d: Known vetoes return failure without local partial mutation or remote
  command side effects.
- AC-1.2.e: Existing `QuadSplitActionTests`, `QuadSplitButtonTests`, and
  `QuadSplitAdapterRoutingTests` still pass.

**Acceptance Tests**
- Test-1.2.a: Unit/TDD - `AutoSplitActionTests` red before generalized action,
  green after.
- Test-1.2.b: Unit - topology table for row/column shapes and clamped values.
- Test-1.2.c: Integration - Dock ownership harness proves Dock-only mutation.
- Test-1.2.d: Regression - veto catalog asserts unchanged pane trees and no
  remote command log growth.
- Test-1.2.e: Regression - existing quad suites prove fixed 2x2 behavior remains.

**Verification Commands**
```bash
set -euo pipefail
./scripts/lint-pbxproj-test-wiring.sh
CMUX_SKIP_ZIG_BUILD=1 ./scripts/test-unit.sh \
  -only-testing:cmuxTests/AutoSplitActionTests \
  -only-testing:cmuxTests/QuadSplitActionTests \
  -only-testing:cmuxTests/QuadSplitButtonTests \
  -only-testing:cmuxTests/QuadSplitAdapterRoutingTests test
```

### 1.3 Add Cmd+Y Auto Split shortcut and command discovery
**Targets:** VAL-SHORTCUT-001
**Dependencies:** ["1.2"]

**Implementation Details**
- Add `autoSplit` to `KeyboardShortcutSettings.Action` with default
  `StoredShortcut(key: "y", command: true)`.
- Add matching settings package action/defaults, settings-visible action, schema
  enum entry, web shortcut data, and configuration docs.
- Add a default-conflict test that fails if any other public action uses Cmd+Y.
- Route the shortcut through the same shared focus path used by Auto Split's
  menu/palette/button adapters.
- Add a command-palette one-shot command `palette.gdock.autoSplit` for discovery
  if the local command-palette registry pattern supports it without adding a
  duplicate mutation path. If added, it invokes the same action as Cmd+Y.
- Explicit user overrides and unbinds in Settings or `cmux.json` take precedence
  over the default Cmd+Y.

**Acceptance Criteria**
- AC-1.3.a: Cmd+Y triggers Auto Split with default rows/columns in a focused main
  pane.
- AC-1.3.b: Cmd+Y triggers Auto Split in a focused Dock pane and does not fall
  through to main after Dock failure.
- AC-1.3.c: `shortcuts.bindings.autoSplit` can override or unbind the action.
- AC-1.3.d: No other default public shortcut equals Cmd+Y.
- AC-1.3.e: Settings/search/docs expose Auto Split as a keyboard shortcut.

**Acceptance Tests**
- Test-1.3.a: Unit/TDD - `AutoSplitShortcutRoutingTests` red before action
  registration/routing, green after.
- Test-1.3.b: Integration - Dock-focused NSEvent path produces Dock topology.
- Test-1.3.c: Settings package - `ShortcutAction.autoSplit.defaultStroke` is Cmd+Y
  and config override/unbind works.
- Test-1.3.d: Regression - iterate public actions and assert no Cmd+Y default
  collision.
- Test-1.3.e: Docs/schema/shortcut-data grep.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'autoSplit|Cmd\+Y|cmd\+y|gdock\.autoSplit' \
  Sources Packages/macOS/CmuxSettings web/data docs Resources
./scripts/lint-pbxproj-test-wiring.sh
CMUX_SKIP_ZIG_BUILD=1 ./scripts/test-unit.sh \
  -only-testing:cmuxTests/AutoSplitShortcutRoutingTests \
  -only-testing:Packages/macOS/CmuxSettings/Tests/CmuxSettingsTests/ShortcutActionNumberedDigitTests test
```

### 1.4 Force the split-tab-bar button into Auto Split mode
**Targets:** VAL-FORCE-001
**Dependencies:** ["1.1", "1.2", "1.3"]

**Implementation Details**
- Resolve the last split-tab-bar button from settings at presentation time so
  force-mode changes update without relaunch.
- With force off, preserve current button id/order/icon/tooltip/action:
  `cmux.splitQuad`, `square.split.2x2`, localized "Split Quad", fixed 2x2.
- With force on, present the last button as Auto Split with a distinct grid icon
  plus compact rows/columns badge where feasible, and a localized tooltip such as
  "Auto Split (2 rows x 3 columns)".
- When force is on and the user clicks that last button, invoke the shared Auto
  Split action with current rows/columns.
- Keep explicit Split Quad command surfaces fixed at 2x2, including View menu,
  context menu, `palette.terminalSplitQuad`, user-bound `splitQuad`, and
  CLI/socket `quad`.
- Keep remote-tmux embedded split buttons filtered so Auto Split does not appear
  as a local custom action in remote lanes.

**Acceptance Criteria**
- AC-1.4.a: Force off: default button list and Dock appearance still end with
  Split Quad and fixed 2x2 behavior.
- AC-1.4.b: Force on: the last button renders as Auto Split with row/column
  tooltip/accessibility text and invokes configured rows/columns.
- AC-1.4.c: A custom surface-tab-bar config that includes `cmux.splitQuad`
  follows force mode; a custom config that omits it is not modified.
- AC-1.4.d: Explicit Split Quad menu/palette/context/CLI paths still create
  exactly 2x2 even when force is on.
- AC-1.4.e: Remote-tmux embedded lane still exposes only supported split buttons.

**Acceptance Tests**
- Test-1.4.a: Unit/TDD - `AutoSplitForceButtonTests` red before force resolver,
  green after.
- Test-1.4.b: Integration - Workspace and Dock split-tab-bar custom action paths
  produce `rows x columns` only when force is enabled.
- Test-1.4.c: Config regression - custom button list inclusion/omission behavior.
- Test-1.4.d: Regression - explicit Split Quad adapters remain fixed 2x2.
- Test-1.4.e: Artifact/UI dogfood - tagged DEBUG app screenshot/debug payload
  shows the off/on button and topology difference.

**Verification Commands**
```bash
set -euo pipefail
./scripts/lint-pbxproj-test-wiring.sh
CMUX_SKIP_ZIG_BUILD=1 ./scripts/test-unit.sh \
  -only-testing:cmuxTests/AutoSplitForceButtonTests \
  -only-testing:cmuxTests/QuadSplitButtonTests \
  -only-testing:cmuxTests/QuadSplitAdapterRoutingTests test
```

### 1.5 Localize, document, build, and dogfood
**Targets:** VAL-I18N-DOCS-001
**Dependencies:** ["1.1", "1.2", "1.3", "1.4"]

**Implementation Details**
- Add localized strings for Settings rows, command-palette entries, shortcut
  label/description, Auto Split tooltip/accessibility text, and any failure/no-op
  text introduced by this feature.
- Update every locale already present in `Resources/Localizable.xcstrings`.
- Update `web/data/cmux-shortcuts.ts`, `web/data/cmux.schema.json`, and
  `docs/configuration.md` for the new settings and shortcut.
- Run focused tests, pbxproj wiring, localization audit, and a tagged build.
- If launching for dogfood, use `./scripts/reload.sh --tag gdock-auto-splitter`
  or `--launch`; never use an untagged app.

**Acceptance Criteria**
- AC-1.5.a: Every new `Resources/Localizable.xcstrings` key has non-empty
  localized values for all locale codes already present in the catalog.
- AC-1.5.b: `docs/configuration.md`, `web/data/cmux.schema.json`, and
  `web/data/cmux-shortcuts.ts` mention Auto Split settings/shortcut accurately.
- AC-1.5.c: `./scripts/lint-pbxproj-test-wiring.sh` exits 0.
- AC-1.5.d: Focused Auto Split and existing Quad Split tests pass with nonzero
  test execution.
- AC-1.5.e: `CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag gdock-auto-splitter`
  exits 0.

**Acceptance Tests**
- Test-1.5.a: Artifact - parse `Resources/Localizable.xcstrings` and assert new
  keys cover every locale in the catalog.
- Test-1.5.b: Docs/schema grep.
- Test-1.5.c: Regression - pbxproj test wiring.
- Test-1.5.d: Integration - focused `cmux-unit` suites.
- Test-1.5.e: Build - tagged reload script.

**Verification Commands**
```bash
set -euo pipefail
python3 - <<'PY'
import json
from pathlib import Path
catalog = json.loads(Path("Resources/Localizable.xcstrings").read_text())
all_locales = sorted({
    locale
    for entry in catalog.get("strings", {}).values()
    for locale in (entry.get("localizations") or {}).keys()
})
prefixes = (
    "settings.gdock.autoSplit",
    "settings.gdock.forceAutoSplitter",
    "shortcut.autoSplit",
    "command.gdock.autoSplit",
    "workspace.tooltip.autoSplit",
)
matched = {
    key: value
    for key, value in catalog.get("strings", {}).items()
    if key.startswith(prefixes)
}
assert matched, "no Auto Split localization keys found"
missing = []
for key, value in matched.items():
    locs = value.get("localizations") or {}
    for locale in all_locales:
        unit = (locs.get(locale) or {}).get("stringUnit") or {}
        if not unit.get("value"):
            missing.append(f"{key}:{locale}")
assert not missing, "missing localizations: " + ", ".join(missing)
print("localized keys:", len(matched), "locales:", len(all_locales))
PY
rg -n 'gdock\.autoSplitRows|gdock\.autoSplitColumns|gdock\.forceAutoSplitter|autoSplit|Cmd\+Y' \
  docs/configuration.md web/data/cmux.schema.json web/data/cmux-shortcuts.ts
./scripts/lint-pbxproj-test-wiring.sh
CMUX_SKIP_ZIG_BUILD=1 ./scripts/test-unit.sh \
  -only-testing:cmuxTests/AutoSplitSettingsTests \
  -only-testing:cmuxTests/AutoSplitActionTests \
  -only-testing:cmuxTests/AutoSplitShortcutRoutingTests \
  -only-testing:cmuxTests/AutoSplitForceButtonTests \
  -only-testing:cmuxTests/QuadSplitActionTests \
  -only-testing:cmuxTests/QuadSplitButtonTests \
  -only-testing:cmuxTests/QuadSplitAdapterRoutingTests test
CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag gdock-auto-splitter
```

---

## 4. Completion Criteria

- All `VAL-*` assertions have passing evidence recorded by the owning work item.
- TDD signal is recorded for each new behavior test: red before implementation,
  green after implementation.
- `gdock.autoSplitRows`, `gdock.autoSplitColumns`, and
  `gdock.forceAutoSplitter` are Settings-visible, schema-backed, and documented.
- Cmd+Y invokes Auto Split by default and is conflict-free/customizable.
- Auto Split produces the configured main/Dock terminal grid and preserves the
  current Split Quad 2x2 contract.
- Force mode changes the last split button only, with localized visual/accessibility
  state and no unexpected remap of explicit Split Quad commands.
- `./scripts/lint-pbxproj-test-wiring.sh`, focused tests, localization audit, and
  tagged `reload.sh --tag gdock-auto-splitter` build all exit 0.

---

## 5. Rollout & Validation

### Rollout Strategy

- Ship fork-only behind ordinary user settings; defaults are conservative:
  rows `2`, columns `2`, force `false`.
- Cmd+Y is enabled by default because current code has no exact default Cmd+Y
  binding, but the implementation must gate this with a default-conflict test.
- Existing Split Quad remains available and fixed 2x2 for compatibility.
- Use a tagged gdock build for dogfood. Do not claim landed/merged from a
  dev-complete task unless merge state is explicitly verified.

### Post-Launch Validation

- In a tagged app, verify Cmd+Y on a single main terminal creates the default 2x2
  grid and focuses the bottom-right cell.
- Change rows/columns to `2 x 3`, press Cmd+Y, and verify six cells in the
  focused main pane.
- Focus a Dock pane, press Cmd+Y, and verify Dock mutates while main pane count
  is unchanged.
- Toggle Force Auto Splitter on, verify the last split button renders as Auto
  Split, click it, and verify it uses the configured rows/columns.
- Toggle Force Auto Splitter off, verify the button returns to Split Quad and
  creates a 2x2 grid.
- Verify explicit Split Quad menu/palette/context/CLI paths remain fixed 2x2.

---

## 6. Open Questions

None. Product defaults and compatibility choices are specified here:

- Rows/columns default to `2` and clamp to `1...6`.
- Force Auto Splitter defaults off.
- Cmd+Y is the Auto Split default unless the required conflict test finds a real
  current default collision before implementation.
- Force mode remaps only the last split-tab-bar button, not every explicit Split
  Quad command surface.