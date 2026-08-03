# Phase 1: Panel kinds, placement, and feature gate

**Project:** Stokd Rail Panels — First Slice
**Slug:** stokd-rail-panels-first-slice
**Review Mode:** complete

## Work Items

### 1.1: Register four stokd rail panel kinds

**Implementation Details**

- **Landing:** fork-only.
- Extend the rail panel identity surface (match existing patterns: `RightSidebarMode` and/or dedicated left-rail panel kinds / `PanelType` cases used by `SidebarDockStore`) with four kinds: `stokdWork`, `stokdWorktrees`, `stokdGlobalConfig`, `stokdUsage` (exact Swift names may use existing casing conventions; raw values must be stable for persistence).
- Update `SidebarDockPlacementMatrix` (or equivalent) so:
  - `stokdWork` is allowed on the **right** rail (tool-tab strip).
  - `stokdWorktrees`, `stokdGlobalConfig`, `stokdUsage` are allowed on the **left** rail as sections.
- Provide display titles for section headers / tabs (localized keys).
- Scaffold empty or placeholder panel hosts that compile and mount without crashing (real UI in Phase 4).
- Failure modes: unknown kind in snapshot → skip + log, never crash; flag-off → kinds not offered in UI.

**Acceptance Criteria**

- AC-1.1.a: Four stokd panel kinds exist in source with stable raw values → registry can address them.
- AC-1.1.b: Placement matrix allows Work on right and the other three on left → `rg`/unit asserts match §0.
- AC-1.1.c: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdRailPanelKindTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.
- AC-1.1.d: `./scripts/lint-pbxproj-test-wiring.sh` → exit 0 for any new test file.

### 1.2: Feature gate for stokd rail panels

**Implementation Details**

- **Landing:** fork-only.
- Decide and implement one gate (document choice in code comment):
  - **Option A:** reuse `sidebar.beta.dock.enabled` (stokd panels only appear when rails are on), or
  - **Option B:** dedicated `sidebar.beta.stokdPanels.enabled` default false, still requiring rails on to mount.
- Default **off**. Flag-off: no stokd kinds in seed, palette, or tab strip.
- Surface in Beta Features settings if Option B (localized).
- Failure modes: missing key → false; never throw from settings read.

**Acceptance Criteria**

- AC-1.2.a: Default UserDefaults (key absent) → stokd panels disabled.
- AC-1.2.b: Unit test proves enable path returns true only when key set true (and rail gate satisfied if Option B).
- AC-1.2.c: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdRailPanelFlagTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

