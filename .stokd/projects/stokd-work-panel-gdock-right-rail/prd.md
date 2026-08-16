# PRD: Stokd Work Panel (gdock right rail)

## 0. Source Context

**Derived From:** Sliced out of `.stokd/projects/stokd-rail-panels-first-slice/prd.md` on 2026-08-08 — the Work panel is being shipped on its own ahead of the remaining left-rail panels.
**Feature Name:** Stokd Work Panel
**PRD Owner:** Brian Stoker
**Last Updated:** 2026-08-08
**Repository:** `stokd-cloud/ghostty-dock` (fork of `manaflow-ai/cmux`), branch `main`
**Landing:** fork-only on `main`

### Summary

Port the **Work** surface from the stokd VS Code extension into gdock as a **right-rail tool tab** beside Files / Find / Vault, hosted on the existing rail system (N collapsible, resizable sections behind `sidebar.beta.dock.enabled`). Work lists the active workspace's stokd **tasks and projects** from the local stokd API.

Because this is the first stokd panel to land, this PRD **owns the shared foundation** every later stokd rail panel builds on:

1. the stokd rail panel-kind surface + placement matrix entry,
2. the beta feature gate for stokd panels,
3. the minimal stokd data plane (CLI executable resolution + local REST client),
4. additive snapshot persistence rules for stokd rail membership.

The remaining three panels (**Worktrees**, **Global Config**, **Usage**) are specified in `.stokd/projects/stokd-rail-panels-first-slice/prd.md`, which now depends on this PRD for items 1–4 and must not re-implement them.

### Source inventory (read-only)

| Source | Role |
|---|---|
| `stokd-cloud/mono` → `docs/port-stokd-panels-to-ghostty-dock.prd.md` | Behavior inventory for Work |
| `.stokd/projects/dockable-sidebar-spaces-and-quad-split/prd.md` | Authoritative rail substrate (sections, collapse, resize, persistence) |
| `.stokd/projects/stokd-rail-panels-first-slice/prd.md` | Sibling PRD for the left-rail panels; consumes this PRD's foundation |
| Live `main` | `Sources/Sidebar/SidebarDock*` |

### Default layout (load-bearing)

```
RIGHT RAIL
┌─────────────────────────┐
│ Section: Tools          │
│ tabs: Files | Find |    │
│       Vault | Work      │
│                         │
│  (active tool content)  │
│                         │
└─────────────────────────┘
```

The left rail is untouched by this PRD: the existing workspaces section stays exactly as it is on `main`. Users may reorder the tool tabs after seed; first enable must match this diagram.

### Non-goals

- Worktrees, Global Config, Usage panels (sibling PRD)
- Agents, Agent chat (ACP), Reviews, Current Activity, Model Configuration, Workload Configuration
- 1:1 VS Code parity for every extension action
- Widget-tile chrome from the widgets PRD
- Socket.IO realtime as a hard requirement
- Freeform canvas dock-anywhere
- Upstream cmux PRs / `vendor/bonsplit` changes

---

## 1. Objectives & Constraints

### Objectives

- Register the `stokdWork` rail panel kind with a stable raw value and right-rail placement.
- Define the stokd-panels beta gate once, in a form the sibling left-rail PRD can reuse unchanged.
- Provide a minimal, testable stokd data plane: CLI executable resolution + local REST client for tasks/projects.
- Render Work as right-rail tool tab content with a real data path and explicit empty/error states — no blank crash chrome.
- Seed Work into the right-rail Tools tab strip on first enable, idempotently.
- Persist rail membership/tab selection with additive snapshot fields only (no `SessionSnapshotSchema.currentVersion` bump).

### Constraints

- **Fork-only** on `stokd-cloud/ghostty-dock` `main`.
- **Rail host only** — no freeform canvas dock-anywhere.
- **Beta-gated**, default off.
- This PRD lands **before** `.stokd/projects/stokd-rail-panels-first-slice/prd.md`; that PRD consumes the kind surface, gate, data plane, and persistence rules defined here.
- The data plane is a headless CLI/API boundary — panels stay thin and never shell out inline.
- Config writes (if any surface later needs them) only via `stokd config set …` — never mutate `~/.stokd/config.yaml` directly.
- All user-facing strings localized en+ja via `String(localized:)` / `Resources/Localizable.xcstrings`.
- New tests wired into `cmux.xcodeproj`; `./scripts/lint-pbxproj-test-wiring.sh` green.
- SwiftUI snapshot-boundary and no-state-mutation-in-body rules apply (see `CLAUDE.md`).
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

## Phase 1: Panel kind, placement, and feature gate

**Purpose:** Nothing can be seeded, mounted, or persisted until the `stokdWork` kind exists in the rail registry/placement matrix and the enablement gate is defined. This phase creates types and wiring only — no panel body yet.

### 1.1 Register the stokdWork rail panel kind

**Dependencies:** none

**Landing:** fork-only

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

**Acceptance Tests**
- Test-1.1.a: Unit — kind enum/registry exposes `stokdWork`; existing non-stokd kinds unchanged.
- Test-1.1.b: Unit — placement matrix edge cases (right allowed, left rejected).
- Test-1.1.c: Unit — unknown-kind decode is skipped, not fatal.
- Test-1.1.d: Suite gate for AC-1.1.d.
- Test-1.1.e: Regression — pbxproj test wiring script.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'stokdWork' Sources/
test -f cmuxTests/StokdWorkPanelKindTests.swift
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorkPanelKindTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 1.2 Feature gate for stokd rail panels

**Dependencies:** 1.1

**Landing:** fork-only

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

**Acceptance Tests**
- Test-1.2.a: Unit — default-off.
- Test-1.2.b: Unit — enable/disable matrix.
- Test-1.2.c: Regression — `rg` asserts the `gdock.` prefix and catalog registration (skipped with a recorded note if Option A is chosen).
- Test-1.2.d: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'stokdPanels|sidebar\.beta\.dock\.enabled|gdock\.sidebar\.beta\.stokdPanels' Sources/ Packages/
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdRailPanelFlagTests CMUX_SKIP_ZIG_BUILD=1 test
```

---

## Phase 2: Minimal stokd data plane

**Purpose:** Cannot start before Phase 1 because the panel host must exist to consume it; must finish before Phase 3 because the Work UI is a thin view over this boundary. Lives under `Sources/Stokd/` without a full SPM package unless extraction clearly pays for itself.

### 2.1 stokd CLI runner

**Dependencies:** 1.1

**Landing:** fork-only

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

**Acceptance Tests**
- Test-2.1.a: Unit — CLI path resolution order.
- Test-2.1.b: Unit — missing-binary error shape.
- Test-2.1.c: Regression — `rg` proves no direct yaml write.
- Test-2.1.d: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'STOKD_CLI_PATH|\.stokd/bin/stokd' Sources/
! rg -n 'config\.yaml' Sources/Stokd/ Sources/Sidebar/
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdCLIRunnerTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 2.2 Local stokd API client for tasks and projects

**Dependencies:** 2.1

**Landing:** fork-only

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

**Acceptance Tests**
- Test-2.2.a: Unit — JSON decode fixtures for tasks and projects (including an empty page and a next-page cursor).
- Test-2.2.b: Unit — error mapping via `URLProtocol` stub (refused + 500).
- Test-2.2.c: Unit — base URL default and override.
- Test-2.2.d: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n '8167|StokdWorkAPI|URLProtocol' Sources/ cmuxTests/
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorkAPIClientTests CMUX_SKIP_ZIG_BUILD=1 test
```

---

## Phase 3: Work panel UI

**Purpose:** Depends on the Phase 1 kind/gate and the Phase 2 data plane. This is the visible deliverable — the port of the VS Code Work surface into the right rail.

### 3.1 Work panel view model

**Dependencies:** 1.1, 2.2

**Landing:** fork-only

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

**Acceptance Tests**
- Test-3.1.a: Unit — fixture load → row mapping.
- Test-3.1.b: Unit — filter/sort determinism.
- Test-3.1.c: Unit — error state.
- Test-3.1.d: Unit — superseded-request discard.
- Test-3.1.e: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'StokdWorkPanelViewModel' Sources/ cmuxTests/
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorkPanelViewModelTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 3.2 Work panel view and rail mounting

**Dependencies:** 3.1

**Landing:** fork-only

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

**Acceptance Tests**
- Test-3.2.a: Unit — mounted hierarchy is non-empty for fixtures.
- Test-3.2.b: Unit — error/empty state rendering.
- Test-3.2.c: Unit — invoker reachability for the open/focus command.
- Test-3.2.d: Regression — `rg` over the Work row files shows no `@ObservedObject`/`@EnvironmentObject`/`@StateObject`/`@Bindable`.
- Test-3.2.e: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'StokdWorkPanel|stokdWork' Sources/
! rg -n '@(ObservedObject|EnvironmentObject|StateObject|Bindable)' Sources/Stokd/Work/
rg -n 'SidebarDockActionInvoker|SidebarDockCommand' Sources/
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorkPanelViewTests CMUX_SKIP_ZIG_BUILD=1 test
```

---

## Phase 4: Default seed

**Purpose:** Runs after Phase 3 so a cold-start window seeds a tab that renders real content rather than a placeholder. Makes the §0 diagram true on first enable without thrashing later user rearrangements.

### 4.1 Seed Work into the right-rail tool tab strip

**Dependencies:** 1.2, 3.2

**Landing:** fork-only

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

**Acceptance Tests**
- Test-4.1.a: Unit — default tab order matches §0.
- Test-4.1.b: Unit — idempotent reseed / custom order preserved.
- Test-4.1.c: Unit — flag-off no-op.
- Test-4.1.d: Unit — left rail untouched.
- Test-4.1.e: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'stokdPanelsSeed|seedStokd|stokdWork' Sources/Sidebar/
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorkPanelSeedTests CMUX_SKIP_ZIG_BUILD=1 test
```

---

## Phase 5: Persistence, localization, and rollout

**Purpose:** Last phase — depends on the panel and seed existing so snapshot keys and strings are real. Closes the slice for dogfood and fixes the persistence contract the sibling PRD inherits.

### 5.1 Snapshot persistence for stokd rail membership

**Dependencies:** 3.2, 4.1

**Landing:** fork-only

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

**Acceptance Tests**
- Test-5.1.a: Unit — encode/decode round-trip.
- Test-5.1.b: Regression — schema version pin.
- Test-5.1.c: Unit — unknown-kind skip.
- Test-5.1.d: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'currentVersion' Sources/ Packages/ | rg -n 'SessionSnapshotSchema' || true
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorkPanelPersistenceTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 5.2 Localization audit and dogfood gate

**Dependencies:** 1.2, 3.2, 4.1, 5.1

**Landing:** fork-only

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
       if 'stokd' in k.lower() and 'work' in k.lower()
       and 'ja' not in v.get('localizations', {})]
assert not bad, f"missing ja: {bad}"
print("ja coverage ok")
PY
./scripts/lint-pbxproj-test-wiring.sh
git -C vendor/bonsplit status --porcelain
git -C vendor/bonsplit rev-parse HEAD
# Preferred full gate when the environment allows:
# CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag stokd-work-panel
./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorkPanelKindTests \
  -only-testing:cmuxTests/StokdRailPanelFlagTests \
  -only-testing:cmuxTests/StokdCLIRunnerTests \
  -only-testing:cmuxTests/StokdWorkAPIClientTests \
  -only-testing:cmuxTests/StokdWorkPanelViewModelTests \
  -only-testing:cmuxTests/StokdWorkPanelViewTests \
  -only-testing:cmuxTests/StokdWorkPanelSeedTests \
  -only-testing:cmuxTests/StokdWorkPanelPersistenceTests \
  CMUX_SKIP_ZIG_BUILD=1 test
```

---

## 3. Completion Criteria

- [ ] All Phase 1–5 work items' Verification Commands exit 0.
- [ ] Flag on + cold seed shows the right-rail Tools strip as Files, Find, Vault, Work.
- [ ] Work lists real tasks and projects from a local stokd workspace, with distinct empty and error states.
- [ ] Flag off: no Work tab; existing rails unchanged; left rail untouched in both states.
- [ ] Config is never written directly to yaml by the app.
- [ ] en+ja strings present; pbxproj test wiring clean; bonsplit clean and at the pinned SHA.
- [ ] `SessionSnapshotSchema.currentVersion` unchanged.
- [ ] The foundation (kind surface, gate, data plane, persistence rules) is reusable as-is by `.stokd/projects/stokd-rail-panels-first-slice/prd.md` — no Work-only naming that would force a rewrite there.

---

## 4. Rollout & Validation

### Rollout Strategy

- Ship behind the beta flag (default off).
- Enable on dogfood machines first via Settings / `cmux.json` beta key.
- Rollback: set the flag false — the Work tab disappears; non-stokd rails remain.

### Post-Launch Validation

- Open the tagged Debug app with the flag on; confirm the §0 tab strip.
- Exercise the Work list against a real local stokd workspace with at least one task and one project.
- Stop the local stokd API; confirm the error state renders with readable text and no crash.
- Reorder the tool tabs, quit, relaunch; confirm the custom order survives.
- Toggle the flag off and back on; confirm no duplicate Work tab appears.

---

## 5. Open Questions

1. Shared rail flag (Option A) vs dedicated `gdock.sidebar.beta.stokdPanels.enabled` (Option B) — Phase 1.2 decides; default Option A if unanswered.
2. Does Work need write actions (start/complete/note) in v1, or list + open only? Default: list + open only; write actions are a follow-up.
3. Should Work fall back to `stokd task list --json` / `stokd project list --json` via the CLI runner when the local API is down? Default: no fallback in v1 — show the error state; revisit after dogfood.

If unanswered at implement time: take the defaults above and record the choice in project notes.