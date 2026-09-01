# Complete Phase Review

**Project:** Stokd Work Panel
**Slug:** stokd-work-panel
**Generated:** 2026-08-28T09:17:26.934369+00:00

## Included Phases

- Phase 1: Make Work a real, CLI-backed work surface (`phase-01-make-work-a-real-cli-backed-work-surface.md`)

---

# Phase 1: Make Work a real, CLI-backed work surface

**Project:** Stokd Work Panel
**Slug:** stokd-work-panel
**Review Mode:** complete

## Work Items

### 1.1: Un-gate Work and render it on the non-dock path

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
- sidebarDockEnabled: false)` equals `[.files, .find, .sessions, .stokdWork]` → Work present at
- index 3.
- AC-1.1.b: the symbol `StokdWorkPlaceholderView` no longer exists anywhere in the target.
- AC-1.1.c: `resolvedAfterSidebarDockGateChange` no longer exists, and no code path rewrites
- `.stokdWork` to `.files`.
- AC-1.1.d: the tab host does not apply the rail section-chrome modifier; the rail host does.
- AC-1.1.e: `xcodebuild … test -only-testing:cmuxTests/StokdWorkAvailabilityTests` → exit 0.

### 1.2: Sever the sidebar-dock coupling

**Dependencies:** 1.1

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
- `sidebarDockEnabled: false`.
- AC-1.2.c: `./scripts/lint-stokd-work-dock-independence.sh` → exit 0.

### 1.3: Replace the HTTP client with a CLI-backed loader

**Dependencies:** 1.1

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
- `["task", "list", "--repo", "<slug>", "--all", "--json", "--limit", "<n>"]` (and the project /
- todo equivalents) to the injected runner.
- AC-1.3.b: given recorded CLI JSON for all three verbs, the resulting row hash set equals the
- fixture hash set exactly.
- AC-1.3.c: a non-zero exit renders a failure state containing the CLI's stderr text.
- AC-1.3.d: `grep -rnE "localhost|8167|http://|URLSession" Sources/Stokd` → no matches.
- AC-1.3.e: `xcodebuild … test -only-testing:cmuxTests/StokdWorkCLILoaderTests` → exit 0.

### 1.4: Add todos as a first-class kind

**Dependencies:** 1.3

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
- the fixture's item statuses.
- AC-1.4.b: selecting the Todos kind filter yields only `.todo` rows; `.all` includes them.
- AC-1.4.c: a todo with no `items` key renders a row with a 0/0 count and does not throw.
- AC-1.4.d: `xcodebuild … test -only-testing:cmuxTests/StokdWorkTodoKindTests` → exit 0.

### 1.5: Report set completeness instead of truncating silently

**Dependencies:** 1.3

**Implementation Details**

- Give the loader an explicit per-kind limit (default 500, well above any observed repo's work
  count) and record, per kind, whether the CLI returned exactly the limit.
- When any kind hit its limit, render a localized truncation footer naming the shown count and a
  "Load more" control that re-requests with a doubled limit.
- Failure mode: "returned exactly the limit" is a heuristic — a set whose size is exactly the limit
  shows the footer and Load more returns nothing new. That is acceptable and must not error.

**Acceptance Criteria**

- AC-1.5.a: a fixture returning exactly the limit renders the truncation footer with the correct
- shown count.
- AC-1.5.b: a fixture below the limit renders no footer.
- AC-1.5.c: Load more re-requests with a doubled limit and merges without duplicating rows by hash.
- AC-1.5.d: `xcodebuild … test -only-testing:cmuxTests/StokdWorkCompletenessTests` → exit 0.

### 1.6: Filter bar: kind, completed, sort — persisted

**Dependencies:** 1.4

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
- rows renders none of them; toggling on renders all.
- AC-1.6.b: selecting the active sort field a second time reverses the row order.
- AC-1.6.c: rows lacking `created_at` sort by `updated_at` under the Created field and are present
- in the output.
- AC-1.6.d: all four defaults keys round-trip through a fresh `UserDefaults` suite and every key is
- `gdock.`-prefixed.
- AC-1.6.e: `xcodebuild … test -only-testing:cmuxTests/StokdWorkFilterBarTests` → exit 0.

### 1.7: Search over the loaded set

**Dependencies:** 1.5

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
- each returns exactly the expected row.
- AC-1.7.b: the reported count equals matches / total-after-filters.
- AC-1.7.c: a zero-match query renders the no-matches state, and Escape restores the full set.
- AC-1.7.d: with the truncation footer active, the search count carries the "of at least" qualifier.
- AC-1.7.e: `xcodebuild … test -only-testing:cmuxTests/StokdWorkSearchTests` → exit 0.

### 1.8: Detail view

**Dependencies:** 1.4

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
- status, description, and acceptance criteria match the fixture.
- AC-1.8.b: recorded `stokd project view` output yields the equivalent project detail model.
- AC-1.8.c: recorded `stokd todo view --json` yields a todo detail model including every checklist
- item and its status.
- AC-1.8.d: unparseable output renders the raw text block, not an empty pane.
- AC-1.8.e: a non-zero exit renders the stderr text and a Retry control.
- AC-1.8.f: `xcodebuild … test -only-testing:cmuxTests/StokdWorkDetailTests` → exit 0.

### 1.9: Per-kind context actions

**Dependencies:** 1.8

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
- order, for a pending item.
- AC-1.9.b: each entry dispatches its documented argument vector to a fake runner.
- AC-1.9.c: Delete and Mark Completed do not dispatch until confirmation is accepted.
- AC-1.9.d: `complete` is absent from the menu for an item already in a terminal status.
- AC-1.9.e: a non-zero exit surfaces the stderr text.
- AC-1.9.f: `xcodebuild … test -only-testing:cmuxTests/StokdWorkActionTests` → exit 0.

### 1.10: Localization audit and full-suite green

**Dependencies:** 1.6, 1.7, 1.9

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
- `Resources/Localizable.xcstrings`.
- AC-1.10.c: `./scripts/lint-pbxproj-test-wiring.sh` → exit 0.
- AC-1.10.d: the full `cmuxTests` suite passes and reports a non-zero executed-test count.

