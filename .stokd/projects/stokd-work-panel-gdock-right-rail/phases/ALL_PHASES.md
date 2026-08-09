# Complete Phase Review

**Project:** Stokd Work Panel (gdock right rail)
**Slug:** stokd-work-panel-gdock-right-rail
**Generated:** 2026-08-08T21:38:00.614868+00:00

## Included Phases

- Phase 1: Panel kind, placement, and feature gate (`phase-01-panel-kind-placement-and-feature-gate.md`)
- Phase 2: Minimal stokd data plane (`phase-02-minimal-stokd-data-plane.md`)
- Phase 3: Work panel UI (`phase-03-work-panel-ui.md`)
- Phase 4: Default seed (`phase-04-default-seed.md`)
- Phase 5: Persistence, localization, and rollout (`phase-05-persistence-localization-and-rollout.md`)

---

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


---

# Phase 2: Minimal stokd data plane

**Project:** Stokd Work Panel (gdock right rail)
**Slug:** stokd-work-panel-gdock-right-rail
**Review Mode:** complete

## Work Items

### 2.1: stokd CLI runner

**Implementation Details**

- **Landing:** fork-only.
- Add a minimal runner that resolves the `stokd` executable in order: `STOKD_CLI_PATH` → `~/.stokd/bin/stokd` → `PATH`.
- Runs commands with an explicit working directory (the active workspace cwd), returns structured stdout/stderr/exit code; never blocks the main actor.
- **Never** write config files from the app; any future write path constructs `stokd config set` argv only.
- Failure modes: CLI missing → structured error with code 127, surfaced as panel state; never a fatal process exit.

**Acceptance Criteria**

- AC-2.1.a: Executable resolution follows `STOKD_CLI_PATH` → `~/.stokd/bin/stokd` → `PATH` against fixtures.
- AC-2.1.b: Missing executable yields a structured error (code 127), not a crash or `fatalError`.
- AC-2.1.c: No source under `Sources/Stokd/` writes to `config.yaml` via `FileManager`/`Data.write`.
- AC-2.1.d: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdCLIRunnerTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

### 2.2: Local stokd API client for tasks and projects

**Dependencies:** 2.1

**Implementation Details**

- **Landing:** fork-only.
- Add a thin REST client for the local stokd API (default `http://localhost:8167`, overridable) covering the paged task and project list endpoints used by Work.
- `URLProtocol`-testable: all requests go through an injectable `URLSession` configuration so tests run offline against fixtures.
- Decode into value types (no reference-type stores leaking below a list boundary — see the snapshot-boundary rule in `CLAUDE.md`).
- Failure modes: API down / non-2xx / decode failure → empty result plus a banner-ready error value; never fatal, never a hang without timeout.

**Acceptance Criteria**

- AC-2.2.a: Paged fixture JSON for tasks and projects decodes into the expected value types.
- AC-2.2.b: Connection refused and non-2xx responses map to a structured error, and the result is an empty list plus error — not a throw across the UI boundary.
- AC-2.2.c: Requests target the configured base URL, defaulting to `http://localhost:8167`.
- AC-2.2.d: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorkAPIClientTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.


---

# Phase 3: Work panel UI

**Project:** Stokd Work Panel (gdock right rail)
**Slug:** stokd-work-panel-gdock-right-rail
**Review Mode:** complete

## Work Items

### 3.1: Work panel view model

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


---

# Phase 4: Default seed

**Project:** Stokd Work Panel (gdock right rail)
**Slug:** stokd-work-panel-gdock-right-rail
**Review Mode:** complete

## Work Items

### 4.1: Seed Work into the right-rail tool tab strip

**Implementation Details**

- **Landing:** fork-only.
- Extend `SidebarDockSeeding` (or sibling) so that when the gate is on and the stokd seed generation has not been applied, the right rail's Tools section includes Work as a tab alongside Files, Find, Vault — order Files, Find, Vault, Work unless the user has already customized the order.
- Idempotent marker (seed generation int / `stokdPanelsSeedApplied`) shared with the sibling left-rail PRD so re-open never re-inserts duplicates or resets user layout.
- Flag-off: the seed path no-ops for stokd kinds.
- Left rail is not modified by this PRD's seed.
- Failure modes: partial seed failure leaves non-stokd rails intact; log and continue.

**Acceptance Criteria**

- AC-4.1.a: Seeding an empty registry with the flag on yields right-rail tools Files, Find, Vault, Work in that order.
- AC-4.1.b: A second seed call does not duplicate the Work tab and does not reset a customized order.
- AC-4.1.c: Flag off → seed introduces no stokd kinds.
- AC-4.1.d: Seeding does not add or reorder any left-rail section.
- AC-4.1.e: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorkPanelSeedTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.


---

# Phase 5: Persistence, localization, and rollout

**Project:** Stokd Work Panel (gdock right rail)
**Slug:** stokd-work-panel-gdock-right-rail
**Review Mode:** complete

## Work Items

### 5.1: Snapshot persistence for stokd rail membership

**Implementation Details**

- **Landing:** fork-only.
- Persist right-rail tool membership, order, and selected tab including `stokdWork` using **additive optional** snapshot fields only — **never** bump `SessionSnapshotSchema.currentVersion` and never add a `SessionWorkspaceLayoutSnapshot` case.
- Round-trip: seed layout → encode → decode → equal membership and selection.
- These rules are the contract the sibling left-rail PRD reuses for its sections.
- Failure modes: unknown future kind → skip; corrupt optional → fall back to the default seed once.

**Acceptance Criteria**

- AC-5.1.a: Round-trip of a Work-inclusive layout preserves membership, order, and selected tab.
- AC-5.1.b: `SessionSnapshotSchema.currentVersion` is unchanged from the pre-phase baseline (remains 1).
- AC-5.1.c: A snapshot containing an unknown stokd kind decodes with that entry skipped and no crash.
- AC-5.1.d: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorkPanelPersistenceTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

### 5.2: Localization audit and dogfood gate

**Dependencies:** 5.1

**Implementation Details**

- **Landing:** fork-only.
- Every new user-facing string uses `String(localized:)` with en+ja entries in `Resources/Localizable.xcstrings`, `state == translated`, and `ja != en` for non-identical natural text. Covered surfaces: tool tab title, empty state, error state, any beta-settings row added in 1.2.
- Palette/debug can open and focus Work through the same invoker path as other rail tools.
- Tagged dogfood: `CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag stokd-work-panel` builds; with the flag on, a cold window matches §0.
- Bonsplit clean: `git -C vendor/bonsplit status --porcelain` empty; pinned SHA unchanged.

**Acceptance Criteria**

- AC-5.2.a: Every new Work string key exists in both en and ja with `state == translated`.
- AC-5.2.b: No bare English literal in new Work Swift sources' `Text(`/`Button(`/alert titles.
- AC-5.2.c: `./scripts/lint-pbxproj-test-wiring.sh` → exit 0.
- AC-5.2.d: Tagged reload compiles → exit 0 (or, where the environment cannot build the app, all suites in this PRD green with that substitution recorded in the session output).
- AC-5.2.e: `git -C vendor/bonsplit status --porcelain` empty and `git -C vendor/bonsplit rev-parse HEAD` equals the pin `48643102d6b68400069429bd43c15d7bda2b00a1`.

