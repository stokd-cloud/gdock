# PRD: Stokd Rail Panels — First Slice

## 0. Source Context

**Derived From:** Working request 2026-08-01 — port selected VS Code stokd extension panels into gdock on the **current** rail system, starting with four panels and a fixed default layout.
**Feature Name:** Stokd Rail Panels (first slice)
**PRD Owner:** Brian Stoker
**Last Updated:** 2026-08-01
**Repository:** `stokd-cloud/ghostty-dock` (fork of `manaflow-ai/cmux`), branch `main`
**Landing:** fork-only on `main`

### Summary

Ship four surfaces from the stokd VS Code extension into the existing left/right **rail** host (N collapsible, resizable sections behind `sidebar.beta.dock.enabled`): **Work**, **Worktrees**, **Global Config**, and **Usage**. Default seed places Work as a **right-rail tab** beside Files/Find/Vault; left keeps the existing workspaces section on top and stacks Global Config → Worktrees → Usage below. This PRD does **not** implement the other six panels from the old full-port PRD and does **not** use freeform canvas dock-anywhere.

### Source inventory (read-only)

| Source | Role |
|---|---|
| `stokd-cloud/mono` → `docs/port-stokd-panels-to-ghostty-dock.prd.md` | Behavior inventory for Work + Worktrees |
| `.stokd/projects/stokd-widgets-global-config-per-model-token-usage/prd.md` | Behavior inventory for Global Config + Usage |
| `.stokd/projects/dockable-sidebar-spaces-and-quad-split/prd.md` | Authoritative rail substrate (sections, collapse, resize, persistence) |
| Live `main` | `Sources/Sidebar/SidebarDock*` |

### Architecture correction

The old port PRD assumes canvas `Dockable` everywhere. **Rails already exist on `main`.** This slice hosts panels in rails only. The old “wait for full canvas dockable refactor” gate is superseded for these four panels.

### Default layout (load-bearing)

```
LEFT RAIL                          RIGHT RAIL
┌─────────────────────────┐        ┌─────────────────────────┐
│ Section: Workspaces     │        │ Section: Tools          │
│ (existing selector)     │        │ tabs: Files | Find |    │
│  — top —                │        │       Vault | Work      │
├─────────────────────────┤        │                         │
│ Section: Global Config  │        │  (active tool content)  │
├─────────────────────────┤        │                         │
│ Section: Worktrees      │        │                         │
├─────────────────────────┤        │                         │
│ Section: Usage          │        │                         │
│  — bottom —             │        │                         │
└─────────────────────────┘        └─────────────────────────┘
```

Users may reorder after seed; first enable must match this diagram.

### Non-goals

- Agents, Agent chat (ACP), Reviews, Current Activity, Model Configuration, Workload Configuration
- 1:1 VS Code parity for every extension action
- Widget-tile chrome from the widgets PRD
- Socket.IO realtime as a hard requirement
- Upstream cmux PRs / `vendor/bonsplit` changes

---

## 1. Objectives & Constraints

### Objectives

- Register four rail-hosted panel kinds: Work, Worktrees, Global Config, Usage.
- Seed the default layout above when the feature is enabled and the stokd-panels seed has not been applied.
- Reuse existing rail primitives (`SidebarDockStore`, seeding, commands, invoker, placement matrix). No second docking system.
- Each panel has a real local data path (CLI / API / files) or a clear empty/error state — no blank crash chrome.
- Persist arrangement with the same additive snapshot rules as the rail PRD (no `SessionSnapshotSchema.currentVersion` bump).

### Constraints

- **Fork-only** on `stokd-cloud/ghostty-dock` `main`.
- **Rail host only** — no freeform canvas dock-anywhere.
- **Beta-gated**, default off (reuse `sidebar.beta.dock.enabled` or a dedicated `sidebar.beta.stokdPanels.enabled`; decide once in Phase 1 and stick to it).
- Config writes only via `stokd config set …` — never mutate `~/.stokd/config.yaml` directly.
- All user-facing strings localized en+ja via `String(localized:)` / `Resources/Localizable.xcstrings`.
- New tests wired into `cmux.xcodeproj`; `./scripts/lint-pbxproj-test-wiring.sh` green.
- SwiftUI snapshot-boundary and no-state-in-body rules apply.
- Bonsplit submodule SHA unchanged and worktree clean.

---

## 1.5 Required Toolchain

| Tool | Min Version | Install Command | Verify Command |
|------|-------------|-----------------|----------------|
| macOS | 14.0 | (OS) | `sw_vers -productVersion` |
| Xcode | 15.0 | App Store | `xcodebuild -version` |
| Swift | 6.0 | (bundled with Xcode) | `swift --version` |
| stokd CLI | current | `curl -fsSL https://stokd.cloud/install \| sh` | `stokd --version` |
| Python 3 | 3.9 | Xcode CLT | `python3 --version` |

Working directory for all Verification Commands: ghostty-dock repo root.

```bash
./scripts/setup.sh   # once per machine if GhosttyKit missing
```

Prefer `CMUX_SKIP_ZIG_BUILD=1` on tagged reloads when host zig is not 0.15.2.

---

## 2. Execution Phases

## Phase 1: Panel kinds, placement, and feature gate

**Purpose:** Later phases cannot seed or mount panels until kinds exist in the rail registry/placement matrix and the enablement gate is defined. This phase creates types and wiring only — no full UI bodies yet.

### 1.1 Register four stokd rail panel kinds

**Dependencies:** none

**Landing:** fork-only

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

**Acceptance Tests**
- Test-1.1.a: Unit — kinds enum/registry lists exactly the four new kinds (plus existing non-stokd kinds unchanged).
- Test-1.1.b: Unit — placement matrix matrix cases for edges.
- Test-1.1.c: Same suite is the executable gate for AC-1.1.c.
- Test-1.1.d: Regression — pbx wiring script.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'stokdWork|stokdWorktrees|stokdGlobalConfig|stokdUsage' Sources/
test -f cmuxTests/StokdRailPanelKindTests.swift || test -f cmuxTests/SidebarDockPlacementMatrixTests.swift
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdRailPanelKindTests CMUX_SKIP_ZIG_BUILD=1 test \
  || ./scripts/test-unit.sh -only-testing:cmuxTests/SidebarDockPlacementMatrixTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 1.2 Feature gate for stokd rail panels

**Dependencies:** 1.1

**Landing:** fork-only

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

**Acceptance Tests**
- Test-1.2.a: Unit — default-off.
- Test-1.2.b: Unit — enable/disable matrix.
- Test-1.2.c: Suite executable gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'stokdPanels|sidebar\.beta\.(dock|stokdPanels)' Sources/
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdRailPanelFlagTests CMUX_SKIP_ZIG_BUILD=1 test
```

---

## Phase 2: Default seed layout

**Purpose:** Cannot run before Phase 1 because seeding needs registered kinds and the gate. This phase makes cold-start windows match the §0 diagram without thrashing later user rearrangements.

### 2.1 Seed left stack and right Work tab

**Dependencies:** 1.1, 1.2

**Landing:** fork-only

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

**Acceptance Tests**
- Test-2.1.a: Unit — default layout diagram.
- Test-2.1.b: Unit — idempotent reseed.
- Test-2.1.c: Unit — flag-off no-op.
- Test-2.1.d: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'stokdPanelsSeed|seedStokd|Global Config|stokdUsage' Sources/Sidebar/
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdRailPanelSeedTests CMUX_SKIP_ZIG_BUILD=1 test
```

---

## Phase 3: Minimal data plane

**Purpose:** Phase 4 UI needs shared CLI/API access. Build a small app-local data plane first so panels stay thin. May live under `Sources/Stokd/` without a full SPM package unless extraction clearly pays for itself.

### 3.1 CLI runner and API client stubs for panels

**Dependencies:** Phase 1 complete (types exist); no hard dep on Phase 2 seed.

**Landing:** fork-only

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

**Acceptance Tests**
- Test-3.1.a: Unit — CLI path resolution.
- Test-3.1.b: Unit — JSON decode fixtures for tasks/projects.
- Test-3.1.c: Unit — writer argv only.
- Test-3.1.d: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'StokdCLI|stokd config set|8167' Sources/
! rg -n 'write.*config\.yaml|FileManager.*config\.yaml' Sources/Stokd/ Sources/Sidebar/ 2>/dev/null || true
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdDataPlaneTests CMUX_SKIP_ZIG_BUILD=1 test
```

---

## Phase 4: Panel UI implementations

**Purpose:** Depends on Phase 1 kinds and Phase 3 data plane. Four work items deliver the visible VS Code panel ports into rails. Seed from Phase 2 makes them appear by default once mounted.

### 4.1 Work panel (right rail tab)

**Dependencies:** 1.1, 3.1

**Landing:** fork-only

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

**Acceptance Tests**
- Test-4.1.a: Unit — view model loads fixtures.
- Test-4.1.b: Unit — filter/sort.
- Test-4.1.c: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'StokdWork|stokdWork' Sources/
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorkPanelTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 4.2 Worktrees panel (left section)

**Dependencies:** 1.1, 3.1

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Implement Worktrees section: inventory from Git/local worktree discovery for the active repo (document source of truth in code; do not hard-depend only on incomplete CLI if git is authoritative).
- Rows: path, branch, dirty; open/reveal minimum; land/review actions optional for this slice if unsafe.
- Failure modes: non-git cwd → empty + explanation.

**Acceptance Criteria**
- AC-4.2.a: Fixture repo produces expected worktree rows in unit tests.
- AC-4.2.b: Non-git path yields empty state without crash.
- AC-4.2.c: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorktreesPanelTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

**Acceptance Tests**
- Test-4.2.a: Unit — row composition.
- Test-4.2.b: Unit — non-git empty.
- Test-4.2.c: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'StokdWorktree|stokdWorktrees' Sources/
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorktreesPanelTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 4.3 Global Config panel (left section)

**Dependencies:** 1.1, 3.1

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Schema-driven settings UI from CLI schema descriptor; scope from active window focused workspace cwd.
- Show layered provenance when cheap; writes only through CLI writer with explicit scope (default workspace; global requires deliberate switch).
- Failure modes: CLI missing → “stokd CLI not found” state; unknown field types render read-only.

**Acceptance Criteria**
- AC-4.3.a: Schema fixture renders ≥1 field group.
- AC-4.3.b: Write path unit test asserts `stokd config set` argv, never FileManager write to yaml.
- AC-4.3.c: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdGlobalConfigPanelTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

**Acceptance Tests**
- Test-4.3.a: Unit — schema decode + render model.
- Test-4.3.b: Unit — write argv.
- Test-4.3.c: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'StokdGlobalConfig|stokdGlobalConfig|config schema' Sources/
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdGlobalConfigPanelTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 4.4 Usage panel (left section, bottom)

**Dependencies:** 1.1, 3.1

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Per provider → per model token/cost breakdown for supported timespans.
- Prefer file-watch/incremental ingest; include reasoning tokens and restart-safe provider dedupe when data model supports it; mark unmeasured cache columns unavailable rather than fake zeros.
- Failure modes: no stores → configured-but-unobserved rows or empty state, not crash.

**Acceptance Criteria**
- AC-4.4.a: Fixture usage records aggregate into provider/model rows.
- AC-4.4.b: Missing cache columns do not display as measured zero when unavailable.
- AC-4.4.c: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdUsagePanelTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

**Acceptance Tests**
- Test-4.4.a: Unit — aggregation.
- Test-4.4.b: Unit — unavailable cache columns.
- Test-4.4.c: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'StokdUsage|stokdUsage|TokenUsage' Sources/
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdUsagePanelTests CMUX_SKIP_ZIG_BUILD=1 test
```

---

## Phase 5: Persistence, localization, and rollout

**Purpose:** Last phase — depends on panels existing so snapshot keys and strings are real. Closes the project for dogfood.

### 5.1 Snapshot persistence for stokd rail membership

**Dependencies:** Phase 2, Phase 4

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Persist section membership, order, collapse, extents, and right-rail tab selection including stokd kinds using **additive optional** snapshot fields only — **never** bump `SessionSnapshotSchema.currentVersion` and never add a `SessionWorkspaceLayoutSnapshot` case.
- Round-trip unit test: seed layout → encode → decode → equal membership.
- Failure modes: unknown future kind → skip; corrupt optional → default seed once.

**Acceptance Criteria**
- AC-5.1.a: Round-trip unit test exit 0 for stokd-inclusive layout.
- AC-5.1.b: `rg` shows no increment of `SessionSnapshotSchema.currentVersion` in the change set relative to pre-phase baseline (version remains 1).
- AC-5.1.c: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdRailPanelPersistenceTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

**Acceptance Tests**
- Test-5.1.a: Unit — encode/decode.
- Test-5.1.b: Regression — schema version pin.
- Test-5.1.c: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'currentVersion' Sources/SessionSnapshotSchema.swift Packages Sources 2>/dev/null | head -20
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdRailPanelPersistenceTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 5.2 Localization audit and dogfood gate

**Dependencies:** 4.1–4.4, 5.1

**Landing:** fork-only

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

**Acceptance Tests**
- Test-5.2.a: Regression — xcstrings keys present.
- Test-5.2.b: Regression — pbx wiring.
- Test-5.2.c: Integration — tagged build or documented unit substitute.
- Test-5.2.d: Regression — bonsplit SHA.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'stokd\.(work|worktrees|globalConfig|usage)|sidebarDock\.stokd' Resources/Localizable.xcstrings || \
  rg -n 'Worktrees|Global Config|Token Usage|STOKD' Resources/Localizable.xcstrings
./scripts/lint-pbxproj-test-wiring.sh
git -C vendor/bonsplit status --porcelain
# Preferred full gate when environment allows:
# CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag stokd-rail-panels
./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorkPanelTests \
  -only-testing:cmuxTests/StokdWorktreesPanelTests \
  -only-testing:cmuxTests/StokdGlobalConfigPanelTests \
  -only-testing:cmuxTests/StokdUsagePanelTests \
  -only-testing:cmuxTests/StokdRailPanelSeedTests \
  CMUX_SKIP_ZIG_BUILD=1 test
```

---

## 3. Completion Criteria

- [ ] All Phase 1–5 work items’ Verification Commands exit 0.
- [ ] Flag on + cold seed matches §0 default layout.
- [ ] Right rail tab strip includes Work; left bottom stack is Global Config → Worktrees → Usage under workspaces.
- [ ] Flag off: no stokd sections/tabs; existing rails unchanged.
- [ ] Config writes never touch yaml files directly.
- [ ] en+ja strings present; pbx test wiring clean; bonsplit submodule clean and unpinned-change-free.
- [ ] No freeform canvas docking; no panels outside the four named in this PRD.

---

## 4. Rollout & Validation

### Rollout Strategy

- Ship behind beta flag (default off).
- Enable on dogfood machines first via settings / `cmux.json` beta key.
- Rollback: set flag false — stokd sections disappear; non-stokd rails remain.

### Post-Launch Validation

- Open tagged Debug app with flag on; confirm layout diagram.
- Exercise Work list against a real local stokd workspace.
- Edit one Global Config field via UI; confirm CLI-mediated write and restart still shows value.
- Confirm Usage updates after agent activity without app crash.
- Confirm session restore keeps stokd section order after quit/relaunch.

---

## 5. Open Questions

1. Shared rail flag vs dedicated `sidebar.beta.stokdPanels.enabled` (Phase 1.2 decides; default Option A if unanswered).
2. How much Worktrees land/review action surface ships in v1 vs list+open only (default list+open).
3. Whether Global Config + Worktrees should ever share one section as tabs later (default remains two sections per §0).

If unanswered at implement time: take the defaults above and record the choice in project notes.