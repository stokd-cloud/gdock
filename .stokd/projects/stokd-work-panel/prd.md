# Stokd Work Panel

## 0. Source Context

**Derived From:** Operator report that the shipped gdock "Work" right-sidebar panel is not a
usable replacement for the Stokd work webview in stokd-code — it shows almost none of the
repository's real tasks and projects, has no todos, no filters, no search, no detail pane, and no
per-item context actions; and it cannot be reached at all unless `sidebar.beta.dock.enabled` is
turned on.
**Feature Name:** Stokd Work Panel
**PRD Owner:** brian@stokd.cloud
**Last Updated:** 2026-08-24

### Summary

gdock ships a right-sidebar tool mode `.stokdWork` ("Work") that is supposed to be the in-editor
view of Stokd work items. Today it is a stub: it is gated behind an unrelated, actively-being-gutted
docking beta flag; it renders `StokdWorkPlaceholderView` on the non-dock path; it reads from a
hardcoded `http://localhost:8167` that holds a **different dataset** from the one the `stokd` CLI
reads; and it exposes exactly one segmented kind picker and a refresh button.

This project makes Work a first-class, always-available right-sidebar tool with no relationship to
docking, sources it through the config-aware `stokd` CLI so it shows exactly the work the CLI
shows, adds todos as a first-class item kind, and restores the filter / search / detail-pane /
context-action surface the operator had in stokd-code.

**Measured evidence of the data defect (2026-08-24, repo `stokd-cloud/gdock`):**

| Source | gdock tasks | gdock projects |
|--------|-------------|----------------|
| `stokd task list --all --json` / `stokd project list --json` (what the operator sees) | 18 | 1 |
| `GET http://localhost:8167/api/tasks?repo_slug=stokd-cloud/gdock` (what the panel reads) | 1 | 0 |

The two hash sets are **disjoint** — the panel is not showing a filtered view of the operator's
work, it is showing a different store.

**Supersedes:** `.stokd/projects/stokd-work-panel-gdock-right-rail/prd.md` (project `493eefd`),
whose `VAL-FLAG-001` deliberately bound Work to the rail beta gate and whose `VAL-API-001` bound it
to the local HTTP API. Both are reversed here.
**Absorbs:** in-flight task `cada835` ("Make the Stokd Work panel a default…"), which covers the
un-gating work item only.

## 1. Objectives & Constraints

### Objectives

- Work is reachable as an ordinary right-sidebar tool with every beta/docking flag off, and stays
  reachable when the docking subsystem is gutted.
- The panel's contents equal the `stokd` CLI's contents for the workspace repository — no second
  data store, no hardcoded host.
- Todos are represented as a first-class item kind next to tasks and projects.
- The operator can filter, sort, search, inspect, and act on work items without leaving gdock.
- Nothing user-facing regresses the typing-latency or SwiftUI list rules the repo already enforces.

### Constraints

- Fork conventions: every new setting id and UserDefaults key is `gdock.*`; every new palette
  command id is `palette.gdock.*` (one-shot) or `palette.toggleSetting.gdock.*` (toggle).
  New settings live in `GdockCatalogSection`.
- Data and mutations go through the resolved `stokd` executable
  (`Sources/Stokd/StokdExecutableResolver.swift` → `StokdCLIRunner`). The panel must not
  hand-construct REST calls or embed an API host: the CLI is the only component that resolves the
  environment (`env: stage`), org, and credentials correctly.
- `stokd task view` and `stokd project view` currently emit **text only** (no `--json`);
  `stokd todo view` and all three `list` verbs emit `--json`. The detail pane must work against
  today's CLI surface without requiring a change in `stokd-cloud/mono`.
- No CLI `list` verb supports `--search`, so search is client-side over the loaded set and must be
  honest about set completeness.
- SwiftUI list-boundary rule: no view below a `LazyVStack`/`ForEach` boundary may hold an
  observable store reference, and no function called from `body` may write state
  (https://github.com/manaflow-ai/cmux/issues/2586).
- Every user-facing string is `String(localized:)` with a key in `Resources/Localizable.xcstrings`.
- Every new `.swift` test file needs both a `PBXFileReference` and a `PBXSourcesBuildPhase` entry
  or it is silently skipped.

### Scope Inventory

| Surface | Files |
|---------|-------|
| Availability / mode bar | `Sources/RightSidebarMode+Availability.swift`, `Sources/RightSidebarPanelView.swift`, `Sources/FileExplorerState.swift`, `Sources/ContentView.swift` |
| Panel hosting | `Sources/RightSidebarToolPanel.swift`, `Sources/ContentView+RightSidebarCommandPalette.swift`, `Sources/MainWindowFocusController.swift` |
| Work implementation | `Sources/Stokd/StokdWorkPanelView.swift`, `StokdWorkPanelViewModel.swift`, `StokdWorkModels.swift`, `StokdWorkAPIClient.swift`, `StokdCLIRunner.swift`, `StokdExecutableResolver.swift` |
| Dock coupling to remove | `Sources/App/WorkspaceRuntimeSettings.swift` (`StokdRailPanelAvailability`), `Sources/Sidebar/SidebarDockSeeding.swift`, `Sources/Sidebar/SidebarDockSessionPersistence.swift`, `Sources/Sidebar/SidebarDockPlacementMatrix.swift` |
| Settings / palette | `Packages/macOS/CmuxSettings/Sources/CmuxSettings/Keys/GdockCatalogSection.swift`, `Sources/Sidebar/RightSidebarSelectionRouter.swift` |
| Localization | `Resources/Localizable.xcstrings` |
| Tests | `cmuxTests/StokdWork*.swift`, `cmuxTests/StokdRailPanelFlagTests.swift`, `cmux.xcodeproj/project.pbxproj` |

### Non-Goals

- Removing or rewriting the sidebar-dock / rail subsystem. This project only severs Work's
  dependency on it; gutting docking is separate work.
- Changing the `stokd` CLI or the Stokd API (including adding `--json` to `stokd task view` or
  `--search` to the `list` verbs). Both are tracked as follow-ups in §6.
- Server-side search, server-side paging, or match-category ("prompt / acceptance / components /
  files / docs") search facets from the stokd-code webview — those require CLI/API support that
  does not exist today.
- Agent-session timelines, tool history, message replay, worktree PR/merge actions, and multi-select
  bulk operations from the stokd-code webview.
- Creating work items from the panel. Creation stays in the CLI for this pass.
- iOS. This is a macOS right-sidebar surface only.

## 1.5 Required Toolchain

| Tool | Min Version | Install Command | Verify Command |
|------|-------------|-----------------|----------------|
| Xcode | 16.0 | Mac App Store / developer.apple.com | `xcodebuild -version` |
| stokd CLI | 0.2.162 | `curl -fsSL https://get.stokd.cloud \| sh` | `stokd --version` |
| jq | 1.7 | `brew install jq` | `jq --version` |
| Python | 3.11 | preinstalled on macOS 15+ | `python3 --version` |

## 2. Contract

**VAL-GATE-001** — Work is a default right-sidebar tool with every beta flag off.
Surface: browser
Needs: none
Behavior: with `sidebar.beta.dock.enabled`, `rightSidebar.beta.dock.enabled`, and
  `rightSidebar.beta.feed.enabled` all absent or false, the right-sidebar mode bar offers a "Work"
  tab, and selecting it renders the live work list rather than `StokdWorkPlaceholderView`.
Evidence: a Swift test asserting `RightSidebarMode.availableModes(feedEnabled: false,
  dockEnabled: false, sidebarDockEnabled: false)` contains `.stokdWork` and that the non-dock
  content host resolves `.stokdWork` to `StokdWorkPanelView`; plus a tagged Release build launched
  with those three defaults deleted, screenshotted showing the Work tab and a populated list.
Fail: the operator cannot reach Work at all without enabling a docking beta they intend to delete.
Rigor: R2
Why: the defect is total unreachability on the default configuration, which a unit test over
  availability alone cannot prove; an independent validator must confirm it on a real build.

**VAL-GATE-002** — Work does not depend on the sidebar-dock subsystem.
Surface: library
Needs: VAL-GATE-001
Behavior: no file under `Sources/Stokd/` and no Work availability path references a `SidebarDock*`
  type, `StokdRailPanelAvailability`, or the `sidebar.beta.dock.enabled` key, so deleting the
  docking subsystem cannot make Work disappear or fail to compile.
Evidence: a checked-in lint script that greps `Sources/Stokd/` and
  `Sources/RightSidebarMode+Availability.swift` for those tokens and exits non-zero on a hit, run
  in the verification block; plus a unit test asserting `.stokdWork.isAvailable` returns the same
  value for `sidebarDockEnabled: true` and `false`.
Fail: gutting docking silently takes Work with it, which is the operator's stated fear.
Rigor: R1
Why: fully decided by a deterministic grep plus one unit test; no independent lane owed.

**VAL-DATA-001** — The panel lists exactly the work the stokd CLI lists.
Surface: browser
Needs: none
Behavior: for the workspace repository's slug, the Work list contains one row per record returned
  by `stokd task list --repo <slug> --all --json`, `stokd project list --repo <slug> --all --json`,
  and `stokd todo list --repo <slug> --all --json`, matched by `hash`, with no extra rows and none
  missing.
Evidence: an integration test driving the loader through a fake `CommandRunning` that replays
  recorded CLI JSON for all three verbs and asserting the resulting row hash set equals the fixture
  hash set; plus a dogfood comparison on `stokd-cloud/gdock` of the on-screen row count against
  `stokd task list --repo stokd-cloud/gdock --all --json | jq length` (today: CLI 18 vs panel 1).
Fail: the operator's real work is invisible and a foreign dataset is shown in its place.
Rigor: R2
Why: this is the reported defect; fixtures alone cannot prove the live store matches, so an
  independent validator must confirm the counts on live data.

**VAL-DATA-002** — The data source is resolved, never hardcoded.
Surface: library
Needs: VAL-DATA-001
Behavior: every Work read and write executes the `stokd` executable located by
  `StokdExecutableResolver`, and no Work code path contains an API host, port, or URL literal.
Evidence: grep of `Sources/Stokd/` for `localhost`, `8167`, `http://`, and `URLSession` exits
  non-zero on any hit; a unit test asserting the loader invokes the runner with the argument vector
  `["task", "list", "--repo", <slug>, "--all", "--json", "--limit", <n>]`.
Fail: a second, environment-blind data path reappears and drifts from the CLI again.
Rigor: R1
Why: settled entirely by a grep and one argument-vector assertion.

**VAL-TODO-001** — Todos are a first-class item kind.
Surface: browser
Needs: VAL-DATA-001
Behavior: todos render as their own kind with a distinct icon, a "Todo" kind label, their status
  badge, and their checklist item count (completed / total), and the kind filter offers Todos
  alongside All, Tasks, and Projects.
Evidence: a view-model test mapping recorded `stokd todo list --json` (which nests `items[]`) into
  todo rows carrying the correct completed/total counts, plus a test that selecting the Todos
  filter yields only todo rows; screenshot of the Todos filter with a populated list.
Fail: todos — now a real Stokd work vehicle — remain invisible in the editor.
Rigor: R1
Why: deterministic mapping over a recorded fixture; no cross-lane validation owed.

**VAL-LIST-001** — The list is complete, and says so when it is not.
Surface: browser
Needs: VAL-DATA-001
Behavior: the panel requests a stated maximum per kind, and when any kind returns exactly that
  maximum it renders a truncation indicator naming the shown count and offering "Load more";
  below the maximum no indicator appears.
Evidence: a view-model test with a fixture of exactly the limit asserting the indicator text and
  its presence, and a second fixture below the limit asserting its absence.
Fail: silent truncation reproduces "where are all my items" with a different root cause.
Rigor: R1
Why: two deterministic fixtures settle it.

**VAL-FILTER-001** — Filters and sort are present and persist.
Surface: browser
Needs: VAL-DATA-001
Behavior: the filter bar offers a kind filter (All / Tasks / Projects / Todos), a show-completed
  toggle that defaults to off and hides `completed`, `cancelled`, and `failed` items while off, and
  a sort control over Last Updated and Created where re-selecting the active field flips
  ascending/descending; every choice survives a panel rebuild and an app relaunch.
Evidence: view-model tests for each control's effect on the rendered rows including the
  flip-on-reselect behavior; a persistence test round-tripping each value through the
  `gdock.workPanel.*` defaults keys.
Fail: the operator re-configures the panel on every launch, as in the current build.
Rigor: R1
Why: all behavior is view-model plus defaults round-trip, decided by unit tests.

**VAL-SEARCH-001** — Search narrows the loaded set.
Surface: browser
Needs: VAL-LIST-001
Behavior: typing in the search field filters the loaded rows case-insensitively across title, hash,
  status, and repo slug; the panel shows a "N of M" match count; Escape clears the query and
  restores the full set.
Evidence: view-model tests over one fixture set covering a match in each of the four fields, the
  reported count, a zero-match empty state, and the Escape-clears behavior.
Fail: finding a known item in a repo with hundreds of work items requires scrolling.
Rigor: R1
Why: pure view-model behavior over deterministic fixtures.

**VAL-DETAIL-001** — Selecting a row opens a detail view.
Surface: browser
Needs: VAL-DATA-001
Behavior: selecting a row opens a detail view showing identity (title, number, hash, repo slug,
  status), created/updated timestamps, the description or objective, acceptance criteria with each
  criterion's recorded outcome, and any notes — loaded on demand from `stokd task view <hash>`,
  `stokd project view <hash>`, or `stokd todo view <hash> --json` for the row's kind; a non-zero
  exit renders the CLI's stderr and a Retry control instead of an empty pane.
Evidence: tests over recorded output of all three verbs asserting each named field renders for its
  kind, and a test asserting a non-zero exit renders the stderr text plus Retry.
Fail: the panel is a list of titles with no way to read what a work item actually promises.
Rigor: R2
Why: correctness spans three different CLI output formats — two of them text, one JSON — so an
  independent validator must confirm all three parse, not just the JSON one.

**VAL-ACTION-001** — Each item kind carries its own context actions.
Surface: browser
Needs: VAL-DETAIL-001
Behavior: right-clicking a row opens a menu whose entries depend on kind — task: Start, Start in
  Worktree, One-Shot, Resume, Integrate, Review, Add Note, Set Priority, Mark Completed, Delete;
  project: Start, Advance, Review, Report, Integrate, Add Note, Set Priority, Mark Completed,
  Delete; todo: Start, Add Note, Mark Completed, Delete — plus Copy Hash and Open in Terminal on
  every kind; each entry runs the matching `stokd` verb through the resolved executable, Delete and
  Mark Completed require a confirmation, and any non-zero exit surfaces the CLI's stderr to the
  operator rather than failing silently.
Evidence: tests asserting the exact entry list per kind, that each entry dispatches the expected
  argument vector to a fake runner, that Delete and Mark Completed are gated behind confirmation,
  and that a non-zero exit is surfaced; plus one live dogfood run of the non-destructive Add Note
  entry verified with `stokd task view <hash>`.
Fail: state-changing verbs are dispatched with wrong arguments, or fail silently against real work.
Rigor: R2
Why: these invoke real state-changing CLI verbs against the operator's live work, so an independent
  validator confirms the argument vectors and the confirmation gates before they ship.

**VAL-CHROME-001** — No dock section chrome on the plain Work tab.
Surface: browser
Needs: VAL-GATE-001
Behavior: when Work is shown as an ordinary right-sidebar tab, no "Collapse Section", "Move Section
  Up", or "Move Section Down" context entry is offered and no collapsed "Collapsed / Expand" strip
  can be produced; those affordances exist only when Work is hosted as a rail section.
Evidence: a test asserting the section-chrome modifier is applied on the rail host path and not on
  the tab host path; a screenshot of a right-click on the Work tab with the docking flag off
  showing no section entries.
Fail: the operator meets docking chrome on a surface that has nothing to do with docking — the
  behavior in the reported screenshots.
Rigor: R1
Why: one structural assertion plus a visual check settles it.

**VAL-L10N-001** — Every new user-facing string is localized.
Surface: artifact
Needs: none
Behavior: every user-facing string added by this project resolves through `String(localized:)` with
  its key present in `Resources/Localizable.xcstrings`.
Evidence: a lint over the diff asserting no bare `Text("…")` / `Button("…")` string literal is
  introduced under `Sources/Stokd/`, and a check that every `String(localized:` key added under
  `Sources/Stokd/` exists in `Resources/Localizable.xcstrings`.
Fail: an English-only panel ships, violating the repo's localization policy.
Rigor: R1
Why: repo policy already requires a localization audit for any UI change; the lint persists it.

## 3. Execution Topology

## Phase 1: Make Work a real, CLI-backed work surface
**Purpose:** One unattended pass. Every decision the work depends on — un-gate rather than
re-gate, source through the CLI rather than HTTP, enumerate parity actions explicitly rather than
diff against a moving webview — is already settled in §1, so no human checkpoint is owed and the
work items are ordered by `**Dependencies:**` alone.

### 1.1 Un-gate Work and render it on the non-dock path
**Targets:** VAL-GATE-001, VAL-CHROME-001
**Dependencies:** []

**Implementation Details**
- `RightSidebarMode.isAvailable`: `.stokdWork` returns `true` unconditionally; drop the
  `sidebarDockEnabled` input from its branch. Delete `resolvedAfterSidebarDockGateChange`, which
  today rewrites `.stokdWork` to `.files` whenever the gate is off, and its call site in
  `Sources/FileExplorerState.swift`.
- `Sources/RightSidebarPanelView.swift`: the non-dock content host currently resolves `.stokdWork`
  to `StokdWorkPlaceholderView`. Resolve it to `StokdWorkPanelView` backed by a window-scoped
  `StokdWorkPanelViewModel`, and delete `StokdWorkPlaceholderView`.
- Extract the repo-slug resolution currently private to
  `RightSidebarToolPanel.syncStokdWorkRepository` into one shared resolver used by both the rail
  host and the new non-dock host, per the repo's shared-behavior policy — one resolution path, not
  one per entrypoint.
- `Sources/ContentView+RightSidebarCommandPalette.swift`: the `.stokdWork` branch requires
  `isSidebarDockEnabled()` and rejects otherwise; add the non-dock show path so
  `palette.gdock.showStokdWork` works with docking off.
- `SidebarDockSeeding` / `SidebarDockSessionPersistence`: `includeStokdWork:` becomes unconditional.
  Keep the existing right-edge-only placement rule in `SidebarDockPlacementMatrix`.
- Section chrome (`Collapse Section` / `Move Section Up` / `Move Section Down`) is applied by the
  rail host only; assert the tab host does not apply it.
- Failure mode: enum declaration order places Work at mode-bar index 3 with Feed and Dock off —
  the slot the Dock tab occupies when its flag is on. Existing tests asserting the gated behavior
  are updated to the new spec; this is a spec change, not a test weakening.

**Acceptance Criteria**
- AC-1.1.a: `RightSidebarMode.availableModes(feedEnabled: false, dockEnabled: false,
  sidebarDockEnabled: false)` equals `[.files, .find, .sessions, .stokdWork]` → Work present at
  index 3.
- AC-1.1.b: the symbol `StokdWorkPlaceholderView` no longer exists anywhere in the target.
- AC-1.1.c: `resolvedAfterSidebarDockGateChange` no longer exists, and no code path rewrites
  `.stokdWork` to `.files`.
- AC-1.1.d: the tab host does not apply the rail section-chrome modifier; the rail host does.
- AC-1.1.e: `xcodebuild … test -only-testing:cmuxTests/StokdWorkAvailabilityTests` → exit 0.

**Acceptance Tests**
- Test-1.1.a: Unit — `StokdWorkAvailabilityTests` covers AC-1.1.a and AC-1.1.c.
- Test-1.1.b: Regression — a test asserting the non-dock host resolves `.stokdWork` to
  `StokdWorkPanelView`, covering AC-1.1.b.
- Test-1.1.c: Unit — section-chrome host test covering AC-1.1.d.

**Verification Commands**
```bash
set -euo pipefail
! grep -rn "StokdWorkPlaceholderView" Sources
! grep -rn "resolvedAfterSidebarDockGateChange" Sources
./scripts/lint-pbxproj-test-wiring.sh
xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/cmux-work-panel \
  test -only-testing:cmuxTests/StokdWorkAvailabilityTests
```

### 1.2 Sever the sidebar-dock coupling
**Targets:** VAL-GATE-002
**Dependencies:** ["1.1"]

**Implementation Details**
- Delete `StokdRailPanelAvailability` from `Sources/App/WorkspaceRuntimeSettings.swift` and every
  call site that used it to suppress Work.
- Add `scripts/lint-stokd-work-dock-independence.sh`: fails when `Sources/Stokd/` or
  `Sources/RightSidebarMode+Availability.swift` mentions `SidebarDock`, `StokdRailPanelAvailability`,
  or `sidebar.beta.dock.enabled`.
- Keep the rail *hosting* of Work intact — the rail may host Work; Work may not know the rail exists.
- Failure mode: the placement matrix legitimately names `.stokdWork`; the lint covers Work-owned
  files only, not the dock subsystem's own files.

**Acceptance Criteria**
- AC-1.2.a: `StokdRailPanelAvailability` does not exist in the target → grep exits non-zero.
- AC-1.2.b: `.stokdWork.isAvailable(...)` returns the same value for `sidebarDockEnabled: true` and
  `sidebarDockEnabled: false`.
- AC-1.2.c: `./scripts/lint-stokd-work-dock-independence.sh` → exit 0.

**Acceptance Tests**
- Test-1.2.a: Unit — parameterized availability test covering AC-1.2.b.
- Test-1.2.b: Regression — the lint script itself, run in CI, covering AC-1.2.a and AC-1.2.c.

**Verification Commands**
```bash
set -euo pipefail
! grep -rn "StokdRailPanelAvailability" Sources
./scripts/lint-stokd-work-dock-independence.sh
xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/cmux-work-panel \
  test -only-testing:cmuxTests/StokdWorkAvailabilityTests
```

### 1.3 Replace the HTTP client with a CLI-backed loader
**Targets:** VAL-DATA-001, VAL-DATA-002
**Dependencies:** ["1.1"]

**Implementation Details**
- Delete `Sources/Stokd/StokdWorkAPIClient.swift` and its `StokdWorkLoading` conformance. Replace
  it with `StokdWorkCLILoader`, conforming to the existing `StokdWorkLoading` protocol so the view
  model's contract is unchanged.
- The loader runs, concurrently, through `StokdCLIRunner` with the workspace directory as cwd:
  `stokd task list --repo <slug> --all --json --limit <n>`,
  `stokd project list --repo <slug> --all --json --limit <n>`,
  `stokd todo list --repo <slug> --all --json --limit <n>`.
- Decode into `StokdTask` / `StokdProject` / `StokdTodo`. The CLI's list JSON is thinner than the
  HTTP DTOs — task rows carry `hash`, `id`, `priority`, `repo_slug`, `status`, `task_number`,
  `title`, `updated_at` and **no description** — so `StokdWorkModels.swift` must be re-keyed to the
  CLI shapes and the row detail line must fall back to the status/updated metadata rather than a
  description that is not there.
- Failure modes to map to a user-visible state, each carrying the CLI's stderr: executable not
  found (exit 127 from the runner), non-zero exit, timeout, and undecodable stdout. Preserve the
  existing generation-counter cancellation so a stale response never overwrites a newer one.
- Do not shell out on every keystroke or every `body` evaluation; load on repo change, on explicit
  refresh, and on an action completing.

**Acceptance Criteria**
- AC-1.3.a: the loader dispatches the exact argument vector
  `["task", "list", "--repo", "<slug>", "--all", "--json", "--limit", "<n>"]` (and the project /
  todo equivalents) to the injected runner.
- AC-1.3.b: given recorded CLI JSON for all three verbs, the resulting row hash set equals the
  fixture hash set exactly.
- AC-1.3.c: a non-zero exit renders a failure state containing the CLI's stderr text.
- AC-1.3.d: `grep -rnE "localhost|8167|http://|URLSession" Sources/Stokd` → no matches.
- AC-1.3.e: `xcodebuild … test -only-testing:cmuxTests/StokdWorkCLILoaderTests` → exit 0.

**Acceptance Tests**
- Test-1.3.a: Unit — argument-vector test against a fake `CommandRunning`, covering AC-1.3.a.
- Test-1.3.b: Integration — replay of recorded three-verb JSON, covering AC-1.3.b.
- Test-1.3.c: Unit — non-zero-exit and timeout paths, covering AC-1.3.c.

**Verification Commands**
```bash
set -euo pipefail
! grep -rnE "localhost|8167|http://|URLSession" Sources/Stokd
test ! -f Sources/Stokd/StokdWorkAPIClient.swift
./scripts/lint-pbxproj-test-wiring.sh
xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/cmux-work-panel \
  test -only-testing:cmuxTests/StokdWorkCLILoaderTests
```

### 1.4 Add todos as a first-class kind
**Targets:** VAL-TODO-001
**Dependencies:** ["1.3"]

**Implementation Details**
- Add `StokdTodo` to `StokdWorkModels.swift` keyed to `stokd todo list --json`: `hash`, `id`,
  `title`, `status`, `repo_slug`, `updated_at`, and a nested `items[]` of
  `{ id, order, title, status, kind, ref_hash, task_hash, repo_slug }`.
- Extend `RowSnapshot.Kind` with `.todo`, give it the `checklist`-family icon distinct from the
  task and project icons, a localized "Todo" kind label, and a completed/total item count derived
  from `items[]`.
- Extend the kind filter with a Todos case; `.all` includes todos.
- Failure mode: a todo whose `items` array is absent or empty renders a 0/0 count, not a crash and
  not a hidden row.

**Acceptance Criteria**
- AC-1.4.a: recorded `stokd todo list --json` maps to todo rows whose completed/total counts equal
  the fixture's item statuses.
- AC-1.4.b: selecting the Todos kind filter yields only `.todo` rows; `.all` includes them.
- AC-1.4.c: a todo with no `items` key renders a row with a 0/0 count and does not throw.
- AC-1.4.d: `xcodebuild … test -only-testing:cmuxTests/StokdWorkTodoKindTests` → exit 0.

**Acceptance Tests**
- Test-1.4.a: Unit — todo decode + count mapping, covering AC-1.4.a and AC-1.4.c.
- Test-1.4.b: Unit — kind filter over a mixed fixture, covering AC-1.4.b.

**Verification Commands**
```bash
set -euo pipefail
xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/cmux-work-panel \
  test -only-testing:cmuxTests/StokdWorkTodoKindTests
```

### 1.5 Report set completeness instead of truncating silently
**Targets:** VAL-LIST-001
**Dependencies:** ["1.3"]

**Implementation Details**
- Give the loader an explicit per-kind limit (default 500, well above any observed repo's work
  count) and record, per kind, whether the CLI returned exactly the limit.
- When any kind hit its limit, render a localized truncation footer naming the shown count and a
  "Load more" control that re-requests with a doubled limit.
- Failure mode: "returned exactly the limit" is a heuristic — a set whose size is exactly the limit
  shows the footer and Load more returns nothing new. That is acceptable and must not error.

**Acceptance Criteria**
- AC-1.5.a: a fixture returning exactly the limit renders the truncation footer with the correct
  shown count.
- AC-1.5.b: a fixture below the limit renders no footer.
- AC-1.5.c: Load more re-requests with a doubled limit and merges without duplicating rows by hash.
- AC-1.5.d: `xcodebuild … test -only-testing:cmuxTests/StokdWorkCompletenessTests` → exit 0.

**Acceptance Tests**
- Test-1.5.a: Unit — at-limit and below-limit fixtures, covering AC-1.5.a and AC-1.5.b.
- Test-1.5.b: Unit — Load-more merge and de-duplication, covering AC-1.5.c.

**Verification Commands**
```bash
set -euo pipefail
xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/cmux-work-panel \
  test -only-testing:cmuxTests/StokdWorkCompletenessTests
```

### 1.6 Filter bar: kind, completed, sort — persisted
**Targets:** VAL-FILTER-001
**Dependencies:** ["1.4"]

**Implementation Details**
- Rebuild the toolbar as a filter bar: kind segmented control (All / Tasks / Projects / Todos), a
  show-completed toggle, a sort control, and the existing refresh button.
- Show-completed defaults to **off** and, while off, hides rows whose status is `completed`,
  `cancelled`, or `failed`.
- Sort offers Last Updated (`updated_at`) and Created (`created_at`); re-selecting the active field
  flips ascending/descending, matching the operator's stokd-code behavior. Sorting is applied
  client-side over the loaded set because no `list` verb accepts a sort flag.
- Persist all three under new `GdockCatalogSection` keys `gdock.workPanel.kindFilter`,
  `gdock.workPanel.showCompleted`, `gdock.workPanel.sortField`, `gdock.workPanel.sortAscending`.
  Register a `palette.toggleSetting.gdock.workPanel.showCompleted` command.
- Failure mode: `created_at` is absent from `stokd task list --json`; sorting by Created must fall
  back to `updated_at` for rows lacking it rather than dropping or crashing on them.

**Acceptance Criteria**
- AC-1.6.a: with show-completed off, a fixture containing `completed`, `cancelled`, and `failed`
  rows renders none of them; toggling on renders all.
- AC-1.6.b: selecting the active sort field a second time reverses the row order.
- AC-1.6.c: rows lacking `created_at` sort by `updated_at` under the Created field and are present
  in the output.
- AC-1.6.d: all four defaults keys round-trip through a fresh `UserDefaults` suite and every key is
  `gdock.`-prefixed.
- AC-1.6.e: `xcodebuild … test -only-testing:cmuxTests/StokdWorkFilterBarTests` → exit 0.

**Acceptance Tests**
- Test-1.6.a: Unit — completed-filter behavior, covering AC-1.6.a.
- Test-1.6.b: Unit — sort field and flip-on-reselect, covering AC-1.6.b and AC-1.6.c.
- Test-1.6.c: Unit — defaults round-trip and prefix assertion, covering AC-1.6.d.

**Verification Commands**
```bash
set -euo pipefail
grep -q 'gdock.workPanel.showCompleted' \
  Packages/macOS/CmuxSettings/Sources/CmuxSettings/Keys/GdockCatalogSection.swift
xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/cmux-work-panel \
  test -only-testing:cmuxTests/StokdWorkFilterBarTests
```

### 1.7 Search over the loaded set
**Targets:** VAL-SEARCH-001
**Dependencies:** ["1.5"]

**Implementation Details**
- Add a search field to the filter bar. Matching is case-insensitive and diacritic-insensitive over
  title, hash, status, and repo slug, applied after the kind and completed filters.
- Show a localized "N of M" count while a query is active; Escape clears the query and restores the
  full set. An empty result renders a distinct "no matches for <query>" state, not the generic
  empty state.
- Debounce recomputation; the filter runs over an already-loaded array, so it must never shell out
  and must never write state from a function called by `body`.
- Failure mode: search covers only what is loaded. When the truncation footer from 1.5 is showing,
  the search count is suffixed with the same "of at least N" qualifier so a miss is not mistaken
  for an absence.

**Acceptance Criteria**
- AC-1.7.a: a query matching only in title, only in hash, only in status, and only in repo slug
  each returns exactly the expected row.
- AC-1.7.b: the reported count equals matches / total-after-filters.
- AC-1.7.c: a zero-match query renders the no-matches state, and Escape restores the full set.
- AC-1.7.d: with the truncation footer active, the search count carries the "of at least" qualifier.
- AC-1.7.e: `xcodebuild … test -only-testing:cmuxTests/StokdWorkSearchTests` → exit 0.

**Acceptance Tests**
- Test-1.7.a: Unit — per-field matching, covering AC-1.7.a.
- Test-1.7.b: Unit — count, empty state, Escape, and truncation qualifier, covering AC-1.7.b
  through AC-1.7.d.

**Verification Commands**
```bash
set -euo pipefail
xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/cmux-work-panel \
  test -only-testing:cmuxTests/StokdWorkSearchTests
```

### 1.8 Detail view
**Targets:** VAL-DETAIL-001
**Dependencies:** ["1.4"]

**Implementation Details**
- Selecting a row pushes a detail view inside the panel with a back control; the panel is too narrow
  for a side-by-side split at typical sidebar widths.
- Detail loads on demand: `stokd task view <hash>` (text), `stokd project view <hash>` (text),
  `stokd todo view <hash> --json` (JSON). Add `StokdWorkDetailParser` with one parser per format.
  The task/project text format is section-delimited (`Task #N  <title>`, a rule line, `Status:`,
  `ID:`, `Runtime:`, `Components:`, then `Description` / `Acceptance Criteria` / `Notes` sections
  under rule lines); parse defensively and render any unrecognized trailing section verbatim rather
  than dropping it.
- Render: identity header (title, number, hash, repo, status badge), timestamps, description /
  objective, acceptance criteria as a list with each criterion's recorded outcome, and notes.
- A non-zero exit renders the CLI's stderr and a Retry control. Cache per hash for the panel's
  lifetime, invalidated by any action from 1.9 that mutates that item.
- Failure mode: the text format is not a stable contract. Parsing must degrade to "render the raw
  CLI output in a monospaced block" rather than showing an empty pane — an assertion the tests
  cover explicitly.

**Acceptance Criteria**
- AC-1.8.a: recorded `stokd task view` output yields a detail model whose title, number, hash,
  status, description, and acceptance criteria match the fixture.
- AC-1.8.b: recorded `stokd project view` output yields the equivalent project detail model.
- AC-1.8.c: recorded `stokd todo view --json` yields a todo detail model including every checklist
  item and its status.
- AC-1.8.d: unparseable output renders the raw text block, not an empty pane.
- AC-1.8.e: a non-zero exit renders the stderr text and a Retry control.
- AC-1.8.f: `xcodebuild … test -only-testing:cmuxTests/StokdWorkDetailTests` → exit 0.

**Acceptance Tests**
- Test-1.8.a: Unit — task text parser, covering AC-1.8.a.
- Test-1.8.b: Unit — project text parser, covering AC-1.8.b.
- Test-1.8.c: Unit — todo JSON parser, covering AC-1.8.c.
- Test-1.8.d: Unit — degradation and error paths, covering AC-1.8.d and AC-1.8.e.

**Verification Commands**
```bash
set -euo pipefail
xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/cmux-work-panel \
  test -only-testing:cmuxTests/StokdWorkDetailTests
```

### 1.9 Per-kind context actions
**Targets:** VAL-ACTION-001
**Dependencies:** ["1.8"]

**Implementation Details**
- One shared action table maps (kind, status) to an ordered entry list and each entry to a `stokd`
  argument vector, per the repo's shared-behavior policy — the row context menu, the detail view's
  action bar, and any palette entry read the same table.
- Entries: task — `task start`, `task start --worktree`, `task one-shot`, `task resume`,
  `task integrate`, `task review`, `task note`, `task priority`, `task complete`, `task delete`;
  project — `project start`, `project advance`, `project review`, `project report`,
  `project integrate`, `project note`, `project priority`, `project complete`, `project delete`;
  todo — `todo start`, `todo note`, `todo complete`, `todo delete`; all kinds — Copy Hash and Open
  in Terminal.
- `task note` / `project note` / `todo note` and `priority` prompt for their input first. Delete and
  Mark Completed require an explicit confirmation naming the item.
- Long-running verbs (`start`, `one-shot`, `integrate`, `advance`, `report`) open a terminal surface
  running the verb rather than blocking the panel on a hidden subprocess.
- On completion, invalidate that item's detail cache and refresh the list. Any non-zero exit
  surfaces the CLI's stderr in a dismissible alert.
- Failure mode: an entry offered for a status where the verb is invalid (for example `complete` on
  an already-completed item) must be absent from the menu, not fail at dispatch.

**Acceptance Criteria**
- AC-1.9.a: the entry list for each of task, project, and todo equals the enumeration above, in that
  order, for a pending item.
- AC-1.9.b: each entry dispatches its documented argument vector to a fake runner.
- AC-1.9.c: Delete and Mark Completed do not dispatch until confirmation is accepted.
- AC-1.9.d: `complete` is absent from the menu for an item already in a terminal status.
- AC-1.9.e: a non-zero exit surfaces the stderr text.
- AC-1.9.f: `xcodebuild … test -only-testing:cmuxTests/StokdWorkActionTests` → exit 0.

**Acceptance Tests**
- Test-1.9.a: Unit — per-kind entry list, covering AC-1.9.a and AC-1.9.d.
- Test-1.9.b: Unit — argument-vector dispatch for every entry, covering AC-1.9.b.
- Test-1.9.c: Unit — confirmation gating and error surfacing, covering AC-1.9.c and AC-1.9.e.

**Verification Commands**
```bash
set -euo pipefail
./scripts/lint-pbxproj-test-wiring.sh
xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/cmux-work-panel \
  test -only-testing:cmuxTests/StokdWorkActionTests
```

### 1.10 Localization audit and full-suite green
**Targets:** VAL-L10N-001
**Dependencies:** ["1.6", "1.7", "1.9"]

**Implementation Details**
- Add `scripts/lint-stokd-work-localization.sh`: fails when `Sources/Stokd/` contains a bare
  user-facing string literal in `Text(`, `Button(`, `.help(`, or `.accessibilityLabel(`, and fails
  when a `String(localized: "key"` used under `Sources/Stokd/` is missing from
  `Resources/Localizable.xcstrings`.
- Audit every string added across 1.1–1.9, including the filter bar, search placeholder and count,
  truncation footer, detail sections, every context-menu entry, every confirmation, and every error
  state.
- Run the whole `cmuxTests` suite, not only the focused targets, to catch tests that the earlier
  spec changes invalidated.

**Acceptance Criteria**
- AC-1.10.a: `./scripts/lint-stokd-work-localization.sh` → exit 0.
- AC-1.10.b: every `String(localized:` key introduced under `Sources/Stokd/` resolves in
  `Resources/Localizable.xcstrings`.
- AC-1.10.c: `./scripts/lint-pbxproj-test-wiring.sh` → exit 0.
- AC-1.10.d: the full `cmuxTests` suite passes and reports a non-zero executed-test count.

**Acceptance Tests**
- Test-1.10.a: Regression — the localization lint, covering AC-1.10.a and AC-1.10.b.
- Test-1.10.b: Integration — the full suite run, covering AC-1.10.d.

**Verification Commands**
```bash
set -euo pipefail
./scripts/lint-stokd-work-localization.sh
./scripts/lint-pbxproj-test-wiring.sh
xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/cmux-work-panel \
  test -only-testing:cmuxTests | tee /tmp/cmux-work-panel-tests.log
grep -qE "Executed [1-9][0-9]* tests" /tmp/cmux-work-panel-tests.log
```

## 4. Completion Criteria

- Every assertion in §2 has its evidence collected and persisted; the two `R2` assertions
  (VAL-GATE-001, VAL-DATA-001, VAL-DETAIL-001, VAL-ACTION-001) additionally carry an independent
  validator's sign-off.
- Every work item's Verification Commands exit 0 on the pushed HEAD.
- A tagged Release build (`./scripts/reload.sh --tag work-panel --launch`) launched with
  `sidebar.beta.dock.enabled`, `rightSidebar.beta.dock.enabled`, and `rightSidebar.beta.feed.enabled`
  deleted shows the Work tab, and its row count for `stokd-cloud/gdock` matches
  `stokd task list --repo stokd-cloud/gdock --all --json | jq length` plus the project and todo
  counts.
- `grep -rnE "localhost|8167|http://|URLSession" Sources/Stokd` returns nothing.
- No file under `Sources/Stokd/` mentions the docking subsystem.

## 5. Rollout & Validation

### Rollout Strategy

- No feature flag. Work becomes a default tool; the whole point of VAL-GATE-001 is that no flag
  gates it. The `gdock.workPanel.*` keys are preferences, not gates.
- Land the phase as one PR. Per repo policy the regression coverage lands as two commits — the
  failing tests first (CI red), the implementation second (CI green) — so the PR's Commits tab shows
  the tests actually catch the bug.
- Dogfood before merge: the tagged build must be exercised by the operator, and merge requires their
  explicit approval. If a fix changes runtime behavior mid-dogfood, rebuild the tag and re-notify —
  the earlier verdict covers only the build that was tested.
- Rollback trigger: any regression in right-sidebar mode-bar behavior for Files / Find / Vault, or
  any typing-latency regression in a terminal surface, reverts the whole PR rather than patching
  forward.

### Post-Launch Validation

- Panel row count continues to equal CLI row count as work items are created and completed during
  ordinary use.
- No `stokd` subprocess is spawned per keystroke or per SwiftUI `body` evaluation — confirm with the
  debug event log during a typing session with the panel open.
- Context actions dispatched from the panel produce the same result as running the verb in a
  terminal, verified for `note` and `complete` on a real work item.
- The truncation footer never appears for a normal repository; if it does, raise the per-kind limit.

## 6. Open Questions

- `stokd task view` and `stokd project view` have no `--json`. Item 1.8 parses their text output
  defensively, which is brittle by construction. Should a follow-up in `stokd-cloud/mono` add
  `--json` to both verbs so the detail pane consumes a real contract? This PRD assumes yes, later,
  and does not depend on it.
- No `list` verb accepts `--search`, so search is client-side over the loaded set. If repositories
  grow past the per-kind limit, a `--search` flag on the CLI becomes necessary; until then the
  truncation footer is the honest signal.
- The stokd-code webview offers match-category search facets (prompt / acceptance / components /
  files / docs), agent-session timelines, worktree PR/merge actions, and multi-select bulk
  operations. All are out of scope here. Which of them the operator actually wants in gdock should
  be decided after using this pass.
- Work is currently restricted to the right edge when hosted in a rail
  (`SidebarDockPlacementMatrix.allows(mode:on:)`). If docking is gutted this rule disappears with
  it; no action is taken here.
