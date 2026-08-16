# Phase 1: Foundations

**Project:** Dockable Sidebar Spaces and Quad Split
**Slug:** dockable-sidebar-spaces-and-quad-split
**Review Mode:** complete

## Work Items

### 1.1: Rail dock store substrate and rollout flag

**Implementation Details**

- **Landing:** fork-only — the rail model reverses upstream's canvas-placement direction and is gdock product identity.
- Add `Sources/Sidebar/SidebarDockEdge.swift` (NEW): `enum SidebarDockEdge: String, Codable, Sendable, CaseIterable { case left; case right }`.
- Add `Sources/Sidebar/SidebarDockStore.swift` (NEW):
  ```swift
  @MainActor @Observable final class SidebarDockStore: BonsplitDelegate {
      let edge: SidebarDockEdge
      let windowId: UUID
      let bonsplitController: BonsplitController
      var panels: [UUID: any Panel] = [:]
      var surfaceIdToPanelId: [TabID: UUID] = [:]
      /// Pre-collapse extent per collapsed split, so expand restores the prior size.
      var rememberedExtentBySplitId: [UUID: CGFloat] = [:]
      static func makeConfiguration(collapsedSectionHeight: CGFloat) -> BonsplitConfiguration
  }
  ```
  There is deliberately **no maximum-section constant.** A rail holds as many sections as the user creates; the requester intends several small panels and asked for three-way-or-more splits.
  Structurally modeled on `DockSplitStore` (`Sources/DockSplitStore.swift:14`) but far smaller: tool panels only, no config-file seeding, no trust prompt, no remote-browser plumbing.
- `makeConfiguration(collapsedSectionHeight:)` sets: `allowSplits = true`, `allowTabReordering = true`, `allowCrossPaneTabMove = true`, `allowCloseLastPane = false`, `autoCloseEmptyPanes = true`, and **`appearance.showSplitButtons = false`**.
- **`appearance.minimumPaneHeight = collapsedSectionHeight`** (public var, `vendor/bonsplit/Sources/Bonsplit/Public/BonsplitConfiguration.swift:553`, default **100**, enforced at `vendor/bonsplit/Sources/Bonsplit/Internal/Views/SplitContainerView.swift:820`). Lowering it to the section-header height is what makes collapse possible at all: at the default 100 a section can never shrink to a ~28pt header. `collapsedSectionHeight` is `RightSidebarChromeMetrics.titlebarHeight` (`Sources/WindowChromeMetrics.swift:35`).
- **`tabBarVisibility`.** Rev 1 used `.multipleTabs` so a one-panel rail showed no tab bar. That still holds for a **one-section** rail, which must look exactly like today. But once a rail has two or more sections, every section needs a visible header — it is both the VS Code title row and the collapse control. So the store selects `.multipleTabs` when the rail has exactly one section and `.always` when it has two or more, re-applying on every section add/remove. `TabBarVisibility` has exactly these two cases (`vendor/bonsplit/Sources/Bonsplit/Public/BonsplitConfiguration.swift:28-42`); `showsTabBar(tabCount:)` returns `tabCount >= 2` for `.multipleTabs` and `true` for `.always`.
- Also set `dividerThickness` to a visible value (public var, `BonsplitConfiguration.swift:~560`) so the resize handle between sections is discoverable, matching the requester's "separator that is draggable to resize". The lane is suppressed **unconditionally** because (a) at 140pt for five buttons it occupies 51–58% of a 240–276pt rail and crowds the tab strip (it does not clip — see the corrected lane arithmetic in §0), and (b) `newTerminal`/`newBrowser` would create terminal and browser panels in a rail, which work item 1.2's placement matrix forbids. Set `appearance.tabBarHeight = RightSidebarChromeMetrics.titlebarHeight` (`Sources/WindowChromeMetrics.swift:35`; the enum is declared at `:34`) so a rail tab bar matches today's mode-bar height.
- Add `Sources/Sidebar/SidebarDockStoreRegistry.swift` (NEW):
  ```swift
  @MainActor @Observable final class SidebarDockStoreRegistry {
      let left: SidebarDockStore
      let right: SidebarDockStore
      func store(for edge: SidebarDockEdge) -> SidebarDockStore
  }
  ```
  Constructed alongside `FileExplorerState` in the window factory (`Sources/AppDelegate.swift:8753`) and injected with **`.environment(registry)`** — not `.environmentObject`, which is the `ObservableObject` mechanism and incompatible with `@Observable`. The neighbouring `.environmentObject(...)` calls at `Sources/AppDelegate.swift:8765-8767` stay as they are. The registry is read only above row boundaries.
- Define the rollout flag here, because Phase 2 reads it: extend `RightSidebarBetaFeatureSettings` (`Sources/App/WorkspaceRuntimeSettings.swift:481`) with `sidebarDockEnabledKey = "sidebar.beta.dock.enabled"`, `defaultSidebarDockEnabled = false`, and `nonisolated static func isSidebarDockEnabled(defaults: UserDefaults = .standard) -> Bool` using the `object(forKey:) != nil` guard pattern of `isFeedEnabled`/`isDockEnabled` (`:488-496`). The enum's name is right-sidebar-specific while the flag governs both rails; it is not renamed because the file is upstream-owned and a rename enlarges every future ingest conflict.
- Failure modes: a `TabID` in `surfaceIdToPanelId` with no entry in `panels` is logged and the tab dropped, never mounted empty; constructing a store without a live window is a programmer error and traps in debug, returns a store with an empty tree in release.

**Acceptance Criteria**

- AC-1.1.a: `SidebarDockEdge` declares exactly `left` and `right` → one type addresses both rails.
- AC-1.1.b: `makeConfiguration(collapsedSectionHeight:)` returns `allowCloseLastPane == false`, `appearance.showSplitButtons == false`, and `appearance.minimumPaneHeight == collapsedSectionHeight` → a rail cannot reach zero sections, no terminal/browser creation buttons appear in a rail, and the minimum pane height permits a collapse to header height instead of Bonsplit's default 100pt floor.
- AC-1.1.g: `tabBarVisibility` resolves to `.multipleTabs` for a one-section rail and `.always` for a rail with two or more sections → today's chrome-free look is preserved at one section, and every section gains a visible header once the rail stacks.
- AC-1.1.h: `SidebarDockStore` declares no maximum-section constant → nothing in the substrate caps how many sections a rail may hold.
- AC-1.1.c: `./scripts/test-unit.sh -only-testing:cmuxTests/SidebarDockStoreTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.
- AC-1.1.d: `RightSidebarBetaFeatureSettings.sidebarDockEnabledKey == "sidebar.beta.dock.enabled"`, `defaultSidebarDockEnabled == false`, and `isSidebarDockEnabled` on an empty `UserDefaults` returns `false` → the gate exists in this phase and defaults off.
- AC-1.1.e: No new file under `Sources/Sidebar/` holds a store reference in a row-level view → `rg` finds no `@ObservedObject`/`@EnvironmentObject`/`@StateObject`/`@Bindable` in the new files.
- AC-1.1.f: The registry's own injection site uses `.environment(` naming the registry value, and no `.environmentObject(` call anywhere names a registry → the `@Observable` propagation mechanism is used for this type. A bare `grep '.environment('` would be vacuous: `Sources/AppDelegate.swift` already contains one such call on `PRD_BASE_SHA`, so the check must name the registry.

### 1.2: Rail view, split behavior, and the non-drag split command

**Implementation Details**

- **Landing:** fork-only.
- Add `Sources/Sidebar/SidebarDockPanelView.swift` (NEW), modeled on `DockPanelView` (`Sources/DockPanelView.swift:11`) including its `visibilityHostId` pattern and appearance-refresh observers. Signature: `init(store: SidebarDockStore, isRailVisible: Bool, windowAppearance: WindowAppearanceSnapshot)`.
- **Splitting a rail.** A drop on the rail's top or bottom band calls `BonsplitController.splitPane(_:orientation:movingTab:insertFirst:)` (`vendor/bonsplit/Sources/Bonsplit/Public/BonsplitController.swift:653`) with `orientation: .vertical` — stacked, top/bottom, per §0 — and `insertFirst: true` for the top band, `false` for the bottom.
- **N sections, built as a right-leaning chain.** Adding a section to the bottom of a rail splits the current bottom-most pane with `orientation: .vertical, insertFirst: false`. Repeating this yields a right-leaning chain of binary splits — the representation of an N-section stack in a binary split tree. **No section count is refused.** Rev 1 capped a rail at two and vetoed a third; that cap is deleted per §5.
- **Refusing side-by-side only.** Implement `splitTabBar(_:shouldSplitPane:orientation:)` (`vendor/bonsplit/Sources/Bonsplit/Public/BonsplitDelegate.swift:38`, default `true` at `:104`) returning `false` when and only when `orientation == .horizontal`. All three `splitPane` overloads consult this veto (`BonsplitController.swift:518`, `:589`, `:671`), so no submodule change is needed. A rail is a fixed-width column; a side-by-side split would yield two ~138pt columns no tool renders usably.
- **Deterministic non-drag affordance (required, not optional).** Per §0, the top/bottom bands are reachable only in `x ∈ [80, 196]` at a 276pt right rail, `x ∈ [80, 160]` at a default 240pt left rail, and **not at all** at a left rail configured ≤ 160pt (inside the supported `120...260` range). Drag is therefore not a dependable path and for a narrow left rail not a path at all. Add a tab context-menu item and a command-palette command, both localized, calling `SidebarDockStore.moveTabToNewSection(_:position:)` where `position` is `.top`/`.bottom` of the rail. This is the path the acceptance tests drive and the one documented as primary.
- **Collapse and expand — the mechanism, which is not obvious.** Bonsplit has no collapse API; collapse is composed from the pixel-extent primitive:
  - `public func setImposedFirstExtent(_ extent: CGFloat?, forSplit splitId: UUID, fromExternal: Bool = false) -> Bool` (`vendor/bonsplit/Sources/Bonsplit/Public/BonsplitController.swift:1072`) pins a split's **first** child to an exact pixel extent, deliberately "escap[ing] the split to fraction semantics" so `dividerPositionRange` does not clamp it. `retryImposedFirstExtent(forSplit:)` (`:1108`) re-applies after constraints change, and refuses during an active divider drag.
  - Collapsing section *k* where *k* is the **first** child of split *S*: store the current extent in `rememberedExtentBySplitId[S]`, then `setImposedFirstExtent(collapsedSectionHeight, forSplit: S)`.
  - Collapsing the **last** section in the chain is the asymmetric case, because it is a *second* child and `setImposedFirstExtent` only pins first children. Collapse it by imposing on its parent split *P* an extent of `availableExtent(P) - collapsedSectionHeight`, which is container-dependent and must therefore be re-imposed when the rail resizes — exactly the case the API's doc comment describes ("hosts re-impose after their container resizes"). Re-impose from the rail's size-change observer, not from a view body.
  - Expanding: `setImposedFirstExtent(nil, forSplit: S)` then restore the remembered extent via `setDividerPosition(_:forSplit:fromExternal:)` (`BonsplitController.swift:1016`), falling back to an even distribution if nothing was remembered.
  - Collapse state lives in the store, not the view, and is persisted (work item 3.2).
- **Resize.** Every section boundary is already a draggable Bonsplit divider; set a visible `dividerThickness` (1.1) so it reads as a separator. A drag on a boundary adjacent to a collapsed section must first clear that section's imposed extent, or the drag fights the imposition.
- Add `Sources/Sidebar/SidebarDockPlacementMatrix.swift` (NEW): a checked-in table declaring, per `PanelType`, whether it may occupy a rail section. Rows: `rightSidebarTool` → allowed; `workspaceSelector` → allowed; every other `PanelType` case → refused. This adopts the one genuinely good artifact of the prior pass (`DockableSupportMatrix`) without its ambient-global machinery.
- New sections are created at an even share of the rail; emptying a section removes it through `autoCloseEmptyPanes`, and the surviving sections redistribute.
- Localize with `en` + `ja` keys `sidebarDock.moveToNewSection.top`, `sidebarDock.moveToNewSection.bottom`, `sidebarDock.section.collapse`, and `sidebarDock.section.expand`.
- Failure modes: a split request for a disallowed `PanelType` is refused with a logged reason; a drop of a pane's only tab onto its own `.center` zone is a no-op (`PaneContainerView.swift:449-458`); collapsing every section in a rail is permitted (the rail becomes a stack of headers) but the rail's own visibility toggle is unaffected; a collapse request during an active divider drag is deferred to drag end, mirroring `retryImposedFirstExtent`'s refusal contract.

**Acceptance Criteria**

- AC-1.2.a: `moveTabToNewSection(_:position: .bottom)` on a one-section rail yields 2 sections with a `.vertical` split and the moved tab alone in the second → the requested arrangement is reachable deterministically.
- AC-1.2.b: `position: .top` puts the moved tab in the **first** section (`insertFirst == true`) → both ends of the stack are targetable.
- AC-1.2.c: Repeating `moveTabToNewSection` **four** times yields **five** sections, all in one `.vertical` chain → N sections work, and nothing caps the count. This is the criterion that would have failed under rev 1.
- AC-1.2.d: `./scripts/test-unit.sh -only-testing:cmuxTests/SidebarDockSplitTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.
- AC-1.2.e: `shouldSplitPane` returns `false` for `.horizontal` and `true` for `.vertical` regardless of the current section count, and a left-band drop leaves the tree unchanged → side-by-side is refused while stacking is never refused.
- AC-1.2.f: Collapsing a non-last section pins its extent to `collapsedSectionHeight`; expanding restores the pre-collapse extent to within 1pt → collapse/expand round-trips without drift.
- AC-1.2.g: Collapsing the **last** section in the chain also reduces it to `collapsedSectionHeight`, and it stays collapsed across a rail resize → the asymmetric second-child case is implemented and re-imposed, not merely handled at rest.
- AC-1.2.h: The placement matrix refuses every `PanelType` except `rightSidebarTool` and `workspaceSelector` → no terminal, browser, markdown, or file-preview panel can occupy a rail section.
- AC-1.2.i: Emptying a section removes it and the rail's section count drops by one → `autoCloseEmptyPanes` governs teardown.
- AC-1.2.j: All four new affordance strings have `en` and `ja` entries with `state == "translated"` and differing values → the new UI text is genuinely localized.

### 1.3: Quad split shared action

**Implementation Details**

- **Landing:** fork-only. The `.custom("cmux.splitQuad")` design is justified by *this fork's* inability to push to `manaflow-ai/bonsplit`. That constraint does not apply to upstream, which owns bonsplit and would reasonably prefer a built-in `.splitQuad` case dispatched like `.splitRight`/`.splitDown` at `vendor/bonsplit/Sources/Bonsplit/Internal/Views/TabBarView.swift:1681-1686`. Shipping the indirect design upstream would invite exactly that rework, so the quad split is **fork-only** and the fork accepts divergence on these files. An optional upstream contribution is recorded as a follow-up in §5; nothing in this PRD blocks on it.
- Add `Sources/QuadSplitAction.swift` (NEW): `@MainActor enum QuadSplitAction { static func perform(inPane paneId: PaneID, workspace: Workspace) -> Bool }`.
- **The recipe, with exact API and pane-id derivation.** `splitPaneWithNewTerminal` returns `TerminalPanel?` (`Sources/Workspace.swift:10665-10672`), **not** a `PaneID`, and no `Workspace.paneId(forPanelId:)` helper exists — so the second target pane's id must come from the controller's focus, which that function sets via `selectTab` + `focus()` (`Sources/Workspace.swift:10725-10726`):
  ```swift
  // 1. side-by-side: left | right
  guard workspace.splitPaneWithNewTerminal(
      targetPane: paneId, orientation: .horizontal, insertFirst: false,
      workingDirectory: nil, initialInput: nil) != nil else { return false }
  guard let rightPaneId = workspace.bonsplitController.focusedPaneId else { return false }
  // 2. stack the left column: top / bottom
  guard workspace.splitPaneWithNewTerminal(
      targetPane: paneId, orientation: .vertical, insertFirst: false,
      workingDirectory: nil, initialInput: nil) != nil else { return false }
  // 3. stack the right column
  guard workspace.splitPaneWithNewTerminal(
      targetPane: rightPaneId, orientation: .vertical, insertFirst: false,
      workingDirectory: nil, initialInput: nil) != nil else { return false }
  return true
  ```
  Reminder: `.horizontal` is side-by-side, `.vertical` is stacked.
- **Do not wrap the sequence in an `isProgrammaticSplit` guard.** `splitPaneWithNewTerminal` already sets it and clears it with an inner `defer` (`Sources/Workspace.swift:10712-10713`), so an outer set would be cleared when the first inner call returns and would be silently ineffective for splits 2 and 3. No additional guard is needed. (The DEBUG stress harness at `Sources/AppDelegate.swift:10000` builds a 2×2 via a different, panel-id-keyed API, `newTerminalSplit(from:orientation:focus:)` at `Sources/Workspace.swift:6738`; it is a shape reference only, not the API used here.)
- Pre-check the veto `splitTabBar(_:shouldSplitPane:orientation:)` once before starting so a remote-tmux mirror pane (which vetoes local splits, `Sources/Workspace.swift:11884`) produces zero splits rather than a partial grid.
- Add `TabManager.createQuadSplit(tabId:surfaceId:focus:) -> Bool` in `Sources/TabManager.swift`, mirroring `createSplit(tabId:surfaceId:direction:focus:)` (`:3739`) and its `sentryBreadcrumb("split.create", …)` instrumentation (`:3743`).
- Failure modes: target pane gone → `false`; `allowSplits == false` → `false`; a veto after the first split → return `false` leaving the partial tree, logged as an inconsistency (unwinding is not attempted).

**Acceptance Criteria**

- AC-1.3.a: `Sources/QuadSplitAction.swift` declares `static func perform(inPane:workspace:) -> Bool` → one shared implementation exists.
- AC-1.3.b: `perform` on a single-pane workspace leaves exactly 4 panes → `allPaneIds.count == 4`.
- AC-1.3.c: `./scripts/test-unit.sh -only-testing:cmuxTests/QuadSplitActionTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.
- AC-1.3.d: Each of the 4 resulting panes holds exactly one terminal panel → no empty and no double-tabbed pane.
- AC-1.3.e: With `allowSplits == false`, `perform` returns `false` and the pane count stays 1 → splits are gated.
- AC-1.3.f: `Sources/QuadSplitAction.swift` contains exactly 3 `splitPaneWithNewTerminal` calls and no `isProgrammaticSplit` assignment → the recipe is the specified three splits with no ineffective outer guard.
- AC-1.3.g: The resulting tree is a genuine 2×2 — the root is a `.horizontal` split whose two children are each a `.vertical` split of two leaf panes — and `focusedPaneId` after step 1 differs from the input `paneId` → the grid *shape* is correct, not merely the pane count. This criterion exists because a regression in the `focusedPaneId` derivation, or an inverted `orientation`/`insertFirst`, would make steps 2 and 3 both split the left column, yielding a 3-high left stack beside one right pane. That wrong shape satisfies AC-1.3.b, AC-1.3.d, and AC-1.3.f while failing the stated objective, so those criteria alone cannot gate it.

### 1.4: Quad split button and entrypoints

**Implementation Details**

- **Landing:** fork-only, for the reason given in 1.3.
- **Scope note.** The request asked for the tab-bar **button** only. The additional entrypoints below are required by the repo's shared-behavior policy (`skills/cmux-shared-behavior/SKILL.md`), not by the request, and are scoped in deliberately. The `⌃⌘D` default binding is likewise an addition, recorded as a decision in §5.
- Add `splitQuad = "cmux.splitQuad"` to `CmuxSurfaceTabBarBuiltInAction` (`Sources/CmuxSurfaceTabBarBuiltInAction.swift:4`). There are **five exhaustive switches** over this enum plus one String-keyed alias map, and missing any of the five breaks the build:
  1. `defaultIcon` (`Sources/CmuxSurfaceTabBarBuiltInAction.swift:44`) — return `square.split.2x2`, matching the `square.split.2x1`/`square.split.1x2` family.
  2. `bonsplitAction` (`:65`) — return `.custom("cmux.splitQuad")`.
  3. The command-palette `title`/`keywords` switch at `Sources/CmuxConfig.swift:1382-1394`. Because this switch *generates* the palette entry, no separate palette contribution is added for the quad action.
  4. `Workspace.executeSurfaceTabBarCommandButton(identifier:inPane:)` (`Sources/Workspace.swift:12274`) — see the routing bullet below.
  5. **`AppDelegate.executeConfiguredCmuxAction(_:context:preferredWindow:onExecuted:onCloudVMCompletion:)`** — the outer `switch action.action` is at `Sources/AppDelegate.swift:15491`, its `case .builtIn(let builtIn):` arm at `:15492`, and the inner `switch builtIn` at `:15493` covers all eight cases with **no `default:`**, ending with `case .splitDown:` around `:15538`. This is the easiest to miss and the most damaging: it is the executor for configured cmux actions, so omitting it both breaks the build and, once it compiles, would leave the quad action a silent no-op from the config-action path. A bare `grep -qF 'splitQuad' Sources/AppDelegate.swift` cannot detect the omission because the shortcut routing already satisfies it, so the acceptance criterion below names the site explicitly.
  Additionally, `init?(configID:)` (`Sources/CmuxSurfaceTabBarBuiltInAction.swift:14-38`) is **not** exhaustive over the enum — it switches on a `String` with `default: return nil`. It still needs a `"cmux.splitQuad"` / `"splitQuad"` alias arm so the identifier parses from config, but it will compile without one.
- Append `.splitQuad` to `CmuxSurfaceTabBarButton.defaults` (`Sources/CmuxConfig.swift:943-948`) and the fallback list (`:2093-2098`), giving `newTerminal, newBrowser, splitRight, splitDown, splitQuad` — vertical divider, horizontal divider, quad last, as requested.
- **Tooltip.** `BonsplitConfiguration.SplitButtonTooltips` (`vendor/bonsplit/Sources/Bonsplit/Public/BonsplitConfiguration.swift:394-412`) has exactly four fields and no custom slot, so it cannot carry a quad tooltip and must not be touched (nor may `Workspace.currentSplitButtonTooltips()`, `Sources/Workspace.swift:2664-2671`). Set the tooltip on the button instead: `SplitActionButton.tooltip` (`BonsplitConfiguration.swift:295`), which `splitActionButtonTooltip` prefers over the tooltips struct (`TabBarView.swift:1654-1656`), populated where cmux buttons map to Bonsplit buttons (`Sources/Workspace.swift:3354`). Do not copy the bare-literal tooltip bug at `Sources/Workspace.swift:2668-2669`.
- **Custom-action routing.** Add a **new** case to the switch in `Workspace.executeSurfaceTabBarCommandButton(identifier:inPane:)`: `case .splitQuad: _ = QuadSplitAction.perform(inPane: pane, workspace: self)`. Do **not** add `.splitQuad` to the deliberate `break` list at `Sources/Workspace.swift:12283`. The identifier arrives via `splitTabBar(_:didRequestCustomAction:inPane:)` (`Sources/Workspace.swift:12383-12390`), and the `guard let executable = surfaceTabBarCommandButtons[identifier]` at `:12267` is satisfied because `applySurfaceTabBarButtons` (`:3285`) registers the button at `:3350`.
- Give the Dock the same list: `Sources/DockSplitStore+Appearance.swift:37` omits `splitButtons:` and no `applySurfaceTabBarButtons` equivalent runs for Docks, so without this the Dock is the one surface missing the button.
- **The five real entrypoints** (the config enum and the JSON schema are registration surfaces, not entrypoints):
  1. Keyboard shortcut — add `splitQuad` to `KeyboardShortcutSettings.Action` (`Sources/KeyboardShortcutSettings.swift:64`, panes block `:129-138`), a `label`, and a `defaultShortcut` (`⌃⌘D`) near `:452-460`; route the event beside `Sources/AppDelegate.swift:13952`. **Critically, mirror the Dock routing:** `.splitRight` first calls `routeSplitToFocusedDock(kind:direction:preferredWindow:)` (`Sources/AppDelegate.swift:13959`) so a focused Dock pane splits instead of the main area, behavior documented at `docs/dock.md:23`. Without the equivalent for quad, `⌃⌘D` would split the main area while a Dock pane has focus, contradicting the Dock button.
  2. View menu — an item beside `Sources/cmuxApp.swift:1029`/`:1033`.
  3. Command palette re-dispatch — `Sources/ContentView+RightSidebarCommandPalette.swift:71` **and** `Sources/ContentView+AgentChatCommandPalette.swift:13`, both of which map palette ids to `CmuxSurfaceTabBarBuiltInAction`.
  4. Terminal context menu — beside `Sources/GhosttyTerminalView.swift:7010`/`:7022`, gated by `canSplitCurrentSurface()` (`:7063`).
  5. Socket/CLI — accept `quad` at **both** `new_split` sites: the dispatch `case "new_split":` (`Sources/TerminalController.swift:1921`) and `newSplit(_ args:)` (`:11971`), plus the usage text at `:10779`.
- Registration surfaces to update: `ShortcutAction` (`Packages/macOS/CmuxSettings/Sources/CmuxSettings/Values/ShortcutAction.swift:9`, panes block `:92-101`, `.panes` category `:198-205`, a **localized** label — do not copy the bare literals at `:403-404`), `ShortcutAction+Defaults.swift`, and `"splitQuad"` in the `shortcuts.bindings` `propertyNames` enum in `web/data/cmux.schema.json`.
- Failure modes: a Dock-focused quad request where the Dock vetoes returns `false` without touching the main area; an unknown CLI direction string returns the existing usage error.

**Acceptance Criteria**

- AC-1.4.a: `CmuxSurfaceTabBarButton.defaults` has 5 elements ending in the quad entry, and `CmuxSurfaceTabBarBuiltInAction.splitQuad.bonsplitAction == .custom("cmux.splitQuad")` → the button is 5th and routes through the no-submodule-change path.
- AC-1.4.b: The pinned `vendor/bonsplit` submodule commit is unchanged and the submodule worktree is clean → the no-submodule-change constraint holds, checked without a base ref.
- AC-1.4.c: `./scripts/test-unit.sh -only-testing:cmuxTests/QuadSplitButtonTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.
- AC-1.4.d: All five exhaustive switches handle `.splitQuad` — `defaultIcon`, `bonsplitAction`, `Sources/CmuxConfig.swift:1382-1394`, `Sources/Workspace.swift:12274`, and `Sources/AppDelegate.swift:15491` — and `init?(configID:)` parses `"cmux.splitQuad"` → the build is not broken and no dispatch path silently no-ops.
- AC-1.4.e: With a Dock pane focused, the quad shortcut splits the Dock and leaves the main area's pane count unchanged → shortcut and button agree about the Dock.
- AC-1.4.f: Each of the five entrypoints resolves to `QuadSplitAction.perform` or `TabManager.createQuadSplit` → one shared action path.
- AC-1.4.g: The Dock appearance supplies the 5-button list → the Dock is not the odd surface out.

