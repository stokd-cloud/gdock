# PRD: Stokd Global Config Panel (gdock left rail)

## 0. Source Context

**Derived From:** Sliced out of `.stokd/projects/stokd-rail-panels-first-slice/prd.md` on 2026-08-09 — the remaining three-panel PRD is being split so Worktrees, Global Config, and Usage can land independently.
**Feature Name:** Stokd Global Config Panel
**PRD Owner:** Brian Stoker
**Last Updated:** 2026-08-09
**Repository:** `stokd-cloud/ghostty-dock` (fork of `manaflow-ai/cmux`), branch `main`
**Landing:** fork-only on `main`
**Prerequisite:** `docs/stokd-work-panel.prd.md` — the Work panel PRD **owns** the shared foundation (stokd rail panel-kind surface, the `sidebar.beta.dock.enabled` gate for stokd panels, the stokd CLI runner, and the additive snapshot persistence rules). This PRD consumes that foundation unchanged and re-specifies none of it.

### Summary

Port the **Global Config** surface from the stokd VS Code extension into gdock as a **left-rail section**, hosted on the existing rail system behind the same beta gate as Work. The section renders a schema-driven settings UI from the stokd CLI's own config schema, shows the effective value with its layer provenance, and writes changes back **only** through `stokd config set`.

The load-bearing rule is the write path: gdock never touches `config.yaml` with `FileManager`. The CLI owns validation, layering, and file format; the panel constructs argv and nothing else. That keeps one writer for stokd configuration and means a gdock version can never corrupt a config a newer CLI understands.

### Charter

**Mission.** Give a gdock user the stokd configuration surface in the left rail, with the CLI as the
only writer, so that reading and changing stokd settings never requires leaving the terminal and
never risks a config file gdock does not fully understand.

**Why this is worth doing.** Configuration is the one stokd surface where a wrong write costs the
user state that lives outside gdock. Today that state is only reachable through the CLI or an editor;
a panel that reads the schema but writes through anything other than `stokd config set` would trade a
small convenience for a class of corruption the user cannot undo from the app.

**What success looks like.** A schema-driven form that shows every field the CLI declares — including
ones this gdock build has never seen — with its effective value and layer, where each edit is one
auditable `stokd config set` invocation with an explicit scope, and a rejected edit leaves the
previous value on screen with the CLI's own message.

**What we will not do.** We will not reimplement stokd's schema, validation, defaults, or file
format; we will not write configuration files directly; and we will not let the global scope be
reached by accident.

**Boundaries.** Fork-only, left rail only, behind the existing beta gate, consuming the foundation
owned by `docs/stokd-work-panel.prd.md` without redefining any of it.

### Source inventory (read-only)

| Source | Role |
|---|---|
| `docs/stokd-work-panel.prd.md` | **Prerequisite PRD** — panel-kind surface, gate, CLI runner, snapshot rules |
| `.stokd/projects/stokd-widgets-global-config-per-model-token-usage/prd.md` | Behavior inventory for Global Config |
| `.stokd/projects/dockable-sidebar-spaces-and-quad-split/prd.md` | Authoritative rail substrate (sections, collapse, resize, persistence) |
| Live `main` | `Sources/Sidebar/SidebarDock*`, `Sources/Stokd/` |

### Default layout (load-bearing)

```
LEFT RAIL
┌─────────────────────────┐
│ Section: Workspaces     │  (existing, stays on top)
├─────────────────────────┤
│ Section: Global Config  │  ← this PRD, stokd rank 1
├─────────────────────────┤
│ …stokd rank 2…          │  (Worktrees, when landed)
├─────────────────────────┤
│ …stokd rank 3…          │  (Usage, when landed)
└─────────────────────────┘
```

Global Config seeds at **stokd section rank 1**, directly below the workspaces section. The three left-rail panels land independently, so seeding is rank-ordered rather than positional: any landing order composes into the same documented layout.

## 1. Objectives & Constraints

### Objectives

- Register the `stokdGlobalConfig` panel kind as an addition to the existing stokd kind surface, allowed on the left rail and rejected on the right.
- Read the config schema from the stokd CLI and render a schema-driven form, degrading unknown field types to read-only rather than hiding them.
- Show the effective value and its layer provenance (global vs workspace) for each field.
- Write exclusively through `stokd config set` with an explicit scope, defaulting to the workspace scope.
- Seed the section once at stokd rank 1 without disturbing user layout or other stokd sections.
- Persist section state via the prerequisite's additive snapshot rules; ship localized en+ja strings behind the existing beta gate.

### Constraints

- **Fork-only** on `stokd-cloud/ghostty-dock` `main`.
- **Prerequisite:** `docs/stokd-work-panel.prd.md` must land first; its panel-kind surface, beta gate, CLI runner, and snapshot rules are consumed unchanged and never redefined here.
- **The app never writes stokd configuration files.** All writes construct `stokd config set` argv; no `FileManager`/`Data.write` to `config.yaml` on any path. YAML may be read for layer provenance, read-only.
- Scope is explicit on every write: workspace by default; the global scope requires a deliberate user switch, never an implicit fallback.
- **Left rail only** — no right-rail or tool-tab-strip changes.
- **Rail host only** — no freeform canvas dock-anywhere.
- **Beta-gated**, default off, reusing `sidebar.beta.dock.enabled`; no new flag.
- Schema and value reads run off the main actor through the prerequisite's process boundary.
- All user-facing strings localized en+ja via `String(localized:)` / `Resources/Localizable.xcstrings`. Schema-supplied field labels and descriptions come from the CLI and are rendered as-is; only gdock's own chrome is localized.
- New tests wired into `cmux.xcodeproj`; `./scripts/lint-pbxproj-test-wiring.sh` green.
- SwiftUI snapshot-boundary and no-state-mutation-in-body rules apply (see `CLAUDE.md`).
- Bonsplit submodule SHA unchanged and worktree clean.

### Scope Inventory

- The `stokdGlobalConfig` kind, its left-rail placement entry, and its section title under `Sources/Sidebar/SidebarDock*`.
- A config boundary under `Sources/Stokd/Config/`: schema decoding, layered value reads, provenance, and the CLI-argv writer.
- The left-rail Global Config section, including loading, populated, CLI-missing, and error states, plus per-field pending/failed write states.
- Left-rail seeding at stokd rank 1 and the associated snapshot round-trip.
- Localized en+ja strings for gdock chrome in `Resources/Localizable.xcstrings`.
- Focused Swift tests under `cmuxTests/`, explicit Xcode test-target wiring, and tagged dogfood.

### Non-Goals

- Work, Worktrees, and Usage panels, each of which has its own PRD.
- A gdock-side config schema, validation rules, or default values — the CLI owns all three.
- Editing arbitrary YAML by hand, importing/exporting config files, or migrating config versions.
- Agents, Agent chat (ACP), Reviews, Current Activity, Model Configuration, or Workload Configuration.
- Widget-tile chrome, Socket.IO realtime as a hard requirement, or freeform canvas docking.
- Upstream cmux PRs, `vendor/bonsplit` changes, or a second stokd CLI runner.

---

## 1.5 Required Toolchain

| Tool | Min Version | Install Command | Verify Command |
|------|-------------|-----------------|----------------|
| macOS | 14.0 | (OS) | `sw_vers -productVersion` |
| Xcode | 15.0 | App Store | `xcodebuild -version` |
| Swift | 6.0 | (bundled with Xcode) | `swift --version` |
| stokd CLI | current | `curl -fsSL https://stokd.cloud/install \| sh` | `stokd config schema --json` |
| Python 3 | 3.9 | Xcode CLT | `python3 --version` |

Working directory for all Verification Commands: ghostty-dock repo root.

```bash
./scripts/setup.sh   # once per machine if GhosttyKit missing
```

Prefer `CMUX_SKIP_ZIG_BUILD=1` on tagged reloads when host zig is not 0.15.2.

---

## 2. Contract

**VAL-CFGKIND-001** — Global Config is a stable left-rail section kind.
Surface: library
Needs: the panel-kind surface and placement matrix from `docs/stokd-work-panel.prd.md`
Behavior: With the rail gate enabled, gdock can address `stokdGlobalConfig` by a stable persisted
  value, place it on the left rail, reject it on the right rail, and ignore unknown persisted kinds
  without crashing.
Evidence: Persist the RED → GREEN results from `StokdGlobalConfigPanelKindTests` and the Xcode
  test-wiring lint output in the phase evidence.
Fail: A persisted layout containing an older or unknown stokd kind crashes the app or silently
  drops the user's whole left rail.
Rigor: R2
Why: The kind is shared persistence and placement infrastructure, so an independent validator must
  confirm the focused regression suite rather than relying on implementer inspection.

**VAL-CFGSCHEMA-001** — The settings form is driven by the CLI's own schema.
Surface: cli
Needs: VAL-CFGKIND-001 and the CLI runner from `docs/stokd-work-panel.prd.md`
Behavior: Given `stokd config schema --json` output, gdock renders the declared field groups with
  each field's effective value and layer provenance; unknown field types render read-only rather
  than being dropped, and a missing CLI yields an explanatory state rather than an empty form.
Evidence: Persist the RED → GREEN results from `StokdConfigSchemaTests` for a multi-group schema
  fixture, an unknown-type fixture, and the CLI-missing path.
Fail: A field the CLI declares is silently missing from the form, so the user believes a setting
  does not exist.
Rigor: R2
Why: Silently dropping a field the CLI declares is an invisible defect, so schema fidelity needs
  independent fixture-based validation.

**VAL-CFGWRITE-001** — Configuration is written only through the CLI, with an explicit scope.
Surface: cli
Needs: VAL-CFGSCHEMA-001
Behavior: Editing a field issues exactly one `stokd config set` invocation carrying the field key,
  the new value, and an explicit scope defaulting to workspace; no gdock code path writes
  `config.yaml` directly, and a failed write surfaces the CLI's message and restores the prior
  displayed value.
Evidence: Persist the RED → GREEN results from `StokdConfigWriterTests` (argv shape, scope default,
  global-scope opt-in, failure rollback) plus the direct-write source scan from the work item's
  Verification Commands.
Fail: gdock writes `config.yaml` itself, or writes to the global scope when the user meant the
  workspace, corrupting or silently redirecting configuration the user cannot repair from the app.
Rigor: R3
Why: A wrong write corrupts user configuration outside gdock's own state and is not fully
  recoverable from the app, so this assertion owes sealed gate evidence in addition to an
  independent validator.

**VAL-CFGUI-001** — Users can read and change settings without blank chrome or lost edits.
Surface: artifact
Needs: VAL-CFGSCHEMA-001 and VAL-CFGWRITE-001
Behavior: The Global Config section renders identifiable loading, populated, CLI-missing, and error
  content; an in-flight edit shows a pending state, a rejected edit shows the failure and the prior
  value, and every entrypoint reaches the section through the one shared SidebarDock action path.
Evidence: Persist the RED → GREEN `StokdGlobalConfigPanelViewTests` results, the snapshot-boundary
  source scan, and tagged dogfood evidence showing the mounted section states.
Fail: An edit appears to succeed while the CLI rejected it, leaving the screen showing a value
  that is not the stored value.
Rigor: R2
Why: The actor-facing SwiftUI surface needs independent test and dogfood confirmation that no state
  renders blank and no edit is silently dropped.

**VAL-CFGSEED-001** — First enable seeds Global Config once at rank 1 without disturbing user layout.
Surface: library
Needs: VAL-CFGUI-001 and the seed-generation marker from `docs/stokd-work-panel.prd.md`
Behavior: On first gated enable the Global Config section appears directly below the workspaces
  section at stokd rank 1; later launches preserve user order, never duplicate the section, never
  reorder other stokd sections, and never modify the right rail.
Evidence: Persist the RED → GREEN `StokdGlobalConfigPanelSeedTests` results for initial seed,
  reseed, customized order, gate-off behavior, rank composition against rank-2 and rank-3 sections,
  and right-rail invariance.
Fail: Relaunching duplicates the section or resets a layout the user arranged by hand.
Rigor: R2
Why: Seed mutations can silently overwrite user customization and must compose correctly with
  sibling panels landing in any order, which needs independent regression validation.

**VAL-CFGPERSIST-001** — Global Config rail membership round-trips additively.
Surface: library
Needs: VAL-CFGSEED-001 and the additive snapshot rules from `docs/stokd-work-panel.prd.md`
Behavior: A Global-Config-inclusive left-rail layout round-trips membership, order, collapse, and
  extent through additive optional snapshot fields while retaining schema version 1 and skipping
  unknown kinds.
Evidence: Persist the RED → GREEN `StokdGlobalConfigPanelPersistenceTests` results and the
  schema-version source check.
Fail: Section state is lost on relaunch, or a schema-version bump strands older snapshots.
Rigor: R2
Why: Session restoration is durable user state and needs independent round-trip validation.

**VAL-CFGROLL-001** — The localized Global Config panel is buildable and ready for gated dogfood.
Surface: artifact
Needs: VAL-CFGUI-001, VAL-CFGSEED-001, and VAL-CFGPERSIST-001
Behavior: A tagged gdock build presents localized en+ja chrome around the schema-supplied labels,
  opens and focuses the section through the shared action path, and leaves the pinned bonsplit
  submodule unchanged and clean.
Evidence: Persist the localization audit, focused suite output, test-wiring lint, bonsplit
  SHA/status, and the tagged `reload.sh` build result.
Fail: The panel ships with untranslated chrome or an unbuildable tagged app.
Rigor: R2
Why: Release readiness combines source catalogs, build output, and repository integrity and should
  be independently validated as one terminal artifact gate.

## 3. Execution Topology

## Phase 1: Kind and placement

**Purpose:** Nothing can be read, mounted, seeded, or persisted until `stokdGlobalConfig` exists in the rail registry and placement matrix. This phase adds identity and wiring only — no section body yet.

### 1.1 Register the stokdGlobalConfig left-rail kind

**Targets:** VAL-CFGKIND-001
**Dependencies:** []

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Extend the existing stokd rail panel identity surface (introduced by `docs/stokd-work-panel.prd.md`, following the `PanelType` / `RightSidebarMode` conventions used by `SidebarDockStore`) with `stokdGlobalConfig`. Casing follows existing conventions; the **raw value must be stable** because it is persisted.
- Update `SidebarDockPlacementMatrix` (or equivalent) so `stokdGlobalConfig` is allowed on the **left** rail as a section and rejected on the right rail. Do not modify right-rail entries owned by the prerequisite.
- Reuse the prerequisite's `sidebar.beta.dock.enabled` gate as-is; introduce no new flag key.
- Provide a localized section title key; scaffold a placeholder section host that compiles and mounts without crashing (real UI in Phase 3).
- Failure modes: unknown kind in a persisted snapshot → skip + log, never crash; gate off → the kind is not offered in seed, palette, or section menu.

**Acceptance Criteria**
- AC-1.1.a: `stokdGlobalConfig` exists with a stable raw value → the rail registry can address it.
- AC-1.1.b: Placement matrix allows `stokdGlobalConfig` on the left rail and rejects it on the right.
- AC-1.1.c: Decoding a snapshot containing an unrecognized stokd kind drops only that entry and does not crash.
- AC-1.1.d: No new beta flag key is introduced by this PRD.
- AC-1.1.e: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdGlobalConfigPanelKindTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.
- AC-1.1.f: `./scripts/lint-pbxproj-test-wiring.sh` → exit 0 for the new test file.

**Acceptance Tests**
- Test-1.1.a: Unit — the kind registry exposes `stokdGlobalConfig`; existing kinds unchanged.
- Test-1.1.b: Unit — placement matrix edge cases (left allowed, right rejected).
- Test-1.1.c: Unit — unknown-kind decode is skipped, not fatal.
- Test-1.1.d: Regression — no new flag key in source.
- Test-1.1.e: Suite gate for AC-1.1.e.
- Test-1.1.f: Regression — pbxproj test wiring script.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'stokdGlobalConfig' Sources/
test -f cmuxTests/StokdGlobalConfigPanelKindTests.swift
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdGlobalConfigPanelKindTests CMUX_SKIP_ZIG_BUILD=1 test
```

---

## Phase 2: Config access

**Purpose:** Cannot start before Phase 1 because the section host must exist to consume it; must finish before Phase 3 because the form is a thin view over the schema and writer boundary. The read and write halves are separate work items because the write half carries the higher rigor.

### 2.1 Schema and layered value reads

**Targets:** VAL-CFGSCHEMA-001
**Dependencies:** ["1.1"]

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Add a config read boundary under `Sources/Stokd/Config/` that invokes `stokd config schema --json` through the prerequisite's CLI runner, off the main actor, scoped to the active workspace working directory.
- Decode the schema into value types: groups, fields, declared type, key path, description, and default. Unknown/unsupported declared types decode into a `readOnly(rawValue:)` case — **never dropped**.
- Read effective values and their layer provenance (global vs workspace). Layered YAML may be parsed **read-only** for provenance when the CLI does not supply it.
- Failure modes: CLI missing → `cliUnavailable` state carrying the resolver's 127 error, distinct from an empty schema; malformed JSON → structured decode error naming the offending group; timeout → error state, never a hang.

**Acceptance Criteria**
- AC-2.1.a: A multi-group schema fixture decodes into the expected groups and fields with key paths preserved.
- AC-2.1.b: A fixture containing an unrecognized declared type yields a `readOnly` field rather than dropping it — decoded field count equals the fixture's field count.
- AC-2.1.c: Effective values carry their layer provenance for a fixture with both a global and a workspace layer.
- AC-2.1.d: A missing CLI yields `cliUnavailable`, distinct from an empty-schema result.
- AC-2.1.e: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdConfigSchemaTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

**Acceptance Tests**
- Test-2.1.a: Unit — schema decode, groups and key paths.
- Test-2.1.b: Unit — unknown type degrades to read-only, count preserved.
- Test-2.1.c: Unit — layer provenance.
- Test-2.1.d: Unit — CLI-missing state.
- Test-2.1.e: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'config schema --json' Sources/Stokd/
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdConfigSchemaTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 2.2 CLI-mediated config writer

**Targets:** VAL-CFGWRITE-001
**Dependencies:** ["2.1"]

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Add a writer that turns a field edit into exactly one `stokd config set <key> <value>` invocation with an explicit scope flag. Workspace scope is the default; global scope requires a deliberate user switch and is never an implicit fallback.
- The writer's public surface returns constructed argv plus the process result so tests assert argv without executing anything.
- **No file writes.** No `FileManager`, `Data.write`, or `String.write` targeting `config.yaml` anywhere under `Sources/Stokd/Config/`. Enforced by a regression grep in the Verification Commands, not by convention alone.
- Optimistic UI contract: record the previous value and a request id before issuing the write; on success reconcile from the CLI's authoritative read-back; on failure roll back to the previous value and surface the CLI's stderr message.
- Failure modes: non-zero exit → rollback + message; CLI missing → the same `cliUnavailable` state as reads, with no partial mutation.

**Acceptance Criteria**
- AC-2.2.a: A string, a boolean, and a numeric edit each construct exactly one `stokd config set` argv with the expected key, value, and scope flag.
- AC-2.2.b: The default scope is workspace; global scope appears in argv only when explicitly selected.
- AC-2.2.c: A non-zero CLI exit rolls the displayed value back to the previous value and surfaces the CLI message.
- AC-2.2.d: No source under `Sources/Stokd/Config/` writes `config.yaml` — the direct-write grep returns no matches.
- AC-2.2.e: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdConfigWriterTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

**Acceptance Tests**
- Test-2.2.a: Unit — argv shape across three value types.
- Test-2.2.b: Unit — scope default and explicit global opt-in.
- Test-2.2.c: Unit — failure rollback and message surfacing.
- Test-2.2.d: Regression — direct-write scan.
- Test-2.2.e: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'stokd config set|"config", "set"' Sources/Stokd/Config/
! rg -n 'FileManager|Data\.write|String\.write' Sources/Stokd/Config/ | rg -n 'config\.ya?ml'
! rg -n 'config\.ya?ml' Sources/Stokd/Config/Writer*.swift
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdConfigWriterTests CMUX_SKIP_ZIG_BUILD=1 test
```

---

## Phase 3: Section UI

**Purpose:** Depends on the Phase 1 kind and the Phase 2 read/write boundary. This is the visible deliverable — the port of the VS Code Global Config surface into the left rail.

### 3.1 Global Config section view and rail mounting

**Targets:** VAL-CFGUI-001
**Dependencies:** ["2.2"]

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Implement the SwiftUI body and wire it as left-rail section content for `stokdGlobalConfig`, replacing the Phase 1 placeholder.
- Render one control per schema field type (toggle, text, number, enum picker) and a read-only row for degraded types, grouped as the schema declares, each showing its layer provenance.
- Rows carry value snapshots plus closure action bundles only — reference pattern: `IndexSectionActions` / `SectionGapActions` in `Sources/SessionIndexView.swift`. No store references below the list boundary; no state mutation inside view-body computations.
- Section actions (open, focus, refresh, scope switch) route through the existing `SidebarDockActionInvoker` → `SidebarDockCommand.perform` path so palette, context menu, and section menu share one implementation.
- Failure modes: every state (loading, populated, CLI-missing, error) renders identifiable content; a field with a pending write shows a pending affordance and is not editable twice concurrently.

**Acceptance Criteria**
- AC-3.1.a: Mounting `stokdGlobalConfig` with a fixture-backed schema renders at least one field group and a non-empty view hierarchy.
- AC-3.1.b: Loading, populated, CLI-missing, and error states each render identifiable, non-blank content.
- AC-3.1.c: A field with an in-flight write exposes a pending state and rejects a concurrent second edit.
- AC-3.1.d: Section actions resolve through `SidebarDockActionInvoker`/`SidebarDockCommand` from every entrypoint — no duplicated open logic.
- AC-3.1.e: No type below the field list holds an `ObservableObject`/`@Observable` reference (snapshot-boundary rule).
- AC-3.1.f: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdGlobalConfigPanelViewTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

**Acceptance Tests**
- Test-3.1.a: Unit — mounted hierarchy renders a field group for fixtures.
- Test-3.1.b: Unit — all four state renderings.
- Test-3.1.c: Unit — pending-write state and concurrent-edit rejection.
- Test-3.1.d: Unit — invoker reachability for section actions.
- Test-3.1.e: Regression — `rg` over the field-row files shows no store property wrappers.
- Test-3.1.f: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'StokdGlobalConfigPanel|stokdGlobalConfig' Sources/
! rg -n '@(ObservedObject|EnvironmentObject|StateObject|Bindable)' Sources/Stokd/Config/
rg -n 'SidebarDockActionInvoker|SidebarDockCommand' Sources/Stokd/Config/
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdGlobalConfigPanelViewTests CMUX_SKIP_ZIG_BUILD=1 test
```

---

## Phase 4: Default seed

**Purpose:** Runs after Phase 3 so a cold-start window seeds a section that renders real content rather than a placeholder, and so rank composition can be tested against a real mounted section.

### 4.1 Seed Global Config at stokd rank 1

**Targets:** VAL-CFGSEED-001
**Dependencies:** ["3.1"]

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Extend `SidebarDockSeeding` (or sibling) so that when the gate is on and the stokd seed generation has not been applied for this kind, a Global Config section is inserted into the left rail directly below the workspaces section.
- **Rank-ordered insertion:** stokd left-rail sections carry a rank (**Global Config = 1**, Worktrees = 2, Usage = 3). Insertion positions Global Config before any higher-ranked stokd section, so the three panels compose into the documented order regardless of landing order.
- Advance the prerequisite's shared seed-generation marker rather than adding a second marker.
- Gate off: the seed path no-ops for stokd kinds. The right rail is never modified.
- Failure modes: partial seed failure leaves non-stokd rails intact; log and continue.

**Acceptance Criteria**
- AC-4.1.a: Seeding an empty registry with the gate on places Global Config directly below the workspaces section.
- AC-4.1.b: Seeding into a rail that already has a rank-2 or rank-3 stokd section places Global Config before it.
- AC-4.1.c: A second seed call does not duplicate the section and does not reset a customized order.
- AC-4.1.d: Gate off → seed introduces no stokd kinds.
- AC-4.1.e: Seeding leaves the right-rail tool tab strip identical to its pre-seed state.
- AC-4.1.f: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdGlobalConfigPanelSeedTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

**Acceptance Tests**
- Test-4.1.a: Unit — default placement below workspaces.
- Test-4.1.b: Unit — rank composition against rank-2 and rank-3 neighbours.
- Test-4.1.c: Unit — idempotent reseed / custom order preserved.
- Test-4.1.d: Unit — gate-off no-op.
- Test-4.1.e: Unit — right rail untouched.
- Test-4.1.f: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'stokdPanelsSeed|seedStokd|stokdGlobalConfig' Sources/Sidebar/
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdGlobalConfigPanelSeedTests CMUX_SKIP_ZIG_BUILD=1 test
```

---

## Phase 5: Persistence, localization, and rollout

**Purpose:** Last phase — depends on the section and seed existing so snapshot keys and strings are real. Closes the slice for dogfood.

### 5.1 Snapshot persistence for the Global Config section

**Targets:** VAL-CFGPERSIST-001
**Dependencies:** ["4.1"]

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Persist left-rail membership, order, collapse state, and extent for `stokdGlobalConfig` using the **additive optional** snapshot rules established by the prerequisite PRD — **never** bump `SessionSnapshotSchema.currentVersion` and never add a `SessionWorkspaceLayoutSnapshot` case.
- Field values are **not** snapshot state: they are always re-read from the CLI on mount, so a stale snapshot can never present a wrong configuration value.
- Round-trip: seed layout → encode → decode → equal membership, order, collapse, and extent.
- Failure modes: unknown future kind → skip; corrupt optional → fall back to the default seed once.

**Acceptance Criteria**
- AC-5.1.a: Round-trip of a Global-Config-inclusive layout preserves membership, order, collapse, and extent.
- AC-5.1.b: `SessionSnapshotSchema.currentVersion` is unchanged from the pre-phase baseline (remains 1).
- AC-5.1.c: No config field value is persisted into the snapshot — the encoded payload contains no schema key paths.
- AC-5.1.d: A snapshot containing an unknown stokd kind decodes with that entry skipped and no crash.
- AC-5.1.e: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdGlobalConfigPanelPersistenceTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

**Acceptance Tests**
- Test-5.1.a: Unit — encode/decode round-trip.
- Test-5.1.b: Regression — schema version pin.
- Test-5.1.c: Unit — no field values in the encoded snapshot.
- Test-5.1.d: Unit — unknown-kind skip.
- Test-5.1.e: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'currentVersion' Sources/ Packages/ | rg -n 'SessionSnapshotSchema'
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdGlobalConfigPanelPersistenceTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 5.2 Localization audit and dogfood gate

**Targets:** VAL-CFGROLL-001
**Dependencies:** ["5.1"]

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Every new user-facing gdock string uses `String(localized:)` with en+ja entries in `Resources/Localizable.xcstrings`, `state == translated`, and `ja != en` for non-identical natural text. Covered surfaces: section title, scope switcher, provenance labels, pending/failed write text, CLI-missing and error states. Schema-supplied field labels come from the CLI and are exempt — document that exemption in the audit note.
- Palette and debug can open and focus Global Config through the same invoker path as other rail sections.
- Tagged dogfood: `CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag stokd-global-config-panel` builds; with the gate on, a cold window shows the section directly below workspaces.
- Bonsplit clean: `git -C vendor/bonsplit status --porcelain` empty; pinned SHA unchanged.

**Acceptance Criteria**
- AC-5.2.a: Every new Global Config chrome string key exists in both en and ja with `state == translated`.
- AC-5.2.b: No bare English literal appears in new Global Config Swift sources' `Text(`/`Button(`/alert titles, except documented schema-supplied values.
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
       if 'globalconfig' in k.lower().replace('.', '')
       and 'ja' not in v.get('localizations', {})]
assert not bad, f"missing ja: {bad}"
print("ja coverage ok")
PY
./scripts/lint-pbxproj-test-wiring.sh
git -C vendor/bonsplit status --porcelain
git -C vendor/bonsplit rev-parse HEAD
# Preferred full gate when the environment allows:
# CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag stokd-global-config-panel
./scripts/test-unit.sh -only-testing:cmuxTests/StokdGlobalConfigPanelKindTests \
  -only-testing:cmuxTests/StokdConfigSchemaTests \
  -only-testing:cmuxTests/StokdConfigWriterTests \
  -only-testing:cmuxTests/StokdGlobalConfigPanelViewTests \
  -only-testing:cmuxTests/StokdGlobalConfigPanelSeedTests \
  -only-testing:cmuxTests/StokdGlobalConfigPanelPersistenceTests \
  CMUX_SKIP_ZIG_BUILD=1 test
```

---

## 4. Completion Criteria

- [ ] All Phase 1–5 work items' Verification Commands exit 0.
- [ ] Gate on + cold seed shows Global Config directly below the workspaces section, ordered by stokd rank against any sibling stokd sections present.
- [ ] The form renders every field the CLI schema declares, degrading unknown types to read-only, each showing layer provenance.
- [ ] Every write is a `stokd config set` invocation with an explicit scope; no gdock path writes `config.yaml`.
- [ ] A rejected write rolls back the displayed value and surfaces the CLI message.
- [ ] Gate off: no Global Config section; existing rails unchanged; the right rail is untouched in both states.
- [ ] en+ja chrome strings present; pbxproj test wiring clean; bonsplit clean and at the pinned SHA.
- [ ] `SessionSnapshotSchema.currentVersion` unchanged and no field values persisted.
- [ ] The prerequisite `docs/stokd-work-panel.prd.md` has landed and its foundation is consumed unchanged.

---

## 5. Rollout & Validation

### Rollout Strategy

- Ship behind the existing `sidebar.beta.dock.enabled` beta gate (default off).
- Enable on dogfood machines first via Settings / `cmux.json` beta key.
- Rollback: set the gate false — the Global Config section disappears; non-stokd rails remain. Configuration already written through the CLI is unaffected by rollback.

### Post-Launch Validation

- Open the tagged Debug app with the gate on; confirm the field groups match `stokd config schema --json`.
- Edit one field; confirm the value via `stokd config get` (or the CLI's read verb) and confirm it survives an app restart.
- Attempt an invalid value; confirm the CLI rejection message appears and the prior value is restored.
- Rename or remove the stokd binary from PATH; confirm the CLI-missing state rather than an empty form.
- Collapse the section, quit, relaunch; confirm collapse state and order survive.

---

## 6. Open Questions

1. Does the CLI expose layer provenance in its schema/value output, or must gdock parse YAML layers read-only for it? Default: parse read-only for provenance until the CLI exposes it.
2. Should the scope switcher be per-field or per-section? Default: per-section, with the workspace scope selected, to keep the write contract obvious.
3. Should the panel show fields the schema marks internal or deprecated? Default: hide internal, show deprecated with a marker.
