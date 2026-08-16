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
- Decide and implement **one** gate, documented in a code comment, and treat it as the gate for **all** future stokd rail panels:
  - **Option A:** reuse `sidebar.beta.dock.enabled` (stokd panels appear only when rails are on), or
  - **Option B:** dedicated `gdock.sidebar.beta.stokdPanels.enabled`, default false, still requiring rails on to mount.
- Default **off**. Flag-off: no stokd kind in seed, palette, or tab strip.
- Per fork conventions (`CLAUDE.md`), any **new** setting id must use the `gdock.` prefix and live in `GdockCatalogSection`; reusing the grandfathered upstream `sidebar.beta.dock.enabled` key is the only exception.
- Surface in Beta Features settings if Option B (localized en+ja).
- Failure modes: missing key → false; never throw from a settings read.

**Acceptance Criteria**

- AC-1.2.a: Key absent from UserDefaults → stokd panels disabled.
- AC-1.2.b: Enable path returns true only when the key is set true (and the rail gate is satisfied under Option B).
- AC-1.2.c: If Option B is chosen, the new setting id begins with `gdock.` and is registered in `GdockCatalogSection`.
- AC-1.2.d: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdRailPanelFlagTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

