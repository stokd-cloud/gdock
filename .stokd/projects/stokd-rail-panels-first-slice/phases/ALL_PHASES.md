# Complete Phase Review

**Project:** Stokd Rail Panels — First Slice
**Slug:** stokd-rail-panels-first-slice
**Generated:** 2026-08-03T03:16:51.787362+00:00

## Included Phases

- Phase 1: Panel kinds, placement, and feature gate (`phase-01-panel-kinds-placement-and-feature-gate.md`)
- Phase 2: Default seed layout (`phase-02-default-seed-layout.md`)
- Phase 3: Minimal data plane (`phase-03-minimal-data-plane.md`)
- Phase 4: Panel UI implementations (`phase-04-panel-ui-implementations.md`)
- Phase 5: Persistence, localization, and rollout (`phase-05-persistence-localization-and-rollout.md`)

---

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


---

# Phase 2: Default seed layout

**Project:** Stokd Rail Panels — First Slice
**Slug:** stokd-rail-panels-first-slice
**Review Mode:** complete

## Work Items

### 2.1: Seed left stack and right Work tab

**Implementation Details**

- **Landing:** fork-only.
- Extend `SidebarDockSeeding` (or sibling) so when gate is on and stokd seed generation is not yet applied:
  - **Left:** keep/ensure workspaces section at top; create sections Global Config, Worktrees, Usage in that vertical order (Usage bottom).
  - **Right:** ensure Tools section includes Work as a tab with Files, Find, Vault (order: Files, Find, Vault, Work unless existing user order already customized).
- Idempotent marker (e.g. seed generation int / “stokdPanelsSeedApplied”) so re-open does not re-insert duplicates or reset user layout.
- Flag-off: seed path no-ops for stokd kinds.
- Failure modes: partial seed failure leaves non-stokd rails intact; log and continue.

**Acceptance Criteria**

- AC-2.1.a: Unit seed of empty registry with flag on produces left order Workspaces → Global Config → Worktrees → Usage and right tools including Work.
- AC-2.1.b: Second seed call does not duplicate stokd sections/tabs.
- AC-2.1.c: Flag off → seed does not introduce stokd kinds.
- AC-2.1.d: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdRailPanelSeedTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.


---

# Phase 3: Minimal data plane

**Project:** Stokd Rail Panels — First Slice
**Slug:** stokd-rail-panels-first-slice
**Review Mode:** complete

## Work Items

### 3.1: CLI runner and API client stubs for panels

**Implementation Details**

- **Landing:** fork-only.
- Add a minimal runner that resolves `stokd` executable (`STOKD_CLI_PATH` → `~/.stokd/bin/stokd` → PATH) and runs commands with an explicit working directory (active workspace cwd).
- Add thin REST client for local stokd API (default `http://localhost:8167`) for Work list endpoints (tasks/projects paged) — URLProtocol-testable.
- Config schema read path for Global Config: prefer `stokd config schema --json` when available; layered value reads may parse YAML layers read-only.
- Usage ingest: prefer watching provider stores over 60s full poll; accept thin poll as interim if watch lands in same phase’s last item — document chosen path.
- **Never** write config files from the app; writes only via `stokd config set`.
- Failure modes: CLI missing → structured error code 127; API down → empty list + banner-ready error; never fatal process exit.

**Acceptance Criteria**

- AC-3.1.a: Unit — executable resolution order with fixtures.
- AC-3.1.b: Unit — Work API decoder accepts paged fixture JSON.
- AC-3.1.c: Unit — config write path only constructs CLI argv (no FileManager write to config.yaml).
- AC-3.1.d: `swift test` or unit suite for the data plane target → exit 0.


---

# Phase 4: Panel UI implementations

**Project:** Stokd Rail Panels — First Slice
**Slug:** stokd-rail-panels-first-slice
**Review Mode:** complete

## Work Items

### 4.1: Work panel (right rail tab)

**Implementation Details**

- **Landing:** fork-only.
- Implement Work panel UI: list tasks + projects for active workspace context; filter/sort consistent with current stokd API shapes.
- Wire as right-rail tool tab content for `stokdWork`.
- Actor surfaces (palette / section menu if applicable) go through existing `SidebarDockActionInvoker` → `SidebarDockCommand.perform` patterns — no store-only-only reachability.
- Failure modes: API down → empty state with error text; offline-friendly when fixtures allow.

**Acceptance Criteria**

- AC-4.1.a: Mounting `stokdWork` renders a non-empty view hierarchy for fixture-backed store.
- AC-4.1.b: Unit/view-model tests cover list mapping for tasks and projects.
- AC-4.1.c: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorkPanelTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

### 4.2: Worktrees panel (left section)

**Implementation Details**

- **Landing:** fork-only.
- Implement Worktrees section: inventory from Git/local worktree discovery for the active repo (document source of truth in code; do not hard-depend only on incomplete CLI if git is authoritative).
- Rows: path, branch, dirty; open/reveal minimum; land/review actions optional for this slice if unsafe.
- Failure modes: non-git cwd → empty + explanation.

**Acceptance Criteria**

- AC-4.2.a: Fixture repo produces expected worktree rows in unit tests.
- AC-4.2.b: Non-git path yields empty state without crash.
- AC-4.2.c: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorktreesPanelTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

### 4.3: Global Config panel (left section)

**Implementation Details**

- **Landing:** fork-only.
- Schema-driven settings UI from CLI schema descriptor; scope from active window focused workspace cwd.
- Show layered provenance when cheap; writes only through CLI writer with explicit scope (default workspace; global requires deliberate switch).
- Failure modes: CLI missing → “stokd CLI not found” state; unknown field types render read-only.

**Acceptance Criteria**

- AC-4.3.a: Schema fixture renders ≥1 field group.
- AC-4.3.b: Write path unit test asserts `stokd config set` argv, never FileManager write to yaml.
- AC-4.3.c: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdGlobalConfigPanelTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

### 4.4: Usage panel (left section, bottom)

**Implementation Details**

- **Landing:** fork-only.
- Per provider → per model token/cost breakdown for supported timespans.
- Prefer file-watch/incremental ingest; include reasoning tokens and restart-safe provider dedupe when data model supports it; mark unmeasured cache columns unavailable rather than fake zeros.
- Failure modes: no stores → configured-but-unobserved rows or empty state, not crash.

**Acceptance Criteria**

- AC-4.4.a: Fixture usage records aggregate into provider/model rows.
- AC-4.4.b: Missing cache columns do not display as measured zero when unavailable.
- AC-4.4.c: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdUsagePanelTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.


---

# Phase 5: Persistence, localization, and rollout

**Project:** Stokd Rail Panels — First Slice
**Slug:** stokd-rail-panels-first-slice
**Review Mode:** complete

## Work Items

### 5.1: Snapshot persistence for stokd rail membership

**Implementation Details**

- **Landing:** fork-only.
- Persist section membership, order, collapse, extents, and right-rail tab selection including stokd kinds using **additive optional** snapshot fields only — **never** bump `SessionSnapshotSchema.currentVersion` and never add a `SessionWorkspaceLayoutSnapshot` case.
- Round-trip unit test: seed layout → encode → decode → equal membership.
- Failure modes: unknown future kind → skip; corrupt optional → default seed once.

**Acceptance Criteria**

- AC-5.1.a: Round-trip unit test exit 0 for stokd-inclusive layout.
- AC-5.1.b: `rg` shows no increment of `SessionSnapshotSchema.currentVersion` in the change set relative to pre-phase baseline (version remains 1).
- AC-5.1.c: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdRailPanelPersistenceTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

### 5.2: Localization audit and dogfood gate

**Implementation Details**

- **Landing:** fork-only.
- Every new user-facing string uses `String(localized:)` with en+ja entries `state == translated` and `ja != en` for non-identical natural text.
- Actor wiring: palette/debug can open/focus each stokd panel via the same invoker path as other rail tools.
- Tagged dogfood: `CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag stokd-rail-panels` builds; with flag on, cold window matches §0 layout.
- Bonsplit clean: `git -C vendor/bonsplit status --porcelain` empty; pinned SHA unchanged.

**Acceptance Criteria**

- AC-5.2.a: Localization keys for stokd panel titles exist in en and ja.
- AC-5.2.b: `./scripts/lint-pbxproj-test-wiring.sh` → exit 0.
- AC-5.2.c: Tagged reload compiles (or unit suites above all green if CI skips full app) → exit 0.
- AC-5.2.d: `git -C vendor/bonsplit rev-parse HEAD` equals pin `48643102d6b68400069429bd43c15d7bda2b00a1` (or current PRD pin if rail PRD updates it — do not change bonsplit in this project).

