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

