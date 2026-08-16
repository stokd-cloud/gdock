# Phase 3: Work panel UI

**Project:** Stokd Work Panel (gdock right rail)
**Slug:** stokd-work-panel-gdock-right-rail
**Review Mode:** complete

## Work Items

### 3.1: Work panel view model

**Dependencies:** 1.1, 2.2

**Implementation Details**

- **Landing:** fork-only.
- View model owns load / reload / filter / sort for tasks + projects scoped to the active workspace context.
- Exposes immutable row snapshots to the view (no store references below the list boundary).
- No state mutation inside view-body computations; refreshes happen in load completions or property observers.
- Failure modes: API down → `empty(error:)` state carrying user-facing text; empty result → distinct empty state; stale in-flight load is superseded by request id, never applied out of order.

**Acceptance Criteria**

- AC-3.1.a: Loading fixture data produces the expected ordered row snapshots for tasks and projects.
- AC-3.1.b: Filter and sort produce deterministic ordering for a fixed fixture set.
- AC-3.1.c: An error response yields an error state with non-empty user-facing text and zero rows.
- AC-3.1.d: An out-of-order late response for a superseded request id is discarded.
- AC-3.1.e: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorkPanelViewModelTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

### 3.2: Work panel view and rail mounting

**Dependencies:** 3.1

**Implementation Details**

- **Landing:** fork-only.
- Implement the SwiftUI body for Work and wire it as right-rail tool tab content for `stokdWork`, replacing the Phase 1 placeholder.
- Rows carry value snapshots plus closure action bundles only — reference pattern: `IndexSectionActions` / `SectionGapActions` in `Sources/SessionIndexView.swift`.
- Actor surfaces (command palette, tab strip, section menu) go through the existing `SidebarDockActionInvoker` → `SidebarDockCommand.perform` path — one shared action path, no store-only reachability, per the shared-behavior policy.
- Failure modes: API down → empty state with error text; no data → empty state; neither may render blank chrome.

**Acceptance Criteria**

- AC-3.2.a: Mounting `stokdWork` with a fixture-backed view model renders a non-empty view hierarchy.
- AC-3.2.b: Error and empty states each render identifiable, non-blank content.
- AC-3.2.c: Every entrypoint that focuses/opens Work resolves through `SidebarDockActionInvoker`/`SidebarDockCommand` — no duplicated open logic.
- AC-3.2.d: No type below the Work row list holds an `ObservableObject`/`@Observable` reference (snapshot-boundary rule).
- AC-3.2.e: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorkPanelViewTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

