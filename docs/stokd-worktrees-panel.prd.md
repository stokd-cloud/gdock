# PRD: Stokd Worktrees Panel (gdock left rail)

## 0. Source Context

**Derived From:** Sliced out of `.stokd/projects/stokd-rail-panels-first-slice/prd.md` on 2026-08-09 — the remaining three-panel PRD is being split so Worktrees, Global Config, and Usage can land independently.
**Feature Name:** Stokd Worktrees Panel
**PRD Owner:** Brian Stoker
**Last Updated:** 2026-08-09
**Repository:** `stokd-cloud/ghostty-dock` (fork of `manaflow-ai/cmux`), branch `main`
**Landing:** fork-only on `main`
**Prerequisite:** `docs/stokd-work-panel.prd.md` — the Work panel PRD **owns** the shared foundation (stokd rail panel-kind surface, the `sidebar.beta.dock.enabled` gate for stokd panels, the stokd CLI runner, and the additive snapshot persistence rules). This PRD consumes that foundation unchanged and re-specifies none of it.

### Summary

Port the **Worktrees** surface from the stokd VS Code extension into gdock as a **left-rail section**, hosted on the existing rail system behind the same beta gate as Work. The section lists the git worktrees of the active workspace's repository — path, branch, and dirty state — and can open or reveal one.

Git is the source of truth for worktree inventory; the stokd CLI is consulted only for the enrichment it can add (task/project association), never as the sole inventory source. That keeps the panel useful in any repo, including one stokd has never seen.

### Source inventory (read-only)

| Source | Role |
|---|---|
| `docs/stokd-work-panel.prd.md` | **Prerequisite PRD** — panel-kind surface, gate, CLI runner, snapshot rules |
| `stokd-cloud/mono` → `docs/port-stokd-panels-to-ghostty-dock.prd.md` | Behavior inventory for Worktrees |
| `.stokd/projects/dockable-sidebar-spaces-and-quad-split/prd.md` | Authoritative rail substrate (sections, collapse, resize, persistence) |
| Live `main` | `Sources/Sidebar/SidebarDock*`, `Sources/Stokd/` |

### Default layout (load-bearing)

```
LEFT RAIL
┌─────────────────────────┐
│ Section: Workspaces     │  (existing, stays on top)
├─────────────────────────┤
│ …stokd rank 1…          │  (Global Config, when landed)
├─────────────────────────┤
│ Section: Worktrees      │  ← this PRD, stokd rank 2
├─────────────────────────┤
│ …stokd rank 3…          │  (Usage, when landed)
└─────────────────────────┘
```

Worktrees seeds at **stokd section rank 2**, inserted below the workspaces section and ordered against any other stokd sections by rank. The three left-rail panels land independently, so seeding is rank-ordered rather than positional: any landing order composes into the same documented layout.

## 1. Objectives & Constraints

### Objectives

- Register the `stokdWorktrees` panel kind as an addition to the existing stokd kind surface, allowed on the left rail and rejected on the right.
- Discover the active repository's worktrees from git, with a documented, testable source of truth.
- Render path, branch, and dirty state per row, with open/reveal actions routed through the shared SidebarDock action path.
- Seed the section once at stokd rank 2 without disturbing user layout or other stokd sections.
- Persist section membership, order, collapse, and extent using the prerequisite's additive snapshot rules.
- Ship localized en+ja strings and a tagged dogfood build behind the existing beta gate.

### Constraints

- **Fork-only** on `stokd-cloud/ghostty-dock` `main`.
- **Prerequisite:** `docs/stokd-work-panel.prd.md` must land first; its panel-kind surface, beta gate, CLI runner, and snapshot rules are consumed unchanged and never redefined here.
- **Left rail only** — no right-rail or tool-tab-strip changes.
- **Rail host only** — no freeform canvas dock-anywhere.
- **Beta-gated**, default off, reusing `sidebar.beta.dock.enabled`; no new flag.
- Git commands run through the prerequisite's process boundary off the main actor — no synchronous shell-out from a view body.
- Destructive worktree operations (remove, prune, force-land) are out of scope for this release; the panel is read + open only.
- All user-facing strings localized en+ja via `String(localized:)` / `Resources/Localizable.xcstrings`.
- New tests wired into `cmux.xcodeproj`; `./scripts/lint-pbxproj-test-wiring.sh` green.
- SwiftUI snapshot-boundary and no-state-mutation-in-body rules apply (see `CLAUDE.md`).
- Bonsplit submodule SHA unchanged and worktree clean.

### Scope Inventory

- The `stokdWorktrees` kind, its left-rail placement entry, and its section title under `Sources/Sidebar/SidebarDock*`.
- A worktree inventory boundary under `Sources/Stokd/Worktrees/`: git invocation, porcelain parsing, row value types, and presentation state.
- The left-rail Worktrees section, including loading, populated, empty, non-git, and error states.
- Left-rail seeding at stokd rank 2 and the associated snapshot round-trip.
- Localized en+ja strings in `Resources/Localizable.xcstrings`.
- Focused Swift tests under `cmuxTests/`, explicit Xcode test-target wiring, and tagged dogfood.

### Non-Goals

- Work, Global Config, and Usage panels, each of which has its own PRD.
- Destructive worktree actions: create, remove, prune, land, or review from the panel.
- Agents, Agent chat (ACP), Reviews, Current Activity, Model Configuration, or Workload Configuration.
- 1:1 VS Code parity for every extension action.
- Widget-tile chrome, Socket.IO realtime as a hard requirement, or freeform canvas docking.
- Upstream cmux PRs, `vendor/bonsplit` changes, or a second stokd CLI runner.

---

## 1.5 Required Toolchain

| Tool | Min Version | Install Command | Verify Command |
|------|-------------|-----------------|----------------|
| macOS | 14.0 | (OS) | `sw_vers -productVersion` |
| Xcode | 15.0 | App Store | `xcodebuild -version` |
| Swift | 6.0 | (bundled with Xcode) | `swift --version` |
| git | 2.39 | Xcode CLT | `git --version` |
| stokd CLI | current | `curl -fsSL https://stokd.cloud/install \| sh` | `stokd --version` |
| Python 3 | 3.9 | Xcode CLT | `python3 --version` |

Working directory for all Verification Commands: ghostty-dock repo root.

```bash
./scripts/setup.sh   # once per machine if GhosttyKit missing
```

Prefer `CMUX_SKIP_ZIG_BUILD=1` on tagged reloads when host zig is not 0.15.2.

---

## 2. Contract

**VAL-WTKIND-001** — Worktrees is a stable left-rail section kind.
Surface: library
Needs: the panel-kind surface and placement matrix from `docs/stokd-work-panel.prd.md`
Behavior: With the rail gate enabled, gdock can address `stokdWorktrees` by a stable persisted value,
  place it on the left rail, reject it on the right rail, and ignore unknown persisted kinds without
  crashing.
Evidence: Persist the RED → GREEN results from `StokdWorktreesPanelKindTests` and the Xcode
  test-wiring lint output in the phase evidence.
Rigor: R2
Why: The kind is shared persistence and placement infrastructure, so an independent validator must
  confirm the focused regression suite rather than relying on implementer inspection.

**VAL-WTDATA-001** — Worktree inventory is derived from git, deterministically.
Surface: library
Needs: VAL-WTKIND-001 and the CLI/process boundary from `docs/stokd-work-panel.prd.md`
Behavior: For a repository with multiple worktrees, gdock produces one row per worktree carrying
  path, branch (or detached marker), and dirty state; for a non-git directory it produces an empty
  inventory with a distinguishable non-git reason rather than an error state.
Evidence: Persist the RED → GREEN results from `StokdWorktreesInventoryTests`, including the
  `git worktree list --porcelain` fixture, a detached-HEAD fixture, and the non-git fixture.
Rigor: R2
Why: Porcelain parsing is silent-corruption-prone and needs independent fixture-based validation of
  both the happy path and the degenerate directories users actually open.

**VAL-WTSTATE-001** — Worktrees presentation state is deterministic and race-safe.
Surface: library
Needs: VAL-WTDATA-001
Behavior: For a fixed inventory, Worktrees exposes deterministic immutable row snapshots with the
  primary worktree first, distinct populated/empty/non-git/error states, and discards responses
  superseded by a newer request.
Evidence: Persist the RED → GREEN results from `StokdWorktreesViewModelTests`, including the
  ordering-determinism and out-of-order completion fixtures.
Rigor: R2
Why: Ordering and stale-response defects are user-visible but reliably covered by an independent
  deterministic unit-test lane.

**VAL-WTUI-001** — Users can see and open worktrees without blank chrome or duplicated actions.
Surface: artifact
Needs: VAL-WTSTATE-001
Behavior: Selecting the Worktrees section renders identifiable populated, empty, non-git, and error
  content, and open/reveal from any supported entrypoint routes through the one shared SidebarDock
  action path.
Evidence: Persist the RED → GREEN `StokdWorktreesPanelViewTests` results, the snapshot-boundary
  source scan, and tagged dogfood evidence showing the mounted section states.
Rigor: R2
Why: The actor-facing SwiftUI surface needs independent test and dogfood confirmation that no state
  renders as blank chrome.

**VAL-WTSEED-001** — First enable seeds Worktrees once at rank 2 without disturbing user layout.
Surface: library
Needs: VAL-WTUI-001 and the seed-generation marker from `docs/stokd-work-panel.prd.md`
Behavior: On first gated enable the Worktrees section appears below the workspaces section at stokd
  rank 2; later launches preserve user order, never duplicate the section, never reorder other stokd
  sections, and never modify the right rail.
Evidence: Persist the RED → GREEN `StokdWorktreesPanelSeedTests` results for initial seed, reseed,
  customized order, gate-off behavior, rank composition against a rank-1 and rank-3 section, and
  right-rail invariance.
Rigor: R2
Why: Seed mutations can silently overwrite user customization and must compose correctly with
  sibling panels landing in any order, which needs independent regression validation.

**VAL-WTPERSIST-001** — Worktrees rail membership round-trips additively.
Surface: library
Needs: VAL-WTSEED-001 and the additive snapshot rules from `docs/stokd-work-panel.prd.md`
Behavior: A Worktrees-inclusive left-rail layout round-trips membership, order, collapse, and extent
  through additive optional snapshot fields while retaining schema version 1 and skipping unknown
  kinds.
Evidence: Persist the RED → GREEN `StokdWorktreesPanelPersistenceTests` results and the
  schema-version source check.
Rigor: R2
Why: Session restoration is durable user state and needs independent round-trip validation.

**VAL-WTROLL-001** — The localized Worktrees panel is buildable and ready for gated dogfood.
Surface: artifact
Needs: VAL-WTUI-001, VAL-WTSEED-001, and VAL-WTPERSIST-001
Behavior: A tagged gdock build presents localized en+ja Worktrees strings, opens and focuses the
  section through the shared action path, and leaves the pinned bonsplit submodule unchanged and
  clean.
Evidence: Persist the localization audit, focused suite output, test-wiring lint, bonsplit
  SHA/status, and the tagged `reload.sh` build result.
Rigor: R2
Why: Release readiness combines source catalogs, build output, and repository integrity and should
  be independently validated as one terminal artifact gate.

## 3. Execution Topology

## Phase 1: Kind and placement

**Purpose:** Nothing can be discovered, mounted, seeded, or persisted until `stokdWorktrees` exists in the rail registry and placement matrix. This phase adds identity and wiring only — no section body yet.

### 1.1 Register the stokdWorktrees left-rail kind

**Targets:** VAL-WTKIND-001
**Dependencies:** []

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Extend the existing stokd rail panel identity surface (introduced by `docs/stokd-work-panel.prd.md`, following the `PanelType` / `RightSidebarMode` conventions used by `SidebarDockStore`) with `stokdWorktrees`. Casing follows existing conventions; the **raw value must be stable** because it is persisted.
- Update `SidebarDockPlacementMatrix` (or equivalent) so `stokdWorktrees` is allowed on the **left** rail as a section and rejected on the right rail. Do not modify right-rail entries owned by the prerequisite.
- Reuse the prerequisite's `sidebar.beta.dock.enabled` gate as-is; introduce no new flag key.
- Provide a localized section title key; scaffold a placeholder section host that compiles and mounts without crashing (real UI in Phase 3).
- Failure modes: unknown kind in a persisted snapshot → skip + log, never crash; gate off → the kind is not offered in seed, palette, or section menu.

**Acceptance Criteria**
- AC-1.1.a: `stokdWorktrees` exists with a stable raw value → the rail registry can address it.
- AC-1.1.b: Placement matrix allows `stokdWorktrees` on the left rail and rejects it on the right.
- AC-1.1.c: Decoding a snapshot containing an unrecognized stokd kind drops only that entry and does not crash.
- AC-1.1.d: No new beta flag key is introduced — `rg -n 'beta\.' Sources/` shows no key added by this PRD beyond the prerequisite's.
- AC-1.1.e: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorktreesPanelKindTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.
- AC-1.1.f: `./scripts/lint-pbxproj-test-wiring.sh` → exit 0 for the new test file.

**Acceptance Tests**
- Test-1.1.a: Unit — the kind registry exposes `stokdWorktrees`; existing kinds unchanged.
- Test-1.1.b: Unit — placement matrix edge cases (left allowed, right rejected).
- Test-1.1.c: Unit — unknown-kind decode is skipped, not fatal.
- Test-1.1.d: Regression — no new flag key in source.
- Test-1.1.e: Suite gate for AC-1.1.e.
- Test-1.1.f: Regression — pbxproj test wiring script.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'stokdWorktrees' Sources/
test -f cmuxTests/StokdWorktreesPanelKindTests.swift
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorktreesPanelKindTests CMUX_SKIP_ZIG_BUILD=1 test
```

---

## Phase 2: Worktree inventory

**Purpose:** Cannot start before Phase 1 because the section host must exist to consume it; must finish before Phase 3 because the section body is a thin view over this boundary.

### 2.1 Git worktree discovery

**Targets:** VAL-WTDATA-001
**Dependencies:** ["1.1"]

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Add an inventory service under `Sources/Stokd/Worktrees/` that runs `git worktree list --porcelain` for the active workspace repository through the prerequisite's process boundary, off the main actor.
- Parse the porcelain records into value types carrying absolute path, branch name or a detached-HEAD marker, bare/prunable flags, and a dirty flag derived from `git status --porcelain` per worktree.
- **Git is the source of truth for inventory.** Any stokd CLI call is enrichment only (e.g. associating a worktree with a task/project) and its absence or failure must never empty the list. Document this in a code comment.
- Dirty computation is bounded: a per-worktree timeout and a cap on concurrent status probes so a large fleet cannot stall the rail.
- Failure modes: non-git directory → empty inventory with a `nonRepository` reason (not an error); git missing or non-zero exit → empty inventory with a structured error carrying the exit code; timeout → the row is listed with dirty state `unknown` rather than a fabricated clean.

**Acceptance Criteria**
- AC-2.1.a: A multi-worktree porcelain fixture parses into one row per worktree with path and branch populated.
- AC-2.1.b: A detached-HEAD fixture yields the detached marker, not an empty or fabricated branch name.
- AC-2.1.c: A non-git directory yields an empty inventory with the `nonRepository` reason, distinct from the error case.
- AC-2.1.d: A status probe that times out yields dirty state `unknown`, never `clean`.
- AC-2.1.e: Inventory never depends on the stokd CLI — `rg` shows no stokd invocation on the inventory path.
- AC-2.1.f: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorktreesInventoryTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

**Acceptance Tests**
- Test-2.1.a: Unit — porcelain multi-worktree parse.
- Test-2.1.b: Unit — detached HEAD.
- Test-2.1.c: Unit — non-git reason vs error.
- Test-2.1.d: Unit — timeout yields unknown dirty state.
- Test-2.1.e: Regression — no stokd dependency on the inventory path.
- Test-2.1.f: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'worktree list --porcelain' Sources/Stokd/
! rg -n 'StokdCLI' Sources/Stokd/Worktrees/Inventory*.swift
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorktreesInventoryTests CMUX_SKIP_ZIG_BUILD=1 test
```

---

## Phase 3: Section UI

**Purpose:** Depends on the Phase 1 kind and the Phase 2 inventory. This is the visible deliverable — the port of the VS Code Worktrees surface into the left rail.

### 3.1 Worktrees view model

**Targets:** VAL-WTSTATE-001
**Dependencies:** ["2.1"]

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- View model owns load / reload / sort for the inventory scoped to the active workspace repository, and exposes immutable row snapshots to the view (no store references below the list boundary).
- Deterministic ordering: primary worktree first, then remaining worktrees by path, so the list does not reshuffle between refreshes.
- No state mutation inside view-body computations; refreshes happen in load completions or property observers.
- Failure modes: error → `error(text:)` state with user-facing text and zero rows; non-git → distinct `nonRepository` state; superseded in-flight loads are discarded by request id.

**Acceptance Criteria**
- AC-3.1.a: A fixture inventory produces the expected ordered row snapshots with the primary worktree first.
- AC-3.1.b: Repeated loads of the same fixture produce byte-identical ordering.
- AC-3.1.c: The non-git and error cases yield distinct states, each with non-empty user-facing text.
- AC-3.1.d: A late response for a superseded request id is discarded.
- AC-3.1.e: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorktreesViewModelTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

**Acceptance Tests**
- Test-3.1.a: Unit — fixture load → row mapping and order.
- Test-3.1.b: Unit — ordering determinism.
- Test-3.1.c: Unit — non-git vs error states.
- Test-3.1.d: Unit — superseded-request discard.
- Test-3.1.e: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'StokdWorktreesViewModel' Sources/ cmuxTests/
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorktreesViewModelTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 3.2 Worktrees section view and rail mounting

**Targets:** VAL-WTUI-001
**Dependencies:** ["3.1"]

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Implement the SwiftUI body and wire it as left-rail section content for `stokdWorktrees`, replacing the Phase 1 placeholder.
- Rows show path (workspace-relative where possible), branch or detached marker, and a dirty indicator; they carry value snapshots plus closure action bundles only — reference pattern: `IndexSectionActions` / `SectionGapActions` in `Sources/SessionIndexView.swift`.
- Row actions are **open** (open the worktree as a gdock workspace) and **reveal in Finder**, both routed through the existing `SidebarDockActionInvoker` → `SidebarDockCommand.perform` path so palette, context menu, and section menu share one implementation.
- Failure modes: every state (loading, populated, empty, non-git, error) renders identifiable content; none renders blank chrome.

**Acceptance Criteria**
- AC-3.2.a: Mounting `stokdWorktrees` with a fixture-backed view model renders a non-empty view hierarchy.
- AC-3.2.b: Loading, populated, empty, non-git, and error states each render identifiable, non-blank content.
- AC-3.2.c: Open and reveal resolve through `SidebarDockActionInvoker`/`SidebarDockCommand` from every entrypoint — no duplicated open logic.
- AC-3.2.d: No type below the Worktrees row list holds an `ObservableObject`/`@Observable` reference (snapshot-boundary rule).
- AC-3.2.e: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorktreesPanelViewTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

**Acceptance Tests**
- Test-3.2.a: Unit — mounted hierarchy is non-empty for fixtures.
- Test-3.2.b: Unit — all five state renderings.
- Test-3.2.c: Unit — invoker reachability for open and reveal.
- Test-3.2.d: Regression — `rg` over the row files shows no store property wrappers.
- Test-3.2.e: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'StokdWorktreesPanel|stokdWorktrees' Sources/
! rg -n '@(ObservedObject|EnvironmentObject|StateObject|Bindable)' Sources/Stokd/Worktrees/
rg -n 'SidebarDockActionInvoker|SidebarDockCommand' Sources/Stokd/Worktrees/
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorktreesPanelViewTests CMUX_SKIP_ZIG_BUILD=1 test
```

---

## Phase 4: Default seed

**Purpose:** Runs after Phase 3 so a cold-start window seeds a section that renders real content rather than a placeholder, and so rank composition can be tested against a real mounted section.

### 4.1 Seed Worktrees at stokd rank 2

**Targets:** VAL-WTSEED-001
**Dependencies:** ["3.2"]

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Extend `SidebarDockSeeding` (or sibling) so that when the gate is on and the stokd seed generation has not been applied for this kind, a Worktrees section is inserted into the left rail below the workspaces section.
- **Rank-ordered insertion:** stokd left-rail sections carry a rank (Global Config = 1, **Worktrees = 2**, Usage = 3). Insertion positions Worktrees after any lower-ranked stokd section and before any higher-ranked one, so the three panels compose into the documented order regardless of landing order.
- Advance the prerequisite's shared seed-generation marker rather than adding a second marker.
- Gate off: the seed path no-ops for stokd kinds. The right rail is never modified.
- Failure modes: partial seed failure leaves non-stokd rails intact; log and continue.

**Acceptance Criteria**
- AC-4.1.a: Seeding an empty registry with the gate on places Worktrees directly below the workspaces section.
- AC-4.1.b: Seeding into a rail that already has a rank-1 section places Worktrees after it; seeding into a rail that already has a rank-3 section places Worktrees before it.
- AC-4.1.c: A second seed call does not duplicate the section and does not reset a customized order.
- AC-4.1.d: Gate off → seed introduces no stokd kinds.
- AC-4.1.e: Seeding leaves the right-rail tool tab strip identical to its pre-seed state.
- AC-4.1.f: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorktreesPanelSeedTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

**Acceptance Tests**
- Test-4.1.a: Unit — default placement below workspaces.
- Test-4.1.b: Unit — rank composition against rank-1 and rank-3 neighbours.
- Test-4.1.c: Unit — idempotent reseed / custom order preserved.
- Test-4.1.d: Unit — gate-off no-op.
- Test-4.1.e: Unit — right rail untouched.
- Test-4.1.f: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'stokdPanelsSeed|seedStokd|stokdWorktrees' Sources/Sidebar/
rg -n 'rank' Sources/Sidebar/ | rg -n 'stokd'
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorktreesPanelSeedTests CMUX_SKIP_ZIG_BUILD=1 test
```

---

## Phase 5: Persistence, localization, and rollout

**Purpose:** Last phase — depends on the section and seed existing so snapshot keys and strings are real. Closes the slice for dogfood.

### 5.1 Snapshot persistence for the Worktrees section

**Targets:** VAL-WTPERSIST-001
**Dependencies:** ["4.1"]

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Persist left-rail membership, order, collapse state, and extent for `stokdWorktrees` using the **additive optional** snapshot rules established by the prerequisite PRD — **never** bump `SessionSnapshotSchema.currentVersion` and never add a `SessionWorkspaceLayoutSnapshot` case.
- Round-trip: seed layout → encode → decode → equal membership, order, collapse, and extent.
- Failure modes: unknown future kind → skip; corrupt optional → fall back to the default seed once.

**Acceptance Criteria**
- AC-5.1.a: Round-trip of a Worktrees-inclusive layout preserves membership, order, collapse, and extent.
- AC-5.1.b: `SessionSnapshotSchema.currentVersion` is unchanged from the pre-phase baseline (remains 1).
- AC-5.1.c: A snapshot containing an unknown stokd kind decodes with that entry skipped and no crash.
- AC-5.1.d: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorktreesPanelPersistenceTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

**Acceptance Tests**
- Test-5.1.a: Unit — encode/decode round-trip.
- Test-5.1.b: Regression — schema version pin.
- Test-5.1.c: Unit — unknown-kind skip.
- Test-5.1.d: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'currentVersion' Sources/ Packages/ | rg -n 'SessionSnapshotSchema'
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorktreesPanelPersistenceTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 5.2 Localization audit and dogfood gate

**Targets:** VAL-WTROLL-001
**Dependencies:** ["5.1"]

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Every new user-facing string uses `String(localized:)` with en+ja entries in `Resources/Localizable.xcstrings`, `state == translated`, and `ja != en` for non-identical natural text. Covered surfaces: section title, row labels, dirty indicator text, empty/non-git/error states, and any menu item added for open/reveal.
- Palette and debug can open and focus Worktrees through the same invoker path as other rail sections.
- Tagged dogfood: `CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag stokd-worktrees-panel` builds; with the gate on, a cold window shows the section below workspaces.
- Bonsplit clean: `git -C vendor/bonsplit status --porcelain` empty; pinned SHA unchanged.

**Acceptance Criteria**
- AC-5.2.a: Every new Worktrees string key exists in both en and ja with `state == translated`.
- AC-5.2.b: No bare English literal appears in new Worktrees Swift sources' `Text(`/`Button(`/alert titles.
- AC-5.2.c: `./scripts/lint-pbxproj-test-wiring.sh` → exit 0.
- AC-5.2.d: Tagged reload compiles → exit 0 (or, where the environment cannot build the app, all suites in this PRD are green with that substitution recorded in the evidence).
- AC-5.2.e: `git -C vendor/bonsplit status --porcelain` is empty and the pinned SHA is unchanged.

**Acceptance Tests**
- Test-5.2.a: Regression — xcstrings key/locale audit (parse the catalog, compare en vs ja).
- Test-5.2.b: Regression — `rg` for bare English in new Swift sources.
- Test-5.2.c: Regression — pbxproj test wiring.
- Test-5.2.d: Integration — tagged build or documented unit substitute.
- Test-5.2.e: Regression — bonsplit clean + SHA pin.

**Verification Commands**
```bash
set -euo pipefail
python3 - <<'PY'
import json
c = json.load(open('Resources/Localizable.xcstrings'))
bad = [k for k, v in c['strings'].items()
       if 'worktree' in k.lower() and 'stokd' in k.lower()
       and 'ja' not in v.get('localizations', {})]
assert not bad, f"missing ja: {bad}"
print("ja coverage ok")
PY
./scripts/lint-pbxproj-test-wiring.sh
git -C vendor/bonsplit status --porcelain
git -C vendor/bonsplit rev-parse HEAD
# Preferred full gate when the environment allows:
# CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag stokd-worktrees-panel
./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorktreesPanelKindTests \
  -only-testing:cmuxTests/StokdWorktreesInventoryTests \
  -only-testing:cmuxTests/StokdWorktreesViewModelTests \
  -only-testing:cmuxTests/StokdWorktreesPanelViewTests \
  -only-testing:cmuxTests/StokdWorktreesPanelSeedTests \
  -only-testing:cmuxTests/StokdWorktreesPanelPersistenceTests \
  CMUX_SKIP_ZIG_BUILD=1 test
```

---

## 4. Completion Criteria

- [ ] All Phase 1–5 work items' Verification Commands exit 0.
- [ ] Gate on + cold seed shows Worktrees below the workspaces section, ordered by stokd rank against any sibling stokd sections present.
- [ ] Rows show path, branch or detached marker, and dirty state from git, with open and reveal working through the shared action path.
- [ ] Non-git directories render the distinct non-git state; no state renders blank chrome.
- [ ] Gate off: no Worktrees section; existing rails unchanged; the right rail is untouched in both states.
- [ ] en+ja strings present; pbxproj test wiring clean; bonsplit clean and at the pinned SHA.
- [ ] `SessionSnapshotSchema.currentVersion` unchanged.
- [ ] The prerequisite `docs/stokd-work-panel.prd.md` has landed and its foundation is consumed unchanged — no duplicate kind surface, gate, CLI runner, or snapshot rules.

---

## 5. Rollout & Validation

### Rollout Strategy

- Ship behind the existing `sidebar.beta.dock.enabled` beta gate (default off).
- Enable on dogfood machines first via Settings / `cmux.json` beta key.
- Rollback: set the gate false — the Worktrees section disappears; non-stokd rails remain.

### Post-Launch Validation

- Open the tagged Debug app with the gate on in a repo with several worktrees; confirm the rows and dirty markers match `git worktree list`.
- Open a non-git directory; confirm the distinct non-git state, not an error.
- Open a worktree from the panel; confirm it opens as a gdock workspace.
- Collapse the section, quit, relaunch; confirm collapse state and order survive.
- Confirm a large worktree fleet does not stall the rail (dirty probes stay bounded).

---

## 6. Open Questions

1. Should the panel scope to the active workspace's repository only, or to all repositories known to gdock? Default: active workspace repository only; revisit after dogfood.
2. Is stokd task/project association worth showing per row in v1? Default: no — inventory stays pure git; enrichment is a follow-up.
3. Should dirty state refresh on a timer or only on section focus / explicit refresh? Default: on focus and explicit refresh, to keep the bounded-probe guarantee simple.
