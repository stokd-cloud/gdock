# All Phases

**Project:** Stokd Rail Panels — Left Rail Slice
**Slug:** stokd-rail-panels-first-slice
**Review Mode:** complete

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

# Phase 2: Default seed layout

**Project:** Stokd Rail Panels — Left Rail Slice
**Slug:** stokd-rail-panels-first-slice
**Review Mode:** complete

## Work Items

### 2.1: Seed the left-rail stack

**Implementation Details**

- **Landing:** fork-only.
- Extend `SidebarDockSeeding` (or sibling) so when the gate is on and the stokd seed generation is not yet applied:
  - **Left:** keep/ensure the workspaces section at top; create sections Global Config, Worktrees, Usage in that vertical order (Usage bottom).
- Reuse the prerequisite PRD's idempotent marker (seed generation int / `stokdPanelsSeedApplied`) — advance it rather than adding a second marker — so re-open does not re-insert duplicates or reset user layout.
- Do not touch right-rail seeding; the Work tab remains owned by the prerequisite PRD.
- Flag-off: seed path no-ops for stokd kinds.
- Failure modes: partial seed failure leaves non-stokd rails intact; log and continue.

**Acceptance Criteria**

- AC-2.1.a: Unit seed of an empty registry with the flag on produces left order Workspaces → Global Config → Worktrees → Usage.
- AC-2.1.b: Second seed call does not duplicate stokd sections.
- AC-2.1.c: Flag off → seed does not introduce stokd kinds.
- AC-2.1.d: Seeding leaves the right-rail tool tab strip byte-identical to its pre-seed state.
- AC-2.1.e: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdRailPanelSeedTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

# Phase 3: Config and usage data access

**Project:** Stokd Rail Panels — Left Rail Slice
**Slug:** stokd-rail-panels-first-slice
**Review Mode:** complete

## Work Items

### 3.1: Config schema access and usage ingest

**Implementation Details**

- **Landing:** fork-only.
- **Reuse** the stokd CLI runner from `docs/stokd-work-panel.prd.md` (executable resolution, working directory, structured errors). Do not add a second runner or a second executable-resolution path.
- Config schema read path for Global Config: prefer `stokd config schema --json` via that runner; layered value reads may parse YAML layers read-only.
- Config write path: construct `stokd config set …` argv only. **Never** write config files from the app.
- Usage ingest: prefer watching provider stores over a 60s full poll; accept a thin poll as an interim if the watch lands in this phase's last item — document the chosen path in code.
- Failure modes: CLI missing → the runner's structured error (code 127) surfaced as panel state; no stores → empty/unobserved state; never a fatal process exit.

**Acceptance Criteria**

- AC-3.1.a: Config schema fixture JSON decodes into the render model used by Phase 4.
- AC-3.1.b: Usage ingest maps fixture provider store records into aggregate-ready values.
- AC-3.1.c: The config write path only constructs CLI argv — no `FileManager`/`Data.write` to `config.yaml`.
- AC-3.1.d: `rg` shows exactly one stokd executable-resolution implementation in `Sources/` (the prerequisite's).
- AC-3.1.e: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdConfigUsageDataTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

# Phase 4: Panel UI implementations

**Project:** Stokd Rail Panels — Left Rail Slice
**Slug:** stokd-rail-panels-first-slice
**Review Mode:** complete

## Work Items

### 4.1: Worktrees panel (left section)

**Implementation Details**

- **Landing:** fork-only.
- Implement Worktrees section: inventory from Git/local worktree discovery for the active repo (document source of truth in code; do not hard-depend only on incomplete CLI if git is authoritative).
- Rows: path, branch, dirty; open/reveal minimum; land/review actions optional for this slice if unsafe.
- Failure modes: non-git cwd → empty + explanation.

**Acceptance Criteria**

- AC-4.1.a: Fixture repo produces expected worktree rows in unit tests.
- AC-4.1.b: Non-git path yields empty state without crash.
- AC-4.1.c: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorktreesPanelTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

### 4.2: Global Config panel (left section)

**Implementation Details**

- **Landing:** fork-only.
- Schema-driven settings UI from CLI schema descriptor; scope from active window focused workspace cwd.
- Show layered provenance when cheap; writes only through CLI writer with explicit scope (default workspace; global requires deliberate switch).
- Failure modes: CLI missing → “stokd CLI not found” state; unknown field types render read-only.

**Acceptance Criteria**

- AC-4.2.a: Schema fixture renders ≥1 field group.
- AC-4.2.b: Write path unit test asserts `stokd config set` argv, never FileManager write to yaml.
- AC-4.2.c: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdGlobalConfigPanelTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

### 4.3: Usage panel (left section, bottom)

**Implementation Details**

- **Landing:** fork-only.
- Per provider → per model token/cost breakdown for supported timespans.
- Prefer file-watch/incremental ingest; include reasoning tokens and restart-safe provider dedupe when data model supports it; mark unmeasured cache columns unavailable rather than fake zeros.
- Failure modes: no stores → configured-but-unobserved rows or empty state, not crash.

**Acceptance Criteria**

- AC-4.3.a: Fixture usage records aggregate into provider/model rows.
- AC-4.3.b: Missing cache columns do not display as measured zero when unavailable.
- AC-4.3.c: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdUsagePanelTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

# Phase 5: Persistence, localization, and rollout

**Project:** Stokd Rail Panels — Left Rail Slice
**Slug:** stokd-rail-panels-first-slice
**Review Mode:** complete

## Work Items

### 5.1: Snapshot persistence for stokd rail membership

**Implementation Details**

- **Landing:** fork-only.
- Persist left-rail section membership, order, collapse, and extents for the three new kinds using the **additive optional** snapshot rules established by the prerequisite PRD — **never** bump `SessionSnapshotSchema.currentVersion` and never add a `SessionWorkspaceLayoutSnapshot` case. Right-rail tab selection persistence is already covered by the prerequisite PRD.
- Round-trip unit test: seed layout → encode → decode → equal membership.
- Failure modes: unknown future kind → skip; corrupt optional → default seed once.

**Acceptance Criteria**

- AC-5.1.a: Round-trip unit test exit 0 for a layout including the three left-rail stokd sections.
- AC-5.1.b: `rg` shows no increment of `SessionSnapshotSchema.currentVersion` in the change set relative to pre-phase baseline (version remains 1).
- AC-5.1.c: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdRailPanelPersistenceTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

### 5.2: Localization audit and dogfood gate

**Implementation Details**

- **Landing:** fork-only.
- Every new user-facing string uses `String(localized:)` with en+ja entries `state == translated` and `ja != en` for non-identical natural text.
- Actor wiring: palette/debug can open/focus each stokd panel via the same invoker path as other rail tools.
- Tagged dogfood: `CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag stokd-left-rail-panels` builds; with flag on, cold window matches the §0 left-rail layout.
- Bonsplit clean: `git -C vendor/bonsplit status --porcelain` empty; pinned SHA unchanged.

**Acceptance Criteria**

- AC-5.2.a: Localization keys for the Worktrees, Global Config, and Usage section titles exist in en and ja.
- AC-5.2.b: `./scripts/lint-pbxproj-test-wiring.sh` → exit 0.
- AC-5.2.c: Tagged reload compiles (or unit suites above all green if CI skips full app) → exit 0.
- AC-5.2.d: `git -C vendor/bonsplit rev-parse HEAD` equals pin `48643102d6b68400069429bd43c15d7bda2b00a1` (or current PRD pin if rail PRD updates it — do not change bonsplit in this project).
