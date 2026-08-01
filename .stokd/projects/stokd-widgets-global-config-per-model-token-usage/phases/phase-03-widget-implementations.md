# Phase 3: Widget implementations

**Project:** Stokd Widgets: Global Config + Per-Model Token Usage
**Slug:** stokd-widgets-global-config-per-model-token-usage
**Review Mode:** complete

## Work Items

### 3.1: Active-window cwd → config scope context

**Implementation Details**

- Add `Sources/Panels/Stokd/StokdWidgetContextResolver.swift`. This is the mechanism behind "leverage the cwd of whatever the active window is to provide the context to show the right things in all cases."
- Resolution chain, in order, reusing the existing accessors rather than inventing one: `AppDelegate.activeTabManagerForCommands(preferredWindow:)` (`Sources/AppDelegate+ShortcutRoutingWindow.swift:36`, which already falls back key-window → `NSApp.mainWindow` → live context → any live context) → `TabManager.selectedWorkspace` (`Sources/TabManager.swift:756`) → `Workspace.currentDirectory` (`Sources/Workspace.swift:2161`).
- Prefer the **focused surface's** reported directory when available — `Workspace.reportedPanelDirectory(panelId:)` (`Sources/Workspace+SidebarDirectories.swift:48`) for `focusedPanelId` (`Sources/Workspace.swift:2330`) — falling back to `Workspace.currentDirectory`. A workspace with several terminals in different repos should reflect the one the user is actually in.
- **Reactivity.** Observe with a `Publishers.MergeMany` exactly as `RightSidebarToolPanel.observeWorkspaceRootChanges(_:)` does (`Sources/RightSidebarToolPanel.swift:170`) — merging `workspace.$currentDirectory` (`Sources/Workspace.swift:2161`), `workspace.$panelDirectories` (`Sources/Workspace.swift:2367`), and `workspace.currentDirectoryChangeRevisionPublisher()`. **The merge is mandatory, not belt-and-braces:** `currentDirectoryChangeRevisionPublisher()` (`Sources/Workspace+SidebarDirectories.swift:118`) filters on `presentedDirectoryOnly == true`, but the `currentDirectory` `didSet` posts `userInfo: ["workspaceId": id]` **without** that key, so that publisher alone never fires for the ordinary cwd-change path.
- Also react to the active *window* changing (not just the cwd within a window): observe `NSWindow.didBecomeKeyNotification` and re-resolve. A widget in window A must show A's context while A is focused, even though the pane itself lives in one window — the requirement is "the active window", so a widget mounted in a non-key window renders the key window's context and labels which workspace it is reporting on.
- Emit an explicit context value so the UI can always say what it is showing:

  ```swift
  public struct StokdConfigContext: Sendable, Equatable {
      public let workspaceId: UUID?
      public let cwd: URL?
      public let workspaceConfigPath: URL?   // nil when no <ws>/.stokd/config.yaml exists
      public let repoSlug: String?
  }
  ```

- `workspaceConfigPath` comes from `StokdWorkspaceConfigLocator` (1.3). When nil, the widget shows global values with an explicit "no workspace config — writes will create `<cwd>/.stokd/config.yaml`" affordance rather than silently writing globally.
- All state changes happen in the `.sink`, never in a body computation, per the `CLAUDE.md` no-mutation-in-body rule.
- Failure modes: no windows (resolver returns an empty context, widget shows global-only); cwd inside a deleted dir (locator nil, banner shown); rapid window switching (coalesce to the trailing resolution).

**Acceptance Criteria**

- AC-3.1.a: The resolver returns the key window's workspace context, not the pane's host window's, when they differ.
- AC-3.1.b: Focused-surface directory wins over workspace `currentDirectory` when both are present and differ.
- AC-3.1.c: Observation merges all three publishers → `grep -q 'MergeMany' Sources/Panels/Stokd/StokdWidgetContextResolver.swift` exits 0 and the file references `$currentDirectory`.
- AC-3.1.d: A cwd change with no `presentedDirectoryOnly` key still updates the context → the regression that `currentDirectoryChangeRevisionPublisher()` alone would miss.
- AC-3.1.e: With no `<ws>/.stokd/config.yaml`, `workspaceConfigPath` is nil and the resolved write target is `<cwd>/.stokd/config.yaml`.
- AC-3.1.f: No `@Published` write occurs inside a body computation → `! grep -nE 'var body' -A 40 Sources/Panels/Stokd/StokdWidgetContextResolver.swift | grep -qE 'self\.[a-zA-Z]+ = |Task \{ @MainActor'` exits 0.
- AC-3.1.g: `xcodebuild ... -only-testing:cmuxTests/StokdWidgetContextResolverTests test` → exit 0.

### 3.2: Global Config widget view

**Implementation Details**

- Add `Sources/Panels/Stokd/StokdConfigWidgetView.swift`, rendered inside `WidgetTile`.
- Layout: header shows the resolved context (workspace name + short cwd) and a scope control; primary metric slot shows the count of keys overridden at the current scope; detail region is a grouped, searchable field list. With 74 fields across 23 groups, the tile opens on a **group summary** (group name + override count) and drills into one group — a flat 74-row list is unusable at tile size.
- Fields render by descriptor `type`: `.boolean` → toggle; `.enum` → picker over `enumValues`; `.number` → numeric field with validation; `.string` → text field; `.stringArray` → token/CSV editor; `.object` → **read-only** with an "open in editor" affordance, because the writer verb accepts one positional scalar/CSV value; `.unsupported` → read-only.
- Each row shows a **provenance badge** from `StokdLayeredValue.origin` (default / global / workspace) and, when overridden, a revert affordance calling the unset verb at that scope.
- **Scope control.** Default write scope is `workspace`. Switching to `global` requires an explicit confirmation naming the file, because `~/.stokd/config.yaml` reshapes behavior across every repo and session. Fields whose descriptor `scope` is `.global` (3 of 74) are workspace-disabled with an explanatory label. A `secret: true` field renders masked and non-editable (0 today, but the descriptor carries the flag).
- **Write path.** Every mutation calls `StokdConfigWriter` (1.3) with `workingDirectory` = the resolved context cwd. On success, re-read the affected layer and re-derive the row — do not optimistically assume the written value landed, since the CLI's validators may normalize it. On failure, keep the edit in the field, surface the CLI's verbatim stderr inline, and leave the row dirty. Per the `CLAUDE.md` shared-behavior rule there is exactly **one** mutation path; no per-row optimistic copy.
- **List discipline.** The field list is a `LazyVStack`, so every row receives an immutable value snapshot plus a closure action bundle — no row holds a store reference, per the snapshot-boundary rule. The bundle is declared explicitly:

  ```swift
  struct StokdConfigRowActions: Sendable {
      let write: @MainActor (_ key: String, _ value: StokdConfigValue) -> Void
      let revert: @MainActor (_ key: String) -> Void
      let copyKey: @MainActor (_ key: String) -> Void
      let revealInFile: @MainActor (_ key: String) -> Void
  }
  ```

- **Deterministic ordering** (so two implementations agree): groups are ordered by the descriptor array's own order as emitted by the CLI, not alphabetically, because that order is already curated; within a group, fields keep descriptor order. Search spans **all** groups and, while a query is active, replaces the group-summary view with a flat result list; clearing the query returns to the group summary. Drill-down is one level deep with a single back affordance to the summary.
- All labels/descriptions come from the descriptor (already English text from the CLI). Widget **chrome** strings — title, scope labels, confirmation copy, error framing, empty states — are cmux-owned UI and must be localized across all 20 locales in `Resources/Localizable.xcstrings`.
- Failure modes: schema fetch fails (error tile with retry, no partial form); write rejected (above); context has no workspace config (create-on-write affordance from 3.1); descriptor with an unknown type (read-only, never a crash).

**Acceptance Criteria**

- AC-3.2.a: Every descriptor `type` maps to a defined control, with `.object` and `.unsupported` read-only → no descriptor renders as an editable free-text field by accident.
- AC-3.2.b: Provenance badge matches `StokdLayeredValue.origin` for all three layer orderings.
- AC-3.2.c: Default write scope is workspace, and a global write requires explicit confirmation → an unconfirmed global write issues no CLI call.
- AC-3.2.d: Descriptor `scope == .global` fields are disabled under workspace scope.
- AC-3.2.e: A failed write preserves the pending edit and surfaces the CLI stderr verbatim; the row stays dirty.
- AC-3.2.f: A successful write re-reads the layer rather than trusting the submitted value.
- AC-3.2.g: No row view holds a store reference of any form → neither a property wrapper nor a plain store-typed (`*Store`/`*Manager`/`*Panel`) property, since `CLAUDE.md` forbids both below the `LazyVStack` boundary.
- AC-3.2.h: `xcodebuild ... -only-testing:cmuxTests/StokdConfigWidgetTests test` → exit 0.

### 3.3: Token Usage widget view

**Implementation Details**

- Add `Sources/Panels/Stokd/StokdTokenUsageWidgetView.swift`, rendered inside `WidgetTile`.
- Layout: header carries a four-way timespan selector (`24h` / `Week` / `Month` / `Total`); the primary metric slot shows total cost for the timespan with total tokens beneath; the detail region is a **provider → model** disclosure list. This is the specific gap in the existing extension view, which renders one flat row per model with no provider grouping — neither usage endpoint groups by provider (`getTokenUsage` groups by model and a derived work-item "workload"), so the widget joins provider itself from the ingest records.
- Every provider configured in the effective config appears, even with zero observed usage, in one of three explicit states: **observed** (a local transcript store exists and was read), **un-instrumented** (configured but no local store adapter — `droid`, `amp`, `bedrock`, `openrouter`, `lmStudio`, `devin`), or **idle** (store exists, no records in this timespan). A configured provider must never silently vanish.
- Per-model rows show the four dimensions separately (input / output / cache-read / cache-write) plus cost. Grok rows mark cache dimensions **unavailable** rather than `0`, since `usage_events` has no cache columns. Unpriced models show tokens with an `unpriced` marker and are excluded from the cost total, with a footer noting how many models were excluded — never a fabricated `$0.00` folded into a total.
- Models observed in transcripts but absent from `stokd model list` render tagged `unregistered`; models registered but unused render only under an explicit "show unused" toggle, so a 65-model bedrock registry does not bury actual usage.
- A dedicated `unknown` row appears whenever unattributed usage exists, with its share of the total. It is **per-provider**, not global — `TokenUsageKey` carries the provider, so unattributed Codex usage and unattributed Gemini usage are distinct rows and the user can tell which provider's attribution is degrading. Making this visible is the point: it beats a quietly-wrong breakdown.
- **Deterministic ordering:** providers sort by descending timespan cost, then by descending total tokens, then by name — so the expensive thing is first and the order is stable when costs tie or are absent. Models within a provider use the same comparator. Un-instrumented and idle providers sort last, after all observed ones. A model id observed under two different providers yields **two** rows (one per `TokenUsageKey`); they are never merged, since the same id can be served at different prices by different providers.
- Data flows from the 2.3 ingestor's published snapshot. The view **subscribes**; it owns no timer and performs no I/O. `LazyVStack` rows take value snapshots + closure bundles per the snapshot-boundary rule.
- Show a staleness indicator derived from the newest ingested record's timestamp, plus a manual refresh affordance (a user-initiated fold, not a recurring timer).
- Failure modes: no provider store present at all (empty state explaining that no local transcripts were found, listing where it looked); ingestor error (error tile with the failing root); API backfill unreachable at cold start (render live-only data with a "history unavailable" note).

**Acceptance Criteria**

- AC-3.3.a: Rows group provider → model, and every configured provider appears in exactly one of observed / un-instrumented / idle.
- AC-3.3.b: Grok cache dimensions render unavailable, not `0`.
- AC-3.3.c: Unpriced models are excluded from the cost total and counted in a footer → a fixture with one priced and one unpriced model shows only the priced model's cost in the total.
- AC-3.3.d: An `unknown` bucket with usage is rendered with its share, never dropped.
- AC-3.3.e: All four timespans re-derive from the same aggregate without re-reading files → switching timespans issues zero file opens.
- AC-3.3.f: The view owns no timer → `! grep -nE 'Timer\.scheduledTimer|Task\.sleep' Sources/Panels/Stokd/StokdTokenUsageWidgetView.swift` exits 0.
- AC-3.3.g: No row view holds a store reference of any form → neither a property wrapper nor a plain store-typed (`*Store`/`*Manager`/`*Panel`) property, since `CLAUDE.md` forbids both below the `LazyVStack` boundary.
- AC-3.3.h: `xcodebuild ... -only-testing:cmuxTests/StokdTokenUsageWidgetTests test` → exit 0.

