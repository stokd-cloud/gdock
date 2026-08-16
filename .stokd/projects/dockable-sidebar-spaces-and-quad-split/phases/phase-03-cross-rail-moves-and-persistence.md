# Phase 3: Cross-Rail Moves and Persistence

**Project:** Dockable Sidebar Spaces and Quad Split
**Slug:** dockable-sidebar-spaces-and-quad-split
**Review Mode:** complete

## Work Items

### 3.1: Moving a tool panel between rails

**Implementation Details**

- **Landing:** fork-only.
- Add `Sources/Sidebar/SidebarDockStore+ExternalDrop.swift` (NEW), setting `bonsplitController.onExternalTabDrop` on each rail store. Bonsplit routes a drag begun in a different controller to the receiving controller as external; this is the mechanism `DockSplitStore` uses at `Sources/DockSplitStore.swift:113-120`.
- The live panel is **moved, not copied**: remove it from the source store's `panels`/`surfaceIdToPanelId` and insert into the destination's, preserving `id` and `stableSurfaceIdentity` so session identity and focus history survive.
- A drop on the destination rail's bottom band creates the destination's second section with `orientation: .vertical, insertFirst: false` — the arrangement the request describes.
- **The handler must route `.split` destinations through `bonsplitController.splitPane`.** `ExternalTabDropRequest.Destination` (`vendor/bonsplit/Sources/Bonsplit/Public/BonsplitController.swift:9-24`) includes `.split(targetPane:orientation:insertFirst:)`, and the zone-derived destination is handed to the host (`vendor/bonsplit/Sources/Bonsplit/Internal/Views/PaneContainerView.swift:495-497`), so a drop onto the destination rail's **left or right** band arrives as `.split(orientation: .horizontal)` for the host to act on. 1.2's `shouldSplitPane` veto is consulted only by the `splitPane` overloads (`BonsplitController.swift:518`, `:589`, `:671`), so it protects this path **only if** the handler goes through them. Implementing the split by hand here would bypass the veto and admit a side-by-side rail split via the cross-rail route.
- Declare a **new** UTType `com.cmux.sidebar-panel-tab.transfer` in `Resources/Info.plist` under `UTExportedTypeDeclarations`, conforming to `public.data`, alongside the three existing declarations (`com.splittabbar.tabtransfer`, `com.cmux.sidebar-tab-reorder`, `com.cmux.filepreview.transfer`). Reusing `com.cmux.sidebar-tab-reorder` is forbidden: it carries workspace ids and is already accepted by terminals, browsers, and file-preview panes, so reuse would make a tool tab droppable onto a terminal as a workspace.
- Enforce `SidebarDockPlacementMatrix` (1.2) on receipt.
- Failure modes: a disallowed `PanelType` is refused and the drag returns to origin; a move that would leave the left rail with no panels when the workspace selector is its only panel is refused.

**Acceptance Criteria**

- AC-3.1.a: A tab moved from the right rail to the left rail's bottom band lands in the left rail's second section and is absent from the right rail → the requested cross-rail move works.
- AC-3.1.b: The moved panel keeps its `id` and `stableSurfaceIdentity` → it is a move, not a re-creation.
- AC-3.1.c: `./scripts/test-unit.sh -only-testing:cmuxTests/SidebarDockCrossRailTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.
- AC-3.1.d: `Resources/Info.plist` declares `com.cmux.sidebar-panel-tab.transfer` conforming to `public.data`, with 4 unique identifiers total → the new type exists and is distinct from the reorder type.
- AC-3.1.e: A placement-matrix-disallowed `PanelType` is refused on drop → no terminal or browser lands in a rail.
- AC-3.1.f: A move that would empty the left rail of its only panel is refused → the rail invariant holds.
- AC-3.1.g: A cross-rail drop whose destination is `.split(orientation: .horizontal)` is refused with the destination tree unchanged, and the handler reaches `bonsplitController.splitPane` for `.split` destinations → the 1.2 veto also governs the cross-rail path and side-by-side rail splits cannot sneak in through it.

### 3.2: Persist and restore the arrangement in the session snapshot

**Implementation Details**

- **Landing:** fork-only.
- Add two additive optional fields to `SessionWindowSnapshot` (`Sources/SessionPersistence.swift:1867`), mirroring `var dock: SessionSplitContainerSnapshot? = nil` (`:1876`):
  `var leftSidebarDock: SessionSplitContainerSnapshot? = nil` and `var rightSidebarDock: SessionSplitContainerSnapshot? = nil`.
- **Do not bump `SessionSnapshotSchema.currentVersion`** (currently `1`, `Sources/SessionPersistence.swift:14`). `Optional … = nil` is the established pattern, proven by `legacySessionWithoutDockFieldsDecodesCleanly()` in `cmuxTests/DockSessionPersistenceTests.swift`.
- Reuse `SessionSplitContainerSnapshot` (`Sources/SessionSplitContainerSnapshot.swift:8`) verbatim. The stacked split serializes as `SessionSplitLayoutSnapshot(orientation: .vertical, dividerPosition:)`; per-section ordered tabs and selection as `SessionPaneLayoutSnapshot.panelIds`/`.selectedPanelId`. Do not add a third `SessionWorkspaceLayoutSnapshot` case.
- Add `Sources/Sidebar/SidebarDockStore+SessionSnapshot.swift` (NEW) and `Sources/Sidebar/SidebarDockStore+SessionRestore.swift` (NEW), modeled on the `DockSplitStore` equivalents, using `SessionSplitContainerLayoutCodec` (`Sources/SessionSplitContainerLayoutCodec.swift:8`): `snapshot(panelIdForTabId:)`, `pruned(_:keeping:)`, `restoreScaffold(_:)`, then `applyDividerPositions(snapshotNode:liveNode:)`.
- Wire capture into `Sources/AppDelegate.swift:4535-4547` (beside `sidebar` and `dock`) and restore at `:3568-3572` / `:8715-8732`. **Add both fields to the autosave dirty fingerprint at `Sources/AppDelegate.swift:3992-4000`**, which today hashes only left-sidebar visibility, width, and selection — without this the 8-second autosave never notices a rearrangement, which is the highest-risk silent-data-loss path in this PRD and therefore carries its own acceptance criterion.
- **Legacy migration, non-destructive.** Right-rail state lives in global `UserDefaults` today (`rightSidebar.mode`, `fileExplorer.isVisible`, `fileExplorer.width`, `Sources/FileExplorerState.swift:7-15`). On first launch with the flag on and `rightSidebarDock == nil`, seed a one-section right rail with the three tool tabs and the selection taken from `rightSidebar.mode`. Leave every legacy key intact and unmodified so turning the flag off returns the user to their exact prior state. This PRD does **not** retire `fileExplorer.dividerPosition`: it is orthogonal, would be an ungated behavior change, and `FileExplorerState` does read it in `init` (`:54-55`) even though nothing renders it.
- **Collapse state is persisted.** `SessionPaneLayoutSnapshot` carries no collapse field, and `SessionSplitLayoutSnapshot` has `orientation`, `dividerPosition`, `first`, `second` only (`Sources/SessionPersistence.swift:1719-1730`) — no place for an imposed pixel extent. Since §1 forbids adding a `SessionWorkspaceLayoutSnapshot` case and bumping the schema version, persist collapse **outside** the layout tree: add `collapsedPanelIds: [UUID]?` (additive, defaulted `nil`) to the rail's `SessionSplitContainerSnapshot` envelope in a **new** wrapper type rather than mutating the shared struct, or equivalently store it as a sibling optional field on `SessionWindowSnapshot` keyed by rail edge. Either way it is an additive `Optional … = nil` field and the version stays `1`. On restore, rebuild the tree first, then re-impose the collapsed extents through the same path 1.2 uses.
- **Restore imposes no section limit.** A snapshot describing any number of sections restores as-is. There is no cap to enforce on either side; rev 1's two-slot cap and its associated pruning are deleted.
- Failure modes: a `panelId` with no decodable panel drops that tab and keeps the rest, never failing the window decode; a matrix-disallowed panel type in a rail snapshot is dropped.

**Acceptance Criteria**

- AC-3.2.a: `SessionWindowSnapshot` declares both fields as `SessionSplitContainerSnapshot?` defaulted to `nil` → the fields are additive.
- AC-3.2.b: `Sources/SessionPersistence.swift` still contains `static let currentVersion = 1` → no existing session file is invalidated, checked by content rather than by a diff.
- AC-3.2.c: `./scripts/test-unit.sh -only-testing:cmuxTests/SidebarDockPersistenceTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.
- AC-3.2.d: A session JSON with both keys absent decodes with both fields `nil` → old snapshots keep working.
- AC-3.2.e: An N-section rail round-trips orientation, per-section divider extents, per-section ordered `panelIds`, `selectedPanelId`, and collapsed state → the whole arrangement is persisted, including collapse.
- AC-3.2.f: The autosave dirty fingerprint changes when a rail is rearranged → an arrangement is not silently lost at the 8-second boundary.
- AC-3.2.g: With `rightSidebarDock == nil` and `rightSidebar.mode == "find"`, the seeded rail has one section with Find selected, and all legacy `UserDefaults` keys are unchanged → migration is non-destructive.
- AC-3.2.h: A snapshot describing **five** sections restores as five sections with their per-section divider extents and collapsed flags intact → persistence is not silently capped and collapse survives relaunch.

### 3.3: Named saved layouts carry the arrangement

**Implementation Details**

- **Landing:** fork-only.
- "Wherever layouts are saved" is two mechanisms. 3.2 covered the live session file (`~/Library/Application Support/cmux/session-<safeBundleId>.json`). This item covers **named saved layouts**: `~/.config/cmux/layouts.json`, managed by `Sources/SavedLayoutStore.swift`, element `CmuxSavedLayout { name, description, workspace: CmuxWorkspaceDefinition }`.
- Add an optional field to `CmuxWorkspaceDefinition` (`Sources/CmuxWorkspaceDefinition.swift:3`) and declare the shape explicitly in `Sources/Sidebar/CmuxSidebarDockDefinition.swift` (NEW). A session snapshot cannot be reused here because it carries live panel UUIDs, meaningless in a reusable template:
  ```swift
  struct CmuxSidebarDockDefinition: Codable, Sendable, Hashable {
      struct Section: Codable, Sendable, Hashable {
          var panels: [String]      // RightSidebarMode raw values, or "workspaceSelector"
          var selected: String?     // must be a member of `panels`
          var collapsed: Bool?      // absent == expanded
          var weight: Double?       // relative share of the rail; nil == equal share
      }
      struct Rail: Codable, Sendable, Hashable {
          var sections: [Section]   // 1..N, no upper bound
      }
      var left: Rail?
      var right: Rail?
  }
  ```
  JSON keys are the property names verbatim (`left`, `right`, `sections`, `panels`, `selected`, `collapsed`, `weight`). Three notes on why this shape differs from the session snapshot's:
  - `sections` is a **flat array**, not a nested binary tree. A rail is always a `.vertical` chain, so the tree adds nothing a template needs, and a flat list is what a human editing `layouts.json` can reason about. Applying it rebuilds the chain top-to-bottom.
  - `weight` is a **relative share**, not a `0.1...0.9` divider ratio, because with N sections a single pairwise ratio is meaningless. Weights are normalized on apply; a `nil` weight takes an equal share. This deliberately diverges from `CmuxSplitDefinition`'s ratio-clamping convention, which only ever describes a binary split.
  - `selected` is explicit because the declarative schema cannot express per-pane tab selection through the surrounding `focus` convention — a documented gap at `Sources/Workspace+LayoutCapture.swift:159-163` (issue #7444).
- `layouts.json` has no version field, and an optional field on `CmuxWorkspaceDefinition` is transparently forward- and backward-compatible; every other field there already uses `decodeIfPresent`, so no migration is needed.
- Capture in `Sources/Workspace+LayoutCapture.swift` (`captureLayoutDefinition()`), apply in `Sources/TabManager+SavedLayouts.swift`.
- Failure modes: an unknown panel string is skipped and the rest applied; a `split` outside `0.1...0.9` is clamped; `selected` not in `panels` falls back to the first entry.

**Acceptance Criteria**

- AC-3.3.a: `CmuxWorkspaceDefinition` gains the optional field decoded with `decodeIfPresent` → old `layouts.json` files decode unchanged.
- AC-3.3.b: A pre-change `layouts.json` decodes with the field `nil` → back-compat holds without a version field.
- AC-3.3.c: `./scripts/test-unit.sh -only-testing:cmuxTests/SidebarDockSavedLayoutTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.
- AC-3.3.d: Saving a layout from a window with a three-section right rail (one collapsed) and applying it to a fresh window reproduces three sections with the same panel strings, order, selection, collapsed flag, and relative weights → the arrangement travels with named layouts.
- AC-3.3.e: Section `weight` values are normalized on apply, so weights `[1, 1, 2]` yield shares of 25%/25%/50%, and a `nil` weight takes an equal share → relative weights replace the meaningless single pairwise ratio.
- AC-3.3.f: An unknown panel string is skipped without throwing → a forward-compatible file does not break the apply path.
- AC-3.3.g: A `selected` value absent from `panels` falls back to the first entry → malformed templates degrade rather than crash.

