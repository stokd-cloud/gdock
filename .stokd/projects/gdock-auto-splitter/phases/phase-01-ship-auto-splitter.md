# Phase 1: Ship Auto Splitter

**Project:** Gdock Auto Splitter
**Slug:** gdock-auto-splitter
**Review Mode:** complete

## Work Items

### 1.1: Add gdock Auto Split settings

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
- force `false`.
- AC-1.1.b: Values below `1` clamp to `1`; values above `6` clamp to `6`.
- AC-1.1.c: `cmux.json` supports `gdock.autoSplitRows`,
- `gdock.autoSplitColumns`, and `gdock.forceAutoSplitter` without unknown-key
- validation errors.
- AC-1.1.d: Settings UI exposes two numeric controls and one toggle, all
- localized and live-updating the same catalog keys.
- AC-1.1.e: New tests are present in the target; `./scripts/lint-pbxproj-test-wiring.sh`
- exits 0.

### 1.2: Implement the shared Auto Split action

**Dependencies:** 1.1

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
- preservation, and focus result as current Split Quad.
- AC-1.2.b: `1 x 2`, `2 x 1`, and `2 x 3` produce the expected pane counts and
- row/column topology in main workspace tests.
- AC-1.2.c: Dock-targeted Auto Split mutates Dock only and never grows the main
- workspace tree.
- AC-1.2.d: Known vetoes return failure without local partial mutation or remote
- command side effects.
- AC-1.2.e: Existing `QuadSplitActionTests`, `QuadSplitButtonTests`, and
- `QuadSplitAdapterRoutingTests` still pass.

### 1.3: Add Cmd+Y Auto Split shortcut and command discovery

**Dependencies:** 1.2

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
- pane.
- AC-1.3.b: Cmd+Y triggers Auto Split in a focused Dock pane and does not fall
- through to main after Dock failure.
- AC-1.3.c: `shortcuts.bindings.autoSplit` can override or unbind the action.
- AC-1.3.d: No other default public shortcut equals Cmd+Y.
- AC-1.3.e: Settings/search/docs expose Auto Split as a keyboard shortcut.

### 1.4: Force the split-tab-bar button into Auto Split mode

**Dependencies:** 1.1, 1.2, 1.3

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
- Split Quad and fixed 2x2 behavior.
- AC-1.4.b: Force on: the last button renders as Auto Split with row/column
- tooltip/accessibility text and invokes configured rows/columns.
- AC-1.4.c: A custom surface-tab-bar config that includes `cmux.splitQuad`
- follows force mode; a custom config that omits it is not modified.
- AC-1.4.d: Explicit Split Quad menu/palette/context/CLI paths still create
- exactly 2x2 even when force is on.
- AC-1.4.e: Remote-tmux embedded lane still exposes only supported split buttons.

### 1.5: Localize, document, build, and dogfood

**Dependencies:** 1.1, 1.2, 1.3, 1.4

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
- localized values for all locale codes already present in the catalog.
- AC-1.5.b: `docs/configuration.md`, `web/data/cmux.schema.json`, and
- `web/data/cmux-shortcuts.ts` mention Auto Split settings/shortcut accurately.
- AC-1.5.c: `./scripts/lint-pbxproj-test-wiring.sh` exits 0.
- AC-1.5.d: Focused Auto Split and existing Quad Split tests pass with nonzero
- test execution.
- AC-1.5.e: `CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag gdock-auto-splitter`
- exits 0.

