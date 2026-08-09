# PRD: Stokd Usage Panel (gdock left rail)

## 0. Source Context

**Derived From:** Sliced out of `.stokd/projects/stokd-rail-panels-first-slice/prd.md` on 2026-08-09 — the remaining three-panel PRD is being split so Worktrees, Global Config, and Usage can land independently.
**Feature Name:** Stokd Usage Panel
**PRD Owner:** Brian Stoker
**Last Updated:** 2026-08-09
**Repository:** `stokd-cloud/ghostty-dock` (fork of `manaflow-ai/cmux`), branch `main`
**Landing:** fork-only on `main`
**Prerequisite:** `docs/stokd-work-panel.prd.md` — the Work panel PRD **owns** the shared foundation (stokd rail panel-kind surface, the `sidebar.beta.dock.enabled` gate for stokd panels, the stokd CLI runner, and the additive snapshot persistence rules). This PRD consumes that foundation unchanged and re-specifies none of it.

### Summary

Port the **Usage** surface from the stokd VS Code extension into gdock as a **left-rail section**, hosted on the existing rail system behind the same beta gate as Work. The section breaks token and cost usage down per provider and per model over a selectable timespan, ingesting from the provider usage stores on disk.

Two rules carry the design. First, **ingest is incremental**: the panel watches the provider stores and folds in new records rather than re-reading everything on a timer, so a long agent session does not turn the rail into a disk-scanning loop. Second, **unmeasured is not zero**: a column a provider does not report (cache reads, reasoning tokens on providers that omit them) renders as unavailable, never as a measured `0` — a fabricated zero is worse than a blank because it reads as a fact.

### Charter

**Mission.** Show a gdock user what their agents actually cost — per provider, per model, over a
window they choose — from the usage records the providers already write, without ever touching those
records and without ever presenting a number that was not measured.

**Why this is worth doing.** Token spend is the one number in this product that is about the user's
money. A usage panel that is merely approximate is worse than no panel: it gets believed. The two
ways this surface fails are silent double counting across restarts and rendering an unreported column
as `0`, and both produce a confident wrong figure rather than a visible gap.

**What success looks like.** The table reconciles with each provider's own reported usage for the
same window; a relaunch mid-session does not move the totals; unreported columns read as unavailable;
and a long agent session does not turn the rail into a disk-scanning loop.

**What we will not do.** We will not write, rotate, compact, or normalise a provider store; we will
not estimate a price for a model we have no price for; and we will not ship budgets, alerts, or
enforcement in this slice.

**Boundaries.** Fork-only, left rail only, behind the existing beta gate, consuming the foundation
owned by `docs/stokd-work-panel.prd.md` without redefining any of it.

### Investigation Summary

This PRD was derived by slicing an existing multi-panel PRD, not by running fresh investigation
lanes. What is established, and what is not, is stated here plainly so the C3 investigation
obligation is discharged deliberately rather than assumed.

**Established from existing sources.** The behavioral inventory for per-provider/per-model token and
cost breakdown comes from `.stokd/projects/stokd-widgets-global-config-per-model-token-usage/prd.md`,
which already identified the two failure modes this contract targets: restart-unsafe provider dedupe
and unmeasured cache columns being rendered as zero. The rail substrate — sections, collapse, resize,
persistence — is established by `.stokd/projects/dockable-sidebar-spaces-and-quad-split/prd.md` and by
the live `Sources/Sidebar/SidebarDock*` code on `main`. The shared foundation this PRD consumes is
established and already landed by `docs/stokd-work-panel.prd.md`.

**Not yet established — carried as risk into Phase 2.** The on-disk shape, rotation behavior, and
per-record identity of each provider usage store have not been empirically surveyed in this
investigation; the ingest design assumes append-mostly stores with a detectable rotation, and Phase
2.1's fixtures encode that assumption rather than confirm it. Whether local price data is available
for every model in use is likewise unconfirmed (Open Question 4). Whether provider-reported totals
reconcile exactly with locally-recorded records, or only approximately, is unknown until the oracle
below is run for the first time.

**Consequence.** Phase 2.1 should begin by surveying the real stores for each configured provider and
recording what was found; if a store turns out not to be append-mostly, the ingest cursor design in
2.1 is the part that must change, and the contract assertion VAL-USEINGEST-001 stands unchanged
because it is written about outcomes, not about the mechanism.

### Source inventory (read-only)

| Source | Role |
|---|---|
| `docs/stokd-work-panel.prd.md` | **Prerequisite PRD** — panel-kind surface, gate, CLI runner, snapshot rules |
| `.stokd/projects/stokd-widgets-global-config-per-model-token-usage/prd.md` | Behavior inventory for per-model token usage |
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
│ …stokd rank 2…          │  (Worktrees, when landed)
├─────────────────────────┤
│ Section: Usage          │  ← this PRD, stokd rank 3 (bottom)
└─────────────────────────┘
```

Usage seeds at **stokd section rank 3**, the bottom of the stokd stack below the workspaces section. The three left-rail panels land independently, so seeding is rank-ordered rather than positional: any landing order composes into the same documented layout.

## 1. Objectives & Constraints

### Objectives

- Register the `stokdUsage` panel kind as an addition to the existing stokd kind surface, allowed on the left rail and rejected on the right.
- Ingest usage records incrementally from the provider stores, deduplicated across app restarts.
- Aggregate into per-provider → per-model rows for a selectable timespan, including reasoning tokens where the provider reports them.
- Render unmeasured columns as unavailable, never as a measured zero.
- Seed the section once at stokd rank 3 without disturbing user layout or other stokd sections.
- Persist section state via the prerequisite's additive snapshot rules; ship localized en+ja strings behind the existing beta gate.

### Constraints

- **Fork-only** on `stokd-cloud/ghostty-dock` `main`.
- **Prerequisite:** `docs/stokd-work-panel.prd.md` must land first; its panel-kind surface, beta gate, CLI runner, and snapshot rules are consumed unchanged and never redefined here.
- **Ingest is read-only.** The panel never writes, truncates, compacts, or reorders a provider usage store.
- **Watch over poll.** A full re-read is the fallback path only; the steady state is incremental. Any interim polling implementation must be documented in code with the watch path as the stated target.
- Ingest runs off the main actor with bounded memory: records fold into aggregates as they are read; the panel never holds the full record history in memory.
- **Left rail only** — no right-rail or tool-tab-strip changes.
- **Rail host only** — no freeform canvas dock-anywhere.
- **Beta-gated**, default off, reusing `sidebar.beta.dock.enabled`; no new flag.
- Cost figures are derived from provider-reported pricing where available; a model with no known price shows tokens with cost unavailable rather than an estimated cost.
- All user-facing strings localized en+ja via `String(localized:)` / `Resources/Localizable.xcstrings`. Numbers, currency, and dates use locale-aware formatters, not string interpolation.
- New tests wired into `cmux.xcodeproj`; `./scripts/lint-pbxproj-test-wiring.sh` green.
- SwiftUI snapshot-boundary and no-state-mutation-in-body rules apply (see `CLAUDE.md`).
- Bonsplit submodule SHA unchanged and worktree clean.

### Scope Inventory

- The `stokdUsage` kind, its left-rail placement entry, and its section title under `Sources/Sidebar/SidebarDock*`.
- A usage boundary under `Sources/Stokd/Usage/`: store discovery, incremental ingest with restart-safe dedupe, record value types, and aggregation.
- The left-rail Usage section, including loading, populated, no-stores, configured-but-unobserved, and error states, plus the timespan selector.
- Left-rail seeding at stokd rank 3 and the associated snapshot round-trip.
- Localized en+ja strings and locale-aware number/currency/date formatting.
- Focused Swift tests under `cmuxTests/`, explicit Xcode test-target wiring, and tagged dogfood.

### Non-Goals

- Work, Worktrees, and Global Config panels, each of which has its own PRD.
- Budgets, quotas, alerts, or spend enforcement.
- Charts and time-series visualisation in the first release — the deliverable is a table.
- Writing or normalising provider usage stores, or backfilling history the providers did not record.
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
| stokd CLI | current | `curl -fsSL https://stokd.cloud/install \| sh` | `stokd --version` |
| Python 3 | 3.9 | Xcode CLT | `python3 --version` |

Working directory for all Verification Commands: ghostty-dock repo root.

```bash
./scripts/setup.sh   # once per machine if GhosttyKit missing
```

Prefer `CMUX_SKIP_ZIG_BUILD=1` on tagged reloads when host zig is not 0.15.2.

---

## 2. Contract

**VAL-USEKIND-001** — Usage is a stable left-rail section kind.
Surface: library
Needs: the panel-kind surface and placement matrix from `docs/stokd-work-panel.prd.md`
Behavior: With the rail gate enabled, gdock can address `stokdUsage` by a stable persisted value,
  place it on the left rail, reject it on the right rail, and ignore unknown persisted kinds without
  crashing.
Evidence: Persist the RED → GREEN results from `StokdUsagePanelKindTests` and the Xcode test-wiring
  lint output in the phase evidence.
Fail: A persisted layout containing an older or unknown stokd kind crashes the app or silently
  drops the user's whole left rail.
Rigor: R2
Why: The kind is shared persistence and placement infrastructure, so an independent validator must
  confirm the focused regression suite rather than relying on implementer inspection.

**VAL-USEINGEST-001** — Usage ingest is incremental, read-only, and restart-safe.
Surface: data
Needs: VAL-USEKIND-001 and read access to the provider usage stores
Behavior: Given provider usage stores, gdock folds new records into its aggregates without re-reading
  consumed history, never mutates a store, and after a restart re-ingests without double-counting any
  record it already counted.
Evidence: Persist the RED → GREEN results from `StokdUsageIngestTests` covering append-only growth,
  a restart replay of an already-consumed store, a truncated/rotated store, and a byte-identical
  store checksum before and after ingest.
Oracle: the fixed-count synthetic store described in §2 Oracle — N records must ingest to exactly N
  across any sequence of restarts — with provider-reported totals as the field oracle.
Fail: A relaunch re-counts records already counted, inflating reported spend, or ingest mutates a
  provider's store and damages usage history gdock does not own.
Rigor: R3
Why: Double counting silently misstates spend and a write to a provider store damages data outside
  gdock, so this assertion owes sealed gate evidence in addition to an independent validator.

**VAL-USEAGG-001** — Aggregation reports measured values and marks the rest unavailable.
Surface: library
Needs: VAL-USEINGEST-001
Behavior: For a fixed record set and timespan, gdock produces deterministic per-provider →
  per-model rows with token and cost totals, includes reasoning tokens where reported, and renders
  any column the provider does not report as unavailable rather than as a measured zero.
Evidence: Persist the RED → GREEN results from `StokdUsageAggregationTests`, including a fixture
  whose provider omits cache columns and a fixture whose model has no known price.
Fail: A column the provider never reported renders as a measured `0`, so the user reads a
  fabricated figure as a fact.
Rigor: R2
Why: A fabricated zero is indistinguishable from a measured fact to the reader, so the
  unavailable-vs-zero distinction needs independent fixture-based validation.

**VAL-USEUI-001** — Users can read the usage breakdown without blank chrome or misleading figures.
Surface: artifact
Needs: VAL-USEAGG-001
Behavior: The Usage section renders identifiable loading, populated, no-stores,
  configured-but-unobserved, and error content, offers the timespan selector, formats numbers and
  currency for the active locale, and reaches every entrypoint through the one shared SidebarDock
  action path.
Evidence: Persist the RED → GREEN `StokdUsagePanelViewTests` results, the snapshot-boundary source
  scan, and tagged dogfood evidence showing the mounted section states.
Fail: The section renders blank chrome, or an unavailable figure renders as a number the user
  cannot distinguish from a measurement.
Rigor: R2
Why: The actor-facing SwiftUI surface needs independent test and dogfood confirmation that no state
  renders blank and no unavailable figure renders as a number.

**VAL-USESEED-001** — First enable seeds Usage once at rank 3 without disturbing user layout.
Surface: library
Needs: VAL-USEUI-001 and the seed-generation marker from `docs/stokd-work-panel.prd.md`
Behavior: On first gated enable the Usage section appears at the bottom of the stokd stack below the
  workspaces section at rank 3; later launches preserve user order, never duplicate the section,
  never reorder other stokd sections, and never modify the right rail.
Evidence: Persist the RED → GREEN `StokdUsagePanelSeedTests` results for initial seed, reseed,
  customized order, gate-off behavior, rank composition against rank-1 and rank-2 sections, and
  right-rail invariance.
Fail: Relaunching duplicates the section or resets a layout the user arranged by hand.
Rigor: R2
Why: Seed mutations can silently overwrite user customization and must compose correctly with
  sibling panels landing in any order, which needs independent regression validation.

**VAL-USEPERSIST-001** — Usage rail membership round-trips additively.
Surface: library
Needs: VAL-USESEED-001 and the additive snapshot rules from `docs/stokd-work-panel.prd.md`
Behavior: A Usage-inclusive left-rail layout round-trips membership, order, collapse, extent, and the
  selected timespan through additive optional snapshot fields while retaining schema version 1 and
  skipping unknown kinds.
Evidence: Persist the RED → GREEN `StokdUsagePanelPersistenceTests` results and the schema-version
  source check.
Fail: Section state or the selected timespan is lost on relaunch, or a schema-version bump
  strands older snapshots.
Rigor: R2
Why: Session restoration is durable user state and needs independent round-trip validation.

**VAL-USEROLL-001** — The localized Usage panel is buildable and ready for gated dogfood.
Surface: artifact
Needs: VAL-USEUI-001, VAL-USESEED-001, and VAL-USEPERSIST-001
Behavior: A tagged gdock build presents localized en+ja Usage strings with locale-aware number and
  currency formatting, opens and focuses the section through the shared action path, and leaves the
  pinned bonsplit submodule unchanged and clean.
Evidence: Persist the localization audit, focused suite output, test-wiring lint, bonsplit
  SHA/status, and the tagged `reload.sh` build result.
Fail: The panel ships with untranslated strings, locale-wrong number formatting, or an
  unbuildable tagged app.
Rigor: R2
Why: Release readiness combines source catalogs, build output, and repository integrity and should
  be independently validated as one terminal artifact gate.

### Oracle

The adjudicator for usage figures is **each provider's own reported usage for the same window** —
the provider's dashboard or usage API, not a gdock-side recomputation. A row is correct when gdock's
total for a provider/model/window matches that provider's reported total for the same window within
the tolerance recorded below; a disagreement is a defect in this panel until proven otherwise.

- **Reconciliation window:** a complete UTC day that has closed, so neither side is still accruing.
- **Tolerance:** exact match on token counts. Cost may differ by rounding only; any divergence beyond
  rounding is treated as a pricing-table defect and the affected cells must render cost as
  unavailable rather than as a disputed number.
- **Records not written by a provider are out of scope for the oracle:** if a provider does not report
  a column, there is nothing to reconcile and the cell is `unavailable` by construction.
- **Fixed-count secondary oracle for ingest:** for a synthetic store of exactly N records, the
  ingested count must equal N after any sequence of restarts and re-ingests. This is the oracle that
  adjudicates VAL-USEINGEST-001 in CI, where no provider dashboard is reachable.

## 3. Execution Topology

## Phase 1: Kind and placement

**Purpose:** Nothing can be ingested, mounted, seeded, or persisted until `stokdUsage` exists in the rail registry and placement matrix. This phase adds identity and wiring only — no section body yet.

### 1.1 Register the stokdUsage left-rail kind

**Targets:** VAL-USEKIND-001
**Dependencies:** []

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Extend the existing stokd rail panel identity surface (introduced by `docs/stokd-work-panel.prd.md`, following the `PanelType` / `RightSidebarMode` conventions used by `SidebarDockStore`) with `stokdUsage`. Casing follows existing conventions; the **raw value must be stable** because it is persisted.
- Update `SidebarDockPlacementMatrix` (or equivalent) so `stokdUsage` is allowed on the **left** rail as a section and rejected on the right rail. Do not modify right-rail entries owned by the prerequisite.
- Reuse the prerequisite's `sidebar.beta.dock.enabled` gate as-is; introduce no new flag key.
- Provide a localized section title key; scaffold a placeholder section host that compiles and mounts without crashing (real UI in Phase 3).
- Failure modes: unknown kind in a persisted snapshot → skip + log, never crash; gate off → the kind is not offered in seed, palette, or section menu.

**Acceptance Criteria**
- AC-1.1.a: `stokdUsage` exists with a stable raw value → the rail registry can address it.
- AC-1.1.b: Placement matrix allows `stokdUsage` on the left rail and rejects it on the right.
- AC-1.1.c: Decoding a snapshot containing an unrecognized stokd kind drops only that entry and does not crash.
- AC-1.1.d: No new beta flag key is introduced by this PRD.
- AC-1.1.e: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdUsagePanelKindTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.
- AC-1.1.f: `./scripts/lint-pbxproj-test-wiring.sh` → exit 0 for the new test file.

**Acceptance Tests**
- Test-1.1.a: Unit — the kind registry exposes `stokdUsage`; existing kinds unchanged.
- Test-1.1.b: Unit — placement matrix edge cases (left allowed, right rejected).
- Test-1.1.c: Unit — unknown-kind decode is skipped, not fatal.
- Test-1.1.d: Regression — no new flag key in source.
- Test-1.1.e: Suite gate for AC-1.1.e.
- Test-1.1.f: Regression — pbxproj test wiring script.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'stokdUsage' Sources/
test -f cmuxTests/StokdUsagePanelKindTests.swift
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdUsagePanelKindTests CMUX_SKIP_ZIG_BUILD=1 test
```

---

## Phase 2: Usage ingest and aggregation

**Purpose:** Cannot start before Phase 1 because the section host must exist to consume it; must finish before Phase 3 because the table is a thin view over these aggregates. Ingest and aggregation are separate work items because ingest carries the higher rigor and must be provably non-destructive before anything reads through it.

### 2.1 Incremental, restart-safe usage ingest

**Targets:** VAL-USEINGEST-001
**Dependencies:** ["1.1"]

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Add an ingest service under `Sources/Stokd/Usage/` that discovers configured provider usage stores, opens them **read-only**, and folds records into aggregates off the main actor.
- **Watch, don't poll:** register a file-system watch per store and ingest the appended delta on change. A polling fallback is permitted only when a watch cannot be established, must use a bounded interval, and must be documented in code as the fallback path.
- Restart-safe dedupe: persist a per-store ingest cursor (offset plus a content fingerprint) in gdock's own state so a relaunch resumes rather than double-counting. A fingerprint mismatch (rotation or truncation) resets that store's cursor and re-ingests it from the start exactly once.
- Bounded memory: records fold into aggregates as they are read; the full record history is never retained.
- Failure modes: no stores configured → `noStores` state; configured store missing or unreadable → `configuredButUnobserved` for that provider, with the other providers still ingesting; malformed record → skip that record, count it in a diagnostics tally, never abort the stream.

**Acceptance Criteria**
- AC-2.1.a: Appending records to a store ingests only the appended delta — the second ingest reads fewer bytes than the first for an unchanged prefix.
- AC-2.1.b: Restarting with a persisted cursor over an unchanged store yields no additional counted records (no double counting).
- AC-2.1.c: A truncated or rotated store is detected by fingerprint mismatch and re-ingested exactly once, not on every pass.
- AC-2.1.d: Store files are byte-identical before and after ingest — checksums match.
- AC-2.1.e: A malformed record is skipped and tallied without aborting ingest of the remaining records.
- AC-2.1.f: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdUsageIngestTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

**Acceptance Tests**
- Test-2.1.a: Unit — incremental delta read.
- Test-2.1.b: Unit — restart replay without double counting.
- Test-2.1.c: Unit — rotation/truncation detection and single re-ingest.
- Test-2.1.d: Regression — store checksum unchanged after ingest.
- Test-2.1.e: Unit — malformed record skip + tally.
- Test-2.1.f: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'DispatchSource|FSEvents|NSFilePresenter|watch' Sources/Stokd/Usage/
! rg -n 'Data\.write|FileHandle.*forWriting|String\.write' Sources/Stokd/Usage/
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdUsageIngestTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 2.2 Provider and model aggregation

**Targets:** VAL-USEAGG-001
**Dependencies:** ["2.1"]

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Aggregate ingested records into per-provider → per-model rows for the selected timespan (today, 7 days, 30 days, all time), carrying input, output, and reasoning token totals plus derived cost.
- Every numeric cell is a tri-state: `measured(value)`, `unavailable` (the provider does not report this column), or `unknown` (reported but unparseable). **There is no implicit zero** — a true measured zero is `measured(0)` and is distinct from `unavailable`.
- Cost derives from provider-reported pricing where available; a model with no known price yields `unavailable` cost with tokens still `measured`.
- Deterministic ordering: providers alphabetically, models by descending total tokens then by name, so the table does not reshuffle between refreshes.
- Failure modes: empty record set → empty aggregate (not an error); a provider with zero records but a configured store → a `configuredButUnobserved` row rather than omission.

**Acceptance Criteria**
- AC-2.2.a: A fixed record set produces the expected per-provider → per-model rows with deterministic ordering across repeated runs.
- AC-2.2.b: A provider fixture that omits cache columns yields `unavailable` for those cells, never `measured(0)`.
- AC-2.2.c: Reasoning tokens are included for a provider that reports them and `unavailable` for one that does not.
- AC-2.2.d: A model with no known price yields `unavailable` cost while token totals remain `measured`.
- AC-2.2.e: A configured provider with zero records appears as `configuredButUnobserved`, not omitted.
- AC-2.2.f: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdUsageAggregationTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

**Acceptance Tests**
- Test-2.2.a: Unit — aggregation and ordering determinism.
- Test-2.2.b: Unit — unavailable vs measured-zero.
- Test-2.2.c: Unit — reasoning-token coverage.
- Test-2.2.d: Unit — unknown price yields unavailable cost.
- Test-2.2.e: Unit — configured-but-unobserved provider row.
- Test-2.2.f: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'unavailable|measured' Sources/Stokd/Usage/
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdUsageAggregationTests CMUX_SKIP_ZIG_BUILD=1 test
```

---

## Phase 3: Section UI

**Purpose:** Depends on the Phase 1 kind and the Phase 2 aggregates. This is the visible deliverable — the port of the VS Code Usage surface into the left rail.

### 3.1 Usage section view and rail mounting

**Targets:** VAL-USEUI-001
**Dependencies:** ["2.2"]

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Implement the SwiftUI body and wire it as left-rail section content for `stokdUsage`, replacing the Phase 1 placeholder.
- Render a provider → model table for the selected timespan with a timespan selector in the section header. `unavailable` cells render as an em dash with an accessibility label, never as `0`.
- Locale-aware formatting: `NumberFormatter` / `FormatStyle` for token counts and currency, `DateFormatter`/`FormatStyle` for timespan labels — no manual string interpolation of numbers.
- Rows carry value snapshots plus closure action bundles only — reference pattern: `IndexSectionActions` / `SectionGapActions` in `Sources/SessionIndexView.swift`. No store references below the list boundary; no state mutation inside view-body computations. Ingest completions must not write state from a body computation.
- Section actions (open, focus, refresh, change timespan) route through the existing `SidebarDockActionInvoker` → `SidebarDockCommand.perform` path.
- Failure modes: every state (loading, populated, no-stores, configured-but-unobserved, error) renders identifiable content.

**Acceptance Criteria**
- AC-3.1.a: Mounting `stokdUsage` with fixture aggregates renders a non-empty table hierarchy.
- AC-3.1.b: Loading, populated, no-stores, configured-but-unobserved, and error states each render identifiable, non-blank content.
- AC-3.1.c: An `unavailable` cell renders as the unavailable affordance with its accessibility label, and never as the string `0`.
- AC-3.1.d: Token counts and currency render through locale-aware formatters — no direct interpolation of numeric values in the table cells.
- AC-3.1.e: Section actions resolve through `SidebarDockActionInvoker`/`SidebarDockCommand` from every entrypoint.
- AC-3.1.f: No type below the Usage row list holds an `ObservableObject`/`@Observable` reference (snapshot-boundary rule).
- AC-3.1.g: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdUsagePanelViewTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

**Acceptance Tests**
- Test-3.1.a: Unit — mounted table for fixtures.
- Test-3.1.b: Unit — all five state renderings.
- Test-3.1.c: Unit — unavailable cell rendering and accessibility label.
- Test-3.1.d: Regression — `rg` shows formatter use and no raw numeric interpolation in cells.
- Test-3.1.e: Unit — invoker reachability for section actions.
- Test-3.1.f: Regression — `rg` over the row files shows no store property wrappers.
- Test-3.1.g: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'StokdUsagePanel|stokdUsage' Sources/
! rg -n '@(ObservedObject|EnvironmentObject|StateObject|Bindable)' Sources/Stokd/Usage/
rg -n 'NumberFormatter|FormatStyle|formatted\(' Sources/Stokd/Usage/
rg -n 'SidebarDockActionInvoker|SidebarDockCommand' Sources/Stokd/Usage/
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdUsagePanelViewTests CMUX_SKIP_ZIG_BUILD=1 test
```

---

## Phase 4: Default seed

**Purpose:** Runs after Phase 3 so a cold-start window seeds a section that renders real content rather than a placeholder, and so rank composition can be tested against a real mounted section.

### 4.1 Seed Usage at stokd rank 3

**Targets:** VAL-USESEED-001
**Dependencies:** ["3.1"]

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Extend `SidebarDockSeeding` (or sibling) so that when the gate is on and the stokd seed generation has not been applied for this kind, a Usage section is inserted into the left rail below the workspaces section.
- **Rank-ordered insertion:** stokd left-rail sections carry a rank (Global Config = 1, Worktrees = 2, **Usage = 3**). Insertion positions Usage after any lower-ranked stokd section, so the three panels compose into the documented order regardless of landing order.
- Advance the prerequisite's shared seed-generation marker rather than adding a second marker.
- Gate off: the seed path no-ops for stokd kinds. The right rail is never modified.
- Failure modes: partial seed failure leaves non-stokd rails intact; log and continue.

**Acceptance Criteria**
- AC-4.1.a: Seeding an empty registry with the gate on places Usage below the workspaces section.
- AC-4.1.b: Seeding into a rail that already has rank-1 and rank-2 stokd sections places Usage after both.
- AC-4.1.c: A second seed call does not duplicate the section and does not reset a customized order.
- AC-4.1.d: Gate off → seed introduces no stokd kinds.
- AC-4.1.e: Seeding leaves the right-rail tool tab strip identical to its pre-seed state.
- AC-4.1.f: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdUsagePanelSeedTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

**Acceptance Tests**
- Test-4.1.a: Unit — default placement below workspaces.
- Test-4.1.b: Unit — rank composition after rank-1 and rank-2 neighbours.
- Test-4.1.c: Unit — idempotent reseed / custom order preserved.
- Test-4.1.d: Unit — gate-off no-op.
- Test-4.1.e: Unit — right rail untouched.
- Test-4.1.f: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'stokdPanelsSeed|seedStokd|stokdUsage' Sources/Sidebar/
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdUsagePanelSeedTests CMUX_SKIP_ZIG_BUILD=1 test
```

---

## Phase 5: Persistence, localization, and rollout

**Purpose:** Last phase — depends on the section and seed existing so snapshot keys and strings are real. Closes the slice for dogfood.

### 5.1 Snapshot persistence for the Usage section

**Targets:** VAL-USEPERSIST-001
**Dependencies:** ["4.1"]

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Persist left-rail membership, order, collapse state, extent, and the selected timespan for `stokdUsage` using the **additive optional** snapshot rules established by the prerequisite PRD — **never** bump `SessionSnapshotSchema.currentVersion` and never add a `SessionWorkspaceLayoutSnapshot` case.
- Aggregated totals are **not** snapshot state; they are rebuilt from the ingest cursors on mount, so a stale snapshot can never present stale spend. The ingest cursor lives in gdock's own ingest state, not in the session snapshot.
- Round-trip: seed layout → encode → decode → equal membership, order, collapse, extent, and timespan.
- Failure modes: unknown future kind → skip; corrupt optional → fall back to the default seed once; unrecognized timespan value → default timespan.

**Acceptance Criteria**
- AC-5.1.a: Round-trip of a Usage-inclusive layout preserves membership, order, collapse, extent, and selected timespan.
- AC-5.1.b: `SessionSnapshotSchema.currentVersion` is unchanged from the pre-phase baseline (remains 1).
- AC-5.1.c: No aggregated totals appear in the encoded snapshot payload.
- AC-5.1.d: An unrecognized persisted timespan decodes to the default timespan without crashing.
- AC-5.1.e: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdUsagePanelPersistenceTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

**Acceptance Tests**
- Test-5.1.a: Unit — encode/decode round-trip including timespan.
- Test-5.1.b: Regression — schema version pin.
- Test-5.1.c: Unit — no totals in the encoded snapshot.
- Test-5.1.d: Unit — unknown timespan falls back to default.
- Test-5.1.e: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'currentVersion' Sources/ Packages/ | rg -n 'SessionSnapshotSchema'
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/StokdUsagePanelPersistenceTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 5.2 Localization audit and dogfood gate

**Targets:** VAL-USEROLL-001
**Dependencies:** ["5.1"]

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Every new user-facing string uses `String(localized:)` with en+ja entries in `Resources/Localizable.xcstrings`, `state == translated`, and `ja != en` for non-identical natural text. Covered surfaces: section title, column headers, timespan labels, the unavailable affordance's accessibility label, and the no-stores / configured-but-unobserved / error states.
- Palette and debug can open and focus Usage through the same invoker path as other rail sections.
- Tagged dogfood: `CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag stokd-usage-panel` builds; with the gate on, a cold window shows the section at the bottom of the stokd stack and it updates after agent activity without crashing.
- Bonsplit clean: `git -C vendor/bonsplit status --porcelain` empty; pinned SHA unchanged.

**Acceptance Criteria**
- AC-5.2.a: Every new Usage string key exists in both en and ja with `state == translated`.
- AC-5.2.b: No bare English literal appears in new Usage Swift sources' `Text(`/`Button(`/alert titles.
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
       if 'usage' in k.lower() and 'stokd' in k.lower()
       and 'ja' not in v.get('localizations', {})]
assert not bad, f"missing ja: {bad}"
print("ja coverage ok")
PY
./scripts/lint-pbxproj-test-wiring.sh
git -C vendor/bonsplit status --porcelain
git -C vendor/bonsplit rev-parse HEAD
# Preferred full gate when the environment allows:
# CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag stokd-usage-panel
./scripts/test-unit.sh -only-testing:cmuxTests/StokdUsagePanelKindTests \
  -only-testing:cmuxTests/StokdUsageIngestTests \
  -only-testing:cmuxTests/StokdUsageAggregationTests \
  -only-testing:cmuxTests/StokdUsagePanelViewTests \
  -only-testing:cmuxTests/StokdUsagePanelSeedTests \
  -only-testing:cmuxTests/StokdUsagePanelPersistenceTests \
  CMUX_SKIP_ZIG_BUILD=1 test
```

---

## 4. Completion Criteria

- [ ] All Phase 1–5 work items' Verification Commands exit 0.
- [ ] Gate on + cold seed shows Usage at the bottom of the stokd stack, ordered by rank against any sibling stokd sections present.
- [ ] The table breaks usage down per provider and per model for the selected timespan, including reasoning tokens where reported.
- [ ] Unmeasured columns render as unavailable, never as a measured zero; unpriced models show tokens with cost unavailable.
- [ ] Ingest is incremental and restart-safe: provider stores are byte-identical after ingest and no record is double counted across a relaunch.
- [ ] Gate off: no Usage section; existing rails unchanged; the right rail is untouched in both states.
- [ ] en+ja strings present with locale-aware formatting; pbxproj test wiring clean; bonsplit clean and at the pinned SHA.
- [ ] `SessionSnapshotSchema.currentVersion` unchanged and no totals persisted.
- [ ] The prerequisite `docs/stokd-work-panel.prd.md` has landed and its foundation is consumed unchanged.

---

## 5. Rollout & Validation

### Rollout Strategy

- Ship behind the existing `sidebar.beta.dock.enabled` beta gate (default off).
- Enable on dogfood machines first via Settings / `cmux.json` beta key.
- Rollback: set the gate false — the Usage section disappears; non-stokd rails remain. Provider stores are untouched by rollback because ingest never writes them.

### Post-Launch Validation

- Open the tagged Debug app with the gate on; run an agent session and confirm the table updates without a restart and without the rail stuttering.
- Compare a provider's totals against that provider's own reported usage for the same window; investigate any divergence before wider enablement.
- Confirm a provider that omits cache columns shows the unavailable affordance rather than zeros.
- Quit mid-session and relaunch; confirm totals do not double and the selected timespan survives.
- Confirm store file checksums are unchanged after a dogfood session.

---

## 6. Open Questions

1. Which timespans ship in v1? Default: today, 7 days, 30 days, all time.
2. Where does the ingest cursor live — gdock application support state or alongside the session snapshot? Default: gdock application support state, so a snapshot reset cannot cause double counting.
3. Should usage be scoped to the active workspace or shown globally across all workspaces? Default: global, matching how the provider stores are written; a workspace filter is a follow-up.
4. Is provider pricing available locally, or must cost be omitted until the CLI exposes a price table? Default: show cost only where a local price is known, and mark the rest unavailable.
