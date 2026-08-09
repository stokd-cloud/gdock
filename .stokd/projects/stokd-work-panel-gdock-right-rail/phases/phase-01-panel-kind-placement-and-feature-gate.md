# Phase 1: Panel kind, placement, and feature gate

**Project:** Stokd Work Panel (gdock right rail)
**Slug:** stokd-work-panel-gdock-right-rail
**Review Mode:** complete

## Work Items

### 1.1: Register the stokdWork rail panel kind

**Implementation Details**

- **Landing:** fork-only.
- Extend the rail panel identity surface (match existing patterns: `RightSidebarMode` and/or the `PanelType` cases used by `SidebarDockStore`) with the kind `stokdWork`. Exact Swift casing follows existing conventions; the **raw value must be stable** because it is persisted.
- Update `SidebarDockPlacementMatrix` (or equivalent) so `stokdWork` is allowed on the **right** rail (tool-tab strip) and disallowed on the left rail.
- Provide a display title for the tool tab via a localized key.
- Scaffold an empty placeholder panel host that compiles and mounts without crashing (real UI in Phase 3).
- Leave room for the sibling PRD's left-rail kinds: do not close the kind surface to further cases, and do not name the enum/registry `…WorkOnly…`.
- Failure modes: unknown kind in a persisted snapshot → skip + log, never crash; flag-off → kind is not offered in UI.

**Acceptance Criteria**

- AC-1.1.a: `stokdWork` exists in source with a stable raw value → the rail registry can address it.
- AC-1.1.b: Placement matrix allows `stokdWork` on the right rail and rejects it on the left → unit asserts match §0.
- AC-1.1.c: Decoding a snapshot containing an unrecognized stokd kind string does not crash and drops only that entry.
- AC-1.1.d: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorkPanelKindTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.
- AC-1.1.e: `./scripts/lint-pbxproj-test-wiring.sh` → exit 0 for the new test file.

### 1.2: Feature gate for stokd rail panels

**Dependencies:** 1.1

**Implementation Details**

- **Landing:** fork-only.
- Reuse the grandfathered upstream `sidebar.beta.dock.enabled` key and expose one shared enablement
  helper as the gate for **all** future stokd rail panels.
- Default **off**. Flag-off: no stokd kind in seed, palette, or tab strip.
- Introduce no new setting id; any future dedicated setting remains subject to the `gdock.` prefix
  and `GdockCatalogSection` convention.
- Failure modes: missing key → false; never throw from a settings read.

**Acceptance Criteria**

- AC-1.2.a: Key absent from UserDefaults → stokd panels disabled.
- AC-1.2.b: Shared enablement returns true only when `sidebar.beta.dock.enabled` is true.
- AC-1.2.c: No new stokd-panels setting id is registered outside the existing rail gate.
- AC-1.2.d: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdRailPanelFlagTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

