# Complete Phase Review

**Project:** Dockable Sidebar Spaces and Quad Split
**Slug:** dockable-sidebar-spaces-and-quad-split
**Generated:** 2026-07-31T19:58:02.598059+00:00

## Included Phases

- Phase 1: Foundations (`phase-01-foundations.md`)
- Phase 2: Mount Both Rails (`phase-02-mount-both-rails.md`)
- Phase 3: Cross-Rail Moves and Persistence (`phase-03-cross-rail-moves-and-persistence.md`)
- Phase 4: Rollout Surfacing, Localization Audit, and Documentation (`phase-04-rollout-surfacing-localization-audit-and-documentation.md`)

---

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


---

# Phase 2: Mount Both Rails

**Project:** Dockable Sidebar Spaces and Quad Split
**Slug:** dockable-sidebar-spaces-and-quad-split
**Review Mode:** complete

## Work Items

### 2.1: Right rail mounted on the dock store

**Implementation Details**

- **Landing:** fork-only.
- Replace `RightSidebarPanelView`'s `VStack { modeBar; contentForMode }` (`Sources/RightSidebarPanelView.swift:177-181`) with `SidebarDockPanelView` driven by the window's `SidebarDockStore(edge: .right)`, **behind `RightSidebarBetaFeatureSettings.isSidebarDockEnabled`**. With the flag off, the legacy path renders unchanged.
- **Tab set, stated per mode.** `RightSidebarMode` has six cases (`Sources/RightSidebarPanelView.swift:17-22`) but only three have a `Panel` adapter (`paneModes = [.files, .find, .sessions]`, `:59`). Dispositions:
  - `.files`, `.find`, `.sessions` → included, each backed by `RightSidebarToolPanel(workspace:mode:)` (`Sources/RightSidebarToolPanel.swift:22`).
  - `.feed` → **excluded** from the rail tab set; it keeps rendering through the legacy `contentForMode` path when selected. No `FeedToolPanel` is created by this PRD.
  - `.dock` → **excluded.** The Dock is itself a `BonsplitController`; nesting one inside a rail section's Bonsplit pane is out of scope.
  - `.customSidebar` → **excluded**; it is already filtered out of `availableModes()` and renders `EmptyView()`.
  A fresh right rail therefore has exactly three tabs: Files, Find, Vault.
- **Source-of-truth contract for selection (the load-bearing rule).** `SidebarDockStore` is the **sole source of truth**. `FileExplorerState.mode` becomes a *derived mirror* defined as *the mode of the selected tab in the focused section*. It is written exactly once, from `splitTabBar(_:didSelectTab:inPane:)` and `splitTabBar(_:didFocusPane:)` — never from a view body, per §1. `mode`'s public setter is replaced by `SidebarDockStore.focusTab(for:)`, and all existing setters are rewritten to call it: tab click (`Sources/RightSidebarPanelView.swift:238-245`), `keyDown` (`:500-508`), command palette (`Sources/ContentView+RightSidebarCommandPalette.swift`), CLI/socket (`Sources/RightSidebarRemoteCommand.swift`, `Sources/AppDelegate.swift:6644`/`:6771`/`:6917`), and focus memory (`Sources/MainWindowFocusController.swift:147`/`:157`). When two or more sections are visible, `mode` names only the focused section's selection — it is explicitly incapable of describing both, which is why the store, not `mode`, is persisted. On restore the snapshot wins and `rightSidebar.mode` is overwritten from it.
- **Chrome disposition — explicit, because most of `modeBar` has no Bonsplit equivalent.** Bonsplit's tab bar has one host-extensible lane (`splitButtons`) and that lane is suppressed for rails (1.1). Per affordance in `modeBar` (`Sources/RightSidebarPanelView.swift:216-266`):
  | Affordance | Disposition under the flag |
  |---|---|
  | Tab height | Preserved: `appearance.tabBarHeight = RightSidebarChromeMetrics.titlebarHeight` (`Sources/WindowChromeMetrics.swift:34`). Note the type is `RightSidebarChromeMetrics`; `RightSidebarChromeStyle` is a **file name**, not a type. |
  | `WindowDragHandleView()` | **Dropped.** Rail tab-bar area is no longer a window drag handle. |
  | `TitlebarDoubleClickMonitorView()` | **Dropped.** |
  | Per-tab keyboard-shortcut hint overlay | **Dropped.** Bonsplit tabs expose no hint slot. |
  | Numeric feed badge (`badgeCount:`) | **Moot** — `.feed` is excluded from the rail. Bonsplit offers only `showsNotificationBadge: Bool`, no count. |
  | `openAsPaneButton` / `closeButton` | **Relocated** out of the tab bar into `SidebarDockPanelView`'s own header row, retaining accessibility ids `RightSidebar.openAsPaneButton` and the close label. |
  | `reportRightSidebarChromeGeometryForBonsplitUITest` | **Dropped** under the flag; the UI tests that consume it are conditionalized below. |
- **Accessibility identifiers are partially lost, and this is unavoidable.** Bonsplit sets `accessibilityIdentifier` in only three places (`TabBarView.swift:1310`, `:1376`, `:1545` — drop indicator and split-action buttons); `Tab` has no identifier field and Bonsplit exposes no per-tab identifier or view-injection API. So `RightSidebar` and `RightSidebarModeBar` are preserved on the container, but **`RightSidebarModeButton.<mode.rawValue>` cannot be set on Bonsplit tabs without a submodule change and is lost under the flag.** **Exactly three** UI test suites assert against the identifier or the mode-bar height and must be conditionalized on `isSidebarDockEnabled`: `cmuxUITests/FeedSidebarUITests.swift` (`:365`, `:401`, `:409`), `cmuxUITests/RightSidebarChromeHeightUITests.swift` (`:40`, `:72`, `:91`), and `cmuxUITests/BonsplitTabDragUITests.swift:103` (`testRightSidebarModeBarKeepsFixedHeightAcrossPresentationModes`). `cmuxUITests/SettingsSidebarBetaBehaviorUITests.swift` is deliberately **excluded**: it names `RightSidebarModeButton.dock` only in comments (`:18`, `:245`) and makes no assertion on it, so it needs at most a comment update and must not be given a dead flag guard purely to satisfy a grep. Adding `Bonsplit.Tab.accessibilityIdentifier` is a named upstream follow-up in §5.
- Preserve the hidden-rail mount short-circuit (`RightSidebarContentMountPolicy`, enum at `Sources/RightSidebarPanelView.swift:66`, called at `:379`).
- Localize any new header strings with `en` + `ja`.
- Failure modes: a requested mode with no panel is created rather than no-oped; a hidden rail mounts no content.

**Acceptance Criteria**

- AC-2.1.a: With the flag off, `RightSidebarPanelView` renders the legacy `modeBar` path and the three UI test suites above pass unchanged → the change is reversible at runtime.
- AC-2.1.b: With the flag on, a fresh right rail has exactly 3 tabs (Files, Find, Vault) and `.feed`/`.dock`/`.customSidebar` are absent → the tab set is exactly as specified.
- AC-2.1.c: `./scripts/test-unit.sh -only-testing:cmuxTests/RightSidebarDockMountTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.
- AC-2.1.d: `FileExplorerState.mode` changes when focus moves between two sections with different selections, and is written only from the two delegate callbacks → the derived-mirror contract holds and no view body writes it.
- AC-2.1.e: `RightSidebar` and `RightSidebarModeBar` resolve with the flag on → the container identifiers survive.
- AC-2.1.f: Every UI test asserting `RightSidebarModeButton.*` or the mode-bar height is conditionalized on the flag → the known identifier loss does not silently red CI.
- AC-2.1.g: Any new header string has `en` + `ja` with `state == "translated"` and differing values.

### 2.2: Workspace list as a dockable panel

**Implementation Details**

- **Landing:** fork-only.
- Add `workspaceSelector` to `PanelType` (`Sources/Panels/Panel.swift:6`) with a case-insensitive branch in its custom `init(from:)` (`:19`), matching `.filePreview`/`.rightSidebarTool`.
- Add `Sources/Sidebar/WorkspaceSelectorPanel.swift` (NEW): `@MainActor final class WorkspaceSelectorPanel: Panel, ObservableObject` with `panelType = .workspaceSelector`, `stableSurfaceIdentity`, and `displayTitle = String(localized: "sidebarDock.workspaces.title", defaultValue: "Workspaces")`.
- **Where the snapshot boundary sits, and why the panel may hold references.** `VerticalTabsSidebar`'s `==` (`Sources/ContentView.swift:10393-10398`) shows it already holds object references — `windowId`, `observedWindowReference.window`, `updateViewModel`, `fileExplorerState`. The row boundary is the `ForEach` inside `workspaceScrollArea`, which lives **inside** `VerticalTabsSidebar`. `WorkspaceSelectorPanel` is the container *above* that boundary, so it may hold those references; the rule constrains only views *below* it. Nothing below the boundary changes. Factory signature: `init?(workspace: Workspace, windowId: UUID, updateViewModel: UpdateViewModel, fileExplorerState: FileExplorerState, observedWindowReference: ObservedWindowReference)` returning `nil` when any dependency is missing.
- Do not add stored properties to `VerticalTabsSidebar` without updating `==`.
- **Guard-scope risk to acknowledge:** `scripts/check-sidebar-lazy-layout.py` fails loudly if a guarded function is renamed or removed, and it scans `workspaceScrollContent`/`workspaceRows` in five fixed files. This work item must not rename them. It also cannot see the new file, so compliance for new code is asserted by `rg`.
- The prior pass's `LeftWorkspaceSelectorPanel` is read as a worked example only; it is a hand-rolled canvas singleton and is not ported.
- Failure modes: missing dependency → `nil` from the factory, logged; never a panel wrapping an empty list.

**Acceptance Criteria**

- AC-2.2.a: `PanelType` contains `workspaceSelector` and decodes case-insensitively → the type round-trips through persistence.
- AC-2.2.b: `WorkspaceSelectorPanel.panelType == .workspaceSelector` and the factory returns `nil` when a dependency is absent → the wrapper exists and fails closed.
- AC-2.2.c: `./scripts/test-unit.sh -only-testing:cmuxTests/WorkspaceSelectorPanelTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.
- AC-2.2.d: `python3 tests/test_ci_sidebar_lazy_layout_guard.py` exits 0 **and** `rg` finds no store-holding row view in the new file → both the legacy guard and the new-file gap are covered.
- AC-2.2.e: `workspaceScrollContent` and `workspaceRows` still exist in `Sources/ContentView.swift` → the guard's scope was not broken by a rename.
- AC-2.2.f: `sidebarDock.workspaces.title` has `en` + `ja` with `state == "translated"` and differing values.

### 2.3: Left rail mounted on the dock store

**Implementation Details**

- **Landing:** fork-only.
- Mount the left rail through `SidebarDockPanelView` with `SidebarDockStore(edge: .left)`, seeded with one `WorkspaceSelectorPanel`, replacing the default-provider branch of the content switch at `Sources/ContentView.swift:10854-10867`. The extension/custom-sidebar provider branch (`CmuxExtensionSidebarSelection`, `Sources/ContentView.swift:10031`) is untouched. Gate on `isSidebarDockEnabled`.
- Because `tabBarVisibility == .multipleTabs`, a left rail holding only the workspace selector renders **no tab bar**, matching today exactly. A tab bar appears once a second panel is docked — the intended signal that the rail holds two things.
- Left rail width, visibility, and resize behavior are unchanged: `SidebarState` (`Sources/Sidebar/SidebarState.swift:6`), `SidebarLayoutModel` (`Sources/Sidebar/SidebarLayoutModel.swift:15`), and `SidebarResizeInteraction` are not modified by this work item.
- The existing workspace-row drag payload `com.cmux.sidebar-tab-reorder` (`Sources/Sidebar/SidebarTabDragPayload.swift:6`) carries **workspace ids** despite its name and is already accepted by terminals, browsers, and file-preview panes. It is untouched, and tool-panel tab drags must not reuse it (3.1 declares a distinct type).
- Failure modes: a left rail that somehow reaches zero panels re-seeds the workspace selector and logs an invariant violation (`allowCloseLastPane = false` should make this unreachable).

**Acceptance Criteria**

- AC-2.3.a: A left rail holding only the workspace selector shows no tab bar → today's appearance is preserved, verified through `showsTabBar(tabCount: 1) == false` rather than a visual claim.
- AC-2.3.b: Docking a second panel makes the tab bar appear → `showsTabBar(tabCount: 2) == true`.
- AC-2.3.c: `./scripts/test-unit.sh -only-testing:cmuxTests/LeftSidebarDockMountTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.
- AC-2.3.d: `Sources/Sidebar/SidebarState.swift` and `Sources/Sidebar/SidebarLayoutModel.swift` are byte-identical to their `PRD_BASE_SHA` contents → left rail geometry behavior is untouched, checked without relying on a working-tree diff.
- AC-2.3.e: Workspace-row reordering still works → the existing payload is neither repurposed nor broken.
- AC-2.3.f: A left rail with zero panels re-seeds the workspace selector → the invariant is self-healing.


---

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


---

# Phase 4: Rollout Surfacing, Localization Audit, and Documentation

**Project:** Dockable Sidebar Spaces and Quad Split
**Slug:** dockable-sidebar-spaces-and-quad-split
**Review Mode:** complete

## Work Items

### 4.1: Settings surfacing and configuration

**Implementation Details**

- **Landing:** fork-only.
- The flag key `sidebar.beta.dock.enabled` (default `false`) is created in 1.1. This item does not redefine it; it surfaces it in Settings beside the existing Feed and Dock beta rows and accepts it from `~/.config/cmux/cmux.json` on the same path those use, then verifies the declared shape has not drifted.
- Deliberately not a PostHog flag: `scripts/lint-feature-flags.py` requires a `-release`/`-experiment`/`-permission` suffix, an owner, a `reviewBy` expiry, a `defaultWhenUnavailable`, and a single evaluation site — none of which suit a long-lived UI beta toggle read from several views. The Feed and Dock betas set the precedent.
- Default stays `false` for the whole of this PRD; flipping it is out of scope and gated on dogfood (§4).
- Localize the Settings row label and help text with `en` + `ja`.
- Failure modes: with the flag off, no rail writes a snapshot field and every rail renders its pre-PRD path; toggling at runtime cannot corrupt an existing snapshot because the fields are additive and simply unread.

**Acceptance Criteria**

- AC-4.1.a: A Settings row toggles `sidebar.beta.dock.enabled` and the value round-trips through `~/.config/cmux/cmux.json` → the flag is user-reachable by both routes.
- AC-4.1.b: `python3 scripts/lint-feature-flags.py` exits 0 → the PostHog registries are untouched and still lint clean.
- AC-4.1.c: `./scripts/test-unit.sh -only-testing:cmuxTests/SidebarDockBetaFlagTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.
- AC-4.1.d: With the flag off, a written session file contains neither `leftSidebarDock` nor `rightSidebarDock` → the dark path is inert.
- AC-4.1.e: Toggling the flag leaves an existing session snapshot loadable → no corruption on either transition.
- AC-4.1.f: The Settings row label and help text have `en` + `ja` with `state == "translated"` and differing values.

### 4.2: Localization audit and documentation

**Implementation Details**

- **Landing:** fork-only.
- Enumerate every user-facing surface this project added and verify each has `en` + `ja` entries with `state == "translated"` and a `ja` value differing from `en`. The complete key list: `sidebarDock.splitRail.top`, `sidebarDock.splitRail.bottom` (1.2); the five quad keys `shortcut.splitQuad.label`, `menu.view.splitQuad`, `command.terminalSplitQuad.title`, `terminalContextMenu.splitQuad`, `workspace.tooltip.splitQuad` (1.4) — note there is deliberately **no** `command.terminalSplitQuad.subtitle`, because every built-in config action shares the single subtitle `command.cmuxConfig.builtInSubtitle` (`Sources/CmuxConfig.swift:1400`) and no per-action subtitle mechanism exists; demanding such a key would make this criterion unsatisfiable; `sidebarDock.workspaces.title` (2.2); the right-rail header strings (2.1); and the Settings row strings (4.1).
- Web-side catalogs: add `cmux.splitQuad` to the `nightlyActionRegistryDesc` and `actionTypeBuiltin` strings in `web/messages/en.json` and `web/messages/ja.json`; these are prose sentences carrying inline element tags, so the TSX consumer that renders them must gain a matching tag handler. Add the `splitQuad` entry with `en`/`ja` descriptions to the `split-panes` category in `web/data/cmux-shortcuts.ts`.
- **The shipped Dock docs page is localized and must not be missed:** `web/app/[locale]/(landing)/docs/dock/page.tsx` renders via `useTranslations("docs.dock")` from `web/messages/{en,ja}.json`. Updating only the internal `docs/dock.md` would leave the user-visible page stale in both locales, violating §1's "update every supported message catalog". Update the `docs.dock` keys covering the split affordances and shortcuts, including the Dock-focused shortcut behavior described at `docs/dock.md:23`.
- Run the prescribed audit: parse the touched localization files, compare changed keys across `en`/`ja`, and `rg` the changed Swift/TS/TSX/docs files for newly introduced bare English in `Text(`, `Button(`, `.help(`, `.safeHelp(`, `.tooltip(`, alert titles, and accessibility labels. Record the result in the handoff, including anything unverified. `defaultValue`, English fallback text, and schema descriptions do not count.
- Record the locale bookkeeping accurately: `Resources/Localizable.xcstrings` has 20 locales; `knownRegions` has 19 entries = 18 locales + Base, missing `km` and `uk`; `CLAUDE.md` and `skills/cmux-localization/SKILL.md` both say "English and Japanese". This PRD meets the `en` + `ja` bar and does not attempt the other 18.
- Add `docs/sidebar-docking.md` (NEW) documenting: rails as dock spaces; that a horizontal divider is Bonsplit `.vertical`; the drop bands being 25% edge bands with an 80pt floor, with the reachable band given for **both** rails (`x ∈ [80, 196]` at a 276pt right rail, `x ∈ [80, 160]` at a 240pt left rail, and unreachable at a left rail ≤ 160pt) and the non-drag command named as the primary path; that a rail holds N sections with no cap; that each section is collapsible via an imposed pixel extent and every boundary is a drag-resize handle; cross-rail moves; the placement matrix; and both persistence mechanisms (the session file and `layouts.json`).
- Update `docs/dock.md` to distinguish the Dock from sidebar dock spaces, and add a `CHANGELOG.md` entry.

**Acceptance Criteria**

- AC-4.2.a: Every key in the enumerated list has `en` + `ja` with `state == "translated"` and differing values → the audit passes for the complete surface list.
- AC-4.2.b: `docs/sidebar-docking.md` documents the orientation inversion, the drop-band geometry **with both rails' numbers including the unreachable ≤160pt left-rail case**, the absence of a section cap, the collapse mechanism, and both persistence mechanisms → the non-obvious constraints are written down against the real worst case.
- AC-4.2.c: All CI guard scripts pass → `./scripts/check-pbxproj.sh`, `python3 scripts/check-workspace-package-groups.py --check`, `python3 scripts/check-package-resolved-policy.py`, `./tests/test_ci_pbxproj_test_wiring.sh`, and `python3 tests/test_ci_sidebar_lazy_layout_guard.py` all exit 0.
- AC-4.2.d: `web/messages/en.json` and `ja.json` both contain `cmux.splitQuad`, and the `docs.dock` keys mention the quad affordance → the user-visible docs page is not stale in either locale.
- AC-4.2.e: `docs/dock.md` distinguishes the Dock from sidebar dock spaces → the two features are not conflated.
- AC-4.2.f: No bare English literal appears in a user-facing Swift call in any file this project changed → `rg` over the changed set is clean.

