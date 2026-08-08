# Phase 1: Left-rail panel kinds and placement

**Project:** Stokd Rail Panels — Left Rail Slice
**Slug:** stokd-rail-panels-first-slice
**Review Mode:** complete

## Work Items

### 1.1: Register three left-rail stokd panel kinds

**Implementation Details**

- **Landing:** fork-only.
- Extend the existing stokd rail panel identity surface (introduced by the prerequisite PRD, following existing patterns: `RightSidebarMode` and/or the `PanelType` cases used by `SidebarDockStore`) with three kinds: `stokdWorktrees`, `stokdGlobalConfig`, `stokdUsage` (exact Swift names may use existing casing conventions; raw values must be stable for persistence).
- Update `SidebarDockPlacementMatrix` (or equivalent) so `stokdWorktrees`, `stokdGlobalConfig`, `stokdUsage` are allowed on the **left** rail as sections and rejected on the right rail.
- Do not modify the existing right-rail placement entries owned by the prerequisite PRD.
- Reuse the prerequisite PRD's feature gate as-is; do not introduce a second flag.
- Provide display titles for section headers (localized keys).
- Scaffold empty or placeholder panel hosts that compile and mount without crashing (real UI in Phase 4).
- Failure modes: unknown kind in snapshot → skip + log, never crash; flag-off → kinds not offered in UI.

**Acceptance Criteria**

- AC-1.1.a: Three new stokd panel kinds exist in source with stable raw values → registry can address them.
- AC-1.1.b: Placement matrix allows all three on the left rail and rejects them on the right → `rg`/unit asserts match §0.
- AC-1.1.c: The existing gate is reused — no new beta flag key is introduced by this PRD.
- AC-1.1.d: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdRailPanelKindTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.
- AC-1.1.e: `./scripts/lint-pbxproj-test-wiring.sh` → exit 0 for any new test file.
