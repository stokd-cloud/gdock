# PRD: Stokd Rail Panels — Left Rail Slice

## 0. Source Context

**Derived From:** Working request 2026-08-01 — port selected VS Code stokd extension panels into gdock on the **current** rail system with a fixed default layout. Re-sliced 2026-08-08: the **Work** panel moved into its own PRD.
**Feature Name:** Stokd Rail Panels (left rail slice)
**PRD Owner:** Brian Stoker
**Last Updated:** 2026-08-08
**Repository:** `stokd-cloud/ghostty-dock` (fork of `manaflow-ai/cmux`), branch `main`
**Landing:** fork-only on `main`
**Prerequisite:** `docs/stokd-work-panel.prd.md` — the Work panel PRD lands first and **owns** the shared foundation: the stokd rail panel-kind surface, the stokd-panels beta feature gate, the stokd CLI data plane, and the additive snapshot persistence rules. This PRD consumes that foundation and re-specifies none of it.

### Summary

Ship three surfaces from the stokd VS Code extension into the existing left **rail** host (N collapsible, resizable sections behind `sidebar.beta.dock.enabled`): **Worktrees**, **Global Config**, and **Usage**. The left rail keeps the existing workspaces section on top and stacks Global Config → Worktrees → Usage below. The **Work** panel and its right-rail tab are specified in `docs/stokd-work-panel.prd.md` and are out of scope here. This PRD does **not** implement the other six panels from the old full-port PRD and does **not** use freeform canvas dock-anywhere.

### Source inventory (read-only)

| Source | Role |
|---|---|
| `docs/stokd-work-panel.prd.md` | **Prerequisite PRD** — owns panel-kind surface, feature gate, CLI data plane, snapshot rules |
| `stokd-cloud/mono` → `docs/port-stokd-panels-to-ghostty-dock.prd.md` | Behavior inventory for Worktrees |
| `.stokd/projects/stokd-widgets-global-config-per-model-token-usage/prd.md` | Behavior inventory for Global Config + Usage |
| `.stokd/projects/dockable-sidebar-spaces-and-quad-split/prd.md` | Authoritative rail substrate (sections, collapse, resize, persistence) |
| Live `main` | `Sources/Sidebar/SidebarDock*` |

### Architecture correction

The old port PRD assumes canvas `Dockable` everywhere. **Rails already exist on `main`.** This slice hosts panels in rails only. The old “wait for full canvas dockable refactor” gate is superseded for these three panels.

### Default layout (load-bearing)

```
LEFT RAIL
┌─────────────────────────┐
│ Section: Workspaces     │
│ (existing selector)     │
│  — top —                │
├─────────────────────────┤
│ Section: Global Config  │
├─────────────────────────┤
│ Section: Worktrees      │
├─────────────────────────┤
│ Section: Usage          │
│  — bottom —             │
└─────────────────────────┘
```

The right rail is not modified by this PRD; its tool tab strip (including the Work tab) is owned by `docs/stokd-work-panel.prd.md`. Users may reorder after seed; first enable must match this diagram.

### Non-goals

- The Work panel and any right-rail change (see `docs/stokd-work-panel.prd.md`)
- Agents, Agent chat (ACP), Reviews, Current Activity, Model Configuration, Workload Configuration
- 1:1 VS Code parity for every extension action
- Widget-tile chrome from the widgets PRD
- Socket.IO realtime as a hard requirement
- Upstream cmux PRs / `vendor/bonsplit` changes

---

## 1. Objectives & Constraints

### Objectives

- Register three left-rail panel kinds: Worktrees, Global Config, Usage — as additions to the stokd panel-kind surface introduced by the prerequisite PRD.
- Seed the default layout above when the feature is enabled and the stokd-panels seed has not been applied, reusing the prerequisite PRD's seed-generation marker.
- Reuse existing rail primitives (`SidebarDockStore`, seeding, commands, invoker, placement matrix). No second docking system.
- Each panel has a real local data path (CLI / API / files) or a clear empty/error state — no blank crash chrome.
- Persist arrangement with the same additive snapshot rules as the rail PRD (no `SessionSnapshotSchema.currentVersion` bump).

### Constraints

- **Fork-only** on `stokd-cloud/ghostty-dock` `main`.
- **Prerequisite:** `docs/stokd-work-panel.prd.md` must land first. This PRD **consumes unchanged** the panel-kind surface, the beta feature gate, the stokd CLI data plane, and the additive snapshot persistence rules defined there, and must not redefine any of them.
- **Left rail only** — no right-rail or tool-tab-strip changes.
- **Rail host only** — no freeform canvas dock-anywhere.
- **Beta-gated**, default off — reuse whichever gate the prerequisite PRD chose in its Phase 1.2; do not introduce a second flag.
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

## Phase 1: Left-rail panel kinds and placement

**Purpose:** Later phases cannot seed or mount panels until the three left-rail kinds exist in the rail registry/placement matrix. The panel-kind surface itself and the enablement gate already exist from the prerequisite PRD, so this phase adds cases and wiring only — no full UI bodies yet.

### 1.1 Register three left-rail stokd panel kinds

**Dependencies:** none (external: `docs/stokd-work-panel.prd.md` Phases 1–2 landed)

**Landing:** fork-only

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

**Acceptance Tests**
- Test-1.1.a: Unit — kinds enum/registry lists the three new kinds (plus existing kinds unchanged).
- Test-1.1.b: Unit — placement matrix edge cases (left allowed, right rejected).
- Test-1.1.c: Regression — `rg` shows no new `…stokdPanels…` flag key beyond the prerequisite's.
- Test-1.1.d: Same suite is the executable gate for AC-1.1.d.
- Test-1.1.e: Regression — pbx wiring script.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'stokdWorktrees|stokdGlobalConfig|stokdUsage' Sources/
test -f cmuxTests/StokdRailPanelKindTests.swift || test -f cmuxTests/SidebarDockPlacementMatrixTests.swift
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdRailPanelKindTests CMUX_SKIP_ZIG_BUILD=1 test \
  || ./scripts/test-unit.sh -only-testing:cmuxTests/SidebarDockPlacementMatrixTests CMUX_SKIP_ZIG_BUILD=1 test
```

---

## Phase 2: Default seed layout

**Purpose:** Cannot run before Phase 1 because seeding needs registered kinds and the gate. This phase makes cold-start windows match the §0 diagram without thrashing later user rearrangements.

### 2.1 Seed the left-rail stack

**Dependencies:** 1.1

**Landing:** fork-only

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

**Acceptance Tests**
- Test-2.1.a: Unit — default layout diagram.
- Test-2.1.b: Unit — idempotent reseed.
- Test-2.1.c: Unit — flag-off no-op.
- Test-2.1.d: Unit — right rail untouched.
- Test-2.1.e: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'stokdPanelsSeed|seedStokd|Global Config|stokdUsage' Sources/Sidebar/
rg -n 'stokdWorktrees|stokdGlobalConfig|stokdUsage' Sources/Sidebar/
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdRailPanelSeedTests CMUX_SKIP_ZIG_BUILD=1 test
```

---

## Phase 3: Config and usage data access

**Purpose:** Phase 4 UI needs config-schema and token-usage data. The stokd CLI runner itself already exists from the prerequisite PRD's data plane; this phase adds only the two access paths the left-rail panels need, on top of that runner, so panels stay thin.

### 3.1 Config schema access and usage ingest

**Dependencies:** 1.1 (types exist); no hard dep on Phase 2 seed. External: the prerequisite PRD's CLI runner.

**Landing:** fork-only

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

**Acceptance Tests**
- Test-3.1.a: Unit — schema JSON decode fixtures.
- Test-3.1.b: Unit — usage record ingest fixtures.
- Test-3.1.c: Unit — writer argv only.
- Test-3.1.d: Regression — single CLI resolver.
- Test-3.1.e: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'StokdCLI|stokd config set|config schema' Sources/
test "$(rg -c -n 'STOKD_CLI_PATH' Sources/ | wc -l | tr -d ' ')" = "1"
! rg -n 'write.*config\.yaml|FileManager.*config\.yaml' Sources/Stokd/ Sources/Sidebar/ 2>/dev/null || true
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdConfigUsageDataTests CMUX_SKIP_ZIG_BUILD=1 test
```

---

## Phase 4: Panel UI implementations

**Purpose:** Depends on Phase 1 kinds and Phase 3 data access. Three work items deliver the visible VS Code panel ports into the left rail. Seed from Phase 2 makes them appear by default once mounted.

### 4.1 Worktrees panel (left section)

**Dependencies:** 1.1, 3.1

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Implement Worktrees section: inventory from Git/local worktree discovery for the active repo (document source of truth in code; do not hard-depend only on incomplete CLI if git is authoritative).
- Rows: path, branch, dirty; open/reveal minimum; land/review actions optional for this slice if unsafe.
- Failure modes: non-git cwd → empty + explanation.

**Acceptance Criteria**
- AC-4.1.a: Fixture repo produces expected worktree rows in unit tests.
- AC-4.1.b: Non-git path yields empty state without crash.
- AC-4.1.c: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorktreesPanelTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

**Acceptance Tests**
- Test-4.1.a: Unit — row composition.
- Test-4.1.b: Unit — non-git empty.
- Test-4.1.c: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'StokdWorktree|stokdWorktrees' Sources/
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorktreesPanelTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 4.2 Global Config panel (left section)

**Dependencies:** 1.1, 3.1

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Schema-driven settings UI from CLI schema descriptor; scope from active window focused workspace cwd.
- Show layered provenance when cheap; writes only through CLI writer with explicit scope (default workspace; global requires deliberate switch).
- Failure modes: CLI missing → “stokd CLI not found” state; unknown field types render read-only.

**Acceptance Criteria**
- AC-4.2.a: Schema fixture renders ≥1 field group.
- AC-4.2.b: Write path unit test asserts `stokd config set` argv, never FileManager write to yaml.
- AC-4.2.c: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdGlobalConfigPanelTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

**Acceptance Tests**
- Test-4.2.a: Unit — schema decode + render model.
- Test-4.2.b: Unit — write argv.
- Test-4.2.c: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'StokdGlobalConfig|stokdGlobalConfig|config schema' Sources/
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdGlobalConfigPanelTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 4.3 Usage panel (left section, bottom)

**Dependencies:** 1.1, 3.1

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Per provider → per model token/cost breakdown for supported timespans.
- Prefer file-watch/incremental ingest; include reasoning tokens and restart-safe provider dedupe when data model supports it; mark unmeasured cache columns unavailable rather than fake zeros.
- Failure modes: no stores → configured-but-unobserved rows or empty state, not crash.

**Acceptance Criteria**
- AC-4.3.a: Fixture usage records aggregate into provider/model rows.
- AC-4.3.b: Missing cache columns do not display as measured zero when unavailable.
- AC-4.3.c: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdUsagePanelTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

**Acceptance Tests**
- Test-4.3.a: Unit — aggregation.
- Test-4.3.b: Unit — unavailable cache columns.
- Test-4.3.c: Suite gate.

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
- Persist left-rail section membership, order, collapse, and extents for the three new kinds using the **additive optional** snapshot rules established by the prerequisite PRD — **never** bump `SessionSnapshotSchema.currentVersion` and never add a `SessionWorkspaceLayoutSnapshot` case. Right-rail tab selection persistence is already covered by the prerequisite PRD.
- Round-trip unit test: seed layout → encode → decode → equal membership.
- Failure modes: unknown future kind → skip; corrupt optional → default seed once.

**Acceptance Criteria**
- AC-5.1.a: Round-trip unit test exit 0 for a layout including the three left-rail stokd sections.
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

**Dependencies:** 4.1–4.3, 5.1

**Landing:** fork-only

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

**Acceptance Tests**
- Test-5.2.a: Regression — xcstrings keys present.
- Test-5.2.b: Regression — pbx wiring.
- Test-5.2.c: Integration — tagged build or documented unit substitute.
- Test-5.2.d: Regression — bonsplit SHA.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'stokd\.(worktrees|globalConfig|usage)|sidebarDock\.stokd' Resources/Localizable.xcstrings || \
  rg -n 'Worktrees|Global Config|Token Usage|STOKD' Resources/Localizable.xcstrings
./scripts/lint-pbxproj-test-wiring.sh
git -C vendor/bonsplit status --porcelain
# Preferred full gate when environment allows:
# CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag stokd-left-rail-panels
./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorktreesPanelTests \
  -only-testing:cmuxTests/StokdGlobalConfigPanelTests \
  -only-testing:cmuxTests/StokdUsagePanelTests \
  -only-testing:cmuxTests/StokdRailPanelSeedTests \
  CMUX_SKIP_ZIG_BUILD=1 test
```

---

## 3. Completion Criteria

- [ ] All Phase 1–5 work items’ Verification Commands exit 0.
- [ ] Flag on + cold seed matches §0 default layout.
- [ ] Left bottom stack is Global Config → Worktrees → Usage under workspaces; the right rail is unchanged by this PRD.
- [ ] Flag off: no stokd sections; existing rails unchanged.
- [ ] Config writes never touch yaml files directly.
- [ ] en+ja strings present; pbx test wiring clean; bonsplit submodule clean and unpinned-change-free.
- [ ] No freeform canvas docking; no panels outside the three named in this PRD.
- [ ] The prerequisite `docs/stokd-work-panel.prd.md` has landed and its foundation (panel-kind surface, gate, CLI data plane, snapshot rules) is consumed unchanged — no duplicate implementation.

---

## 4. Rollout & Validation

### Rollout Strategy

- Ship behind beta flag (default off).
- Enable on dogfood machines first via settings / `cmux.json` beta key.
- Rollback: set flag false — stokd sections disappear; non-stokd rails remain.

### Post-Launch Validation

- Open tagged Debug app with flag on; confirm layout diagram.
- Edit one Global Config field via UI; confirm CLI-mediated write and restart still shows value.
- Confirm Usage updates after agent activity without app crash.
- Confirm session restore keeps stokd section order after quit/relaunch.

---

## 5. Open Questions

1. (Resolved by the prerequisite PRD) The stokd-panels beta gate is whichever key `docs/stokd-work-panel.prd.md` Phase 1.2 selected; this PRD reuses it.
2. How much Worktrees land/review action surface ships in v1 vs list+open only (default list+open).
3. Whether Global Config + Worktrees should ever share one section as tabs later (default remains two sections per §0).

If unanswered at implement time: take the defaults above and record the choice in project notes.