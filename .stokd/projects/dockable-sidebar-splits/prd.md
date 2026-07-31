# PRD: Dockable Sidebar Spaces and Quad Split

## 0. Source Context

**Derived From:** Direct feature request, 2026-07-31 — a revision of a previously attempted dockable system.
**Feature Name:** Dockable Sidebar Spaces and Quad Split
**PRD Owner:** Brian Stoker
**Last Updated:** 2026-07-31
**Repository:** `stokd-cloud/ghostty-dock` (fork of `manaflow-ai/cmux`), branch `main`.
**PRD base commit (`PRD_BASE_SHA`):** `69b2c55e2795640ca6bef02b1b17d6ecf3c4fa76`
**Pinned `vendor/bonsplit` submodule commit:** `48643102d6b68400069429bd43c15d7bda2b00a1`

### Summary

Two deliverables, bundled at the requester's explicit instruction. First, the left and right sidebars become **dockable spaces**: the tool panels they host can be reordered, split into two stacked slots inside one sidebar, and moved between the two sidebars, with the arrangement persisted as part of the saved layout. Second, a fifth **quad split** button is appended to the pane tab-bar split-button row.

### Request, paraphrased

The requester's message, condensed. No screenshot content is reproduced here, and no work item below relies on an image.

> I made a previous pass at building a dockable system and I've changed my mind on exactly how I want this to work. I'm fine keeping the left and right bars segregated as a different kind of space, but I want to be able to move the items and to split them horizontally. I should be able to drag the Files tab down toward the bottom of that area and have it snap into a dockable space where Files is on the bottom and Find/Vault on the top. I need this because I'm going to add several new things to this area, and I likely want to be able to put any of these tabs on the right into the bottom half of the left side. I want these customizations saved as part of the layout wherever layouts are saved. One additional simple feature: I want a 5th button added — a quad splitter. Vertical, then horizontal, then split quad at the end.

Two consequences of that wording are load-bearing and are honored throughout:

- "Keeping the left and right bars segregated as a different kind of space" is an explicit **withdrawal** of the earlier "all UI placeable anywhere" escalation. Sidebar tools are never placed on the freeform canvas by this work.
- "I'm going to add several new things to this area" is a forward-looking capacity requirement. It is why the slot cap below is a named constant with non-destructive restore rather than a hard structural limit (see §5).

### Definitions

Used precisely throughout; the overloading of "dock" in this codebase is a real hazard.

- **Rail** — the left or right edge-anchored sidebar, considered as a container. Synonymous with **sidebar dock space**. Never used for the pre-existing right-sidebar `.dock` mode.
- **The Dock** — always written with a capital D and the definite article. The pre-existing `RightSidebarMode.dock` feature: a `DockSplitStore`-backed Bonsplit container of terminals and browsers, shown as one mode of the right sidebar behind the `rightSidebar.beta.dock.enabled` flag. It is untouched by this PRD except for gaining the quad button.
- **Slot** — one Bonsplit `PaneID` inside a rail's `BonsplitController`. A rail has 1 or 2 slots. In persistence a slot is one `SessionPaneLayoutSnapshot`.
- **Tool panel** — a `Panel` hosted in a rail slot: a `RightSidebarToolPanel` (Files, Find, Vault) or the new `WorkspaceSelectorPanel`.
- **`**Landing:**`** — each work item states its landing target twice on purpose: once as a standalone line for structural checks, and once as the first Implementation Details bullet, because the PRD→phases extractor preserves `implementation_details` but has no field for a fifth block.

### Orientation inversion — the single most likely implementation error

`SplitOrientation` (`vendor/bonsplit/Sources/Bonsplit/Public/Types/SplitOrientation.swift:4`) has exactly two cases, and the names are the opposite of the visual result:

- `.horizontal` = **side by side** (left | right)
- `.vertical` = **stacked** (top / bottom)

The request's "split them horizontally" means a *horizontal divider* producing top and bottom, which is Bonsplit **`.vertical`**. Every work item restates this at its use site.

### Drop-zone geometry — corrected, and it constrains the interaction

`UnifiedPaneDropDelegate.zoneForLocation(_:)` (`vendor/bonsplit/Sources/Bonsplit/Internal/Views/PaneContainerView.swift:335-352`) is a `private func` computing:

```
edgeRatio = 0.25
horizontalEdge = max(80, width  * 0.25)
verticalEdge   = max(80, height * 0.25)
x < horizontalEdge → .left ;  x > width - horizontalEdge → .right   (checked FIRST)
y < verticalEdge   → .top  ;  y > height - verticalEdge  → .bottom
otherwise → .center
```

Two facts follow that the first draft of this PRD got wrong:

1. The zones are **edge bands of 25% (floor 80pt)**, not halves. "The bottom half" is not a drop target; the bottom `max(80, height*0.25)` is.
2. Left/right are tested **before** top/bottom, and because `horizontalEdge = max(80, width*0.25)` is a flat 80pt for any width ≤ 320, the two side bands consume 160pt of *any* rail narrower than that. The two rails have different width floors and must be reasoned about separately:
   - **Right rail:** floor is `minimumWidth = 276.0` (`Packages/macOS/CmuxSettings/Sources/CmuxSettings/Policies/RightSidebarWidthSettings.swift:24`). The side bands take **160 of 276pt (58%)**; top/bottom are reachable only in `x ∈ [80, 196]`.
   - **Left rail:** floor is `SessionPersistencePolicy.resolvedMinimumSidebarWidth(defaults:)` (`Sources/SessionPersistence.swift:43-48`), defaulting to `defaultMinimumSidebarWidth = 240` (`:23`) but **user-settable anywhere in `sidebarMinimumWidthRange = 120...260`** (`:25`, via the `sidebarMinimumWidth` UserDefaults key at `:18`). At the default 240pt the bands take **160 of 240pt (67%)**, leaving `x ∈ [80, 160]`. At any configured left-rail width **≤ 160pt — which is inside the supported range —** the two 80pt bands tile the entire rail and the top/bottom bands become **completely unreachable**: the drag path to split does not exist at all.
   
   This is why the non-drag command in work item 1.2 is required rather than a convenience: for a narrow left rail it is the *only* way to split.

`BonsplitConfiguration` exposes no drop-zone knob (`acceptedDropZone`, `PaneContainerView.swift:631-646`, gates *file* drops only), and the zone set is not host-configurable. §1 forbids modifying `vendor/bonsplit`. Therefore this PRD delivers the split via the drop path **plus a deterministic non-drag affordance** (work item 1.2), and records the narrow-band ergonomics as accepted debt with a named upstream follow-up (§5).

### Load-bearing facts about today's code

- The tab row showing **Find / Vault / Files** is the **right** sidebar: `RightSidebarPanelView.modeBar` (`Sources/RightSidebarPanelView.swift:216`), mounted trailing at `Sources/ContentView.swift:1894`. This is grounded purely in code: it is the only Find/Vault/Files tab row in the repository. "Vault" is the display label of `RightSidebarMode.sessions` (`Sources/RightSidebarPanelView.swift:28`); no type is named `Vault`.
- The **left** sidebar (`VerticalTabsSidebar`, `Sources/ContentView.swift:10386`) is the workspace list and has **no tab row**.
- The right sidebar renders one mode at a time: `VStack { modeBar; contentForMode }` (`Sources/RightSidebarPanelView.swift:177-181`), switched on `fileExplorerState.mode` (`Sources/RightSidebarPanelView.swift:380`).
- `RightSidebarToolPanel` (`Sources/RightSidebarToolPanel.swift:6`, init at `:22`) already wraps a `RightSidebarMode` as a Bonsplit `Panel` with `panelType = .rightSidebarTool`, used today by "Open as pane". `RightSidebarMode.paneModes` is exactly `[.files, .find, .sessions]` (`Sources/RightSidebarPanelView.swift:59`).
- `DockSplitStore` (`Sources/DockSplitStore.swift:14`) proves a Bonsplit container can live inside the right sidebar with cross-container drops and session persistence.
- `SessionSplitContainerSnapshot` (`Sources/SessionSplitContainerSnapshot.swift:8`) documents itself as "Persisted state shared by every Bonsplit-backed session container"; `SessionWindowSnapshot.dock` (`Sources/SessionPersistence.swift:1876`) is the additive `Optional … = nil` precedent.
- The split-button row is Bonsplit's: `SplitActionButton.defaults` = 4 entries (`vendor/bonsplit/Sources/Bonsplit/Public/BonsplitConfiguration.swift:385-390`); cmux keeps its own parallel list at `Sources/CmuxConfig.swift:943-948` with a fallback at `:2093-2098`.
- **Lane arithmetic.** `TabBarStyling.splitButtonsBackdropWidth(buttonCount:)` gives `6 + 8 + n*22 + (n-1)*4`: four buttons = **114pt**, five = **140pt**. The `maximumSplitButtonLaneWidthFraction = 0.25` value is **not a cap** — `maximumSplitButtonLaneWidth` is `max(fractionLimit, trailingWhitespaceBeforeSplitButtonLane, minimumVisibleSplitButtonLaneWidth(buttonCount:))` (`vendor/bonsplit/Sources/Bonsplit/Internal/Views/TabBarView.swift:308-316`), and `minimumVisibleSplitButtonLaneWidth` = `splitButtonsBackdropWidth(min(count, minimumFullyVisibleSplitButtonCount))` with `minimumFullyVisibleSplitButtonCount = 5` (`:148`, `:167-171`). So for any count ≤ 5 the lane is **guaranteed fully visible at any width** and never clips. An earlier draft of this PRD claimed a "69pt budget" that the four existing buttons already overflowed; that was a misreading of the `max(...)` and is false. The real consideration is ergonomic, not overflow: a five-button lane occupies 140pt of a 240–276pt rail (51–58%), crowding the tab strip. That is why a rail suppresses the lane **unconditionally**, which in turn is why the rail lane composition is invariant to the host button count and the quad button creates **no dependency** on the rail work.
- `vendor/bonsplit` is a submodule owned by `manaflow-ai` (`.gitmodules`); this fork cannot push to it.

### What the previous pass did, and what changed

The prior attempt is `origin/mission/canvas-dockable-refactor-20260725-170934` (tip `17d8a5cde2`, 68 files, +6304/−228), duplicated with unrelated commits on the local-only `feature/failedDock` (tip `63ef054955`, byte-identical dock code). It is **not merged**; `main` has zero fork-only commits.

It added `Packages/macOS/CmuxDockable` (`Dockable`, `DockableKind`, `DockableRegistry`, `DockableSnapshot`, `PortalHostable`), moved canvas panes onto it, and added a `LeftWorkspaceSelectorPanel` so the workspace selector could be placed **on the canvas**. Its own follow-up `docs/cmux-all-ui-dockable.prd.md` records the dogfood verdict: canvas panel kinds became dockable but the fixed rails still could not be placed, and the ask escalated to "all UI dockable". The current request reduces that scope: the rails stay segregated, and docking happens *inside* them. `CmuxDockable` is therefore not resurrected (§5).

## 1. Objectives & Constraints

### Objectives

- A rail can be split by a horizontal divider into two stacked slots, both by dragging a tool panel tab onto the rail's top or bottom drop band and by a deterministic non-drag command.
- Tool panel tabs can be reordered within a slot, moved between slots of one rail, and moved between the left and right rails.
- The rails remain distinct, edge-anchored spaces; no sidebar tool is placed on the canvas.
- The arrangement (which panels, which rail, which slot, order, divider ratio, per-slot selection) survives quit and relaunch and is carried by named saved layouts.
- A fifth "Split Quad" button is appended to the pane tab-bar split-button row, producing a 2×2 pane grid, reachable from every entrypoint that can already split.
- A user who never rearranges anything sees no change: a one-slot rail keeps today's chrome.

### Constraints

- **No `vendor/bonsplit` modification.** The submodule is owned by `manaflow-ai` and this fork cannot push to it. The quad button uses the existing extension point `SplitActionButton.Action.custom(String)` (`vendor/bonsplit/Sources/Bonsplit/Public/BonsplitConfiguration.swift:227`) dispatched via `BonsplitController.requestCustomAction(_:inPane:)` (`:259`, called from `vendor/bonsplit/Sources/Bonsplit/Internal/Views/TabBarView.swift:1687-1688`). The pinned submodule SHA must not change.
- **Never bump `SessionSnapshotSchema.currentVersion`** (`Sources/SessionPersistence.swift:14`, currently `1`). The load gate is exact equality (`Packages/macOS/CmuxWorkspaces/Sources/CmuxWorkspaces/Session/SessionSnapshotRepository.swift:60`); a mismatch discards the entire session file.
- **Do not add a third case to `SessionWorkspaceLayoutSnapshot`** (`Sources/SessionPersistence.swift:1732`); its `init(from:)` throws on any `type` other than `pane`/`split` (`:1750-1752`).
- **Snapshot boundary for list subtrees.** Below a `LazyVStack`/`LazyHStack`/`List`/`ForEach` row boundary, no view may hold an `ObservableObject`/`@Observable` store reference. Reference pattern: `SessionSearchFn`, `IndexSectionActions`, `SectionGapActions` in `Sources/SessionIndexView.swift`. Note `scripts/check-sidebar-lazy-layout.py` only scans five hardcoded files and **cannot** see new files, so compliance for new code is verified by explicit `rg` assertions, not by that guard.
- **No state mutation inside view-body computations.**
- New types go in new files; `Sources/ContentView.swift` is named in `skills/cmux-architecture/SKILL.md` as the pattern the one-type-per-file rule exists to stop.
- `VerticalTabsSidebar` is `Equatable` with a hand-written `==` (`Sources/ContentView.swift:10393-10398`) applied via `.equatable()`; added stored properties must update `==`.
- New `cmuxTests/*.swift` files need all four pbxproj entries. An unwired test reports "Executed 0 tests" and `-only-testing:` still exits 0, so **every** work item creating a test file verifies wiring with `./scripts/lint-pbxproj-test-wiring.sh`.
- User-facing strings use `String(localized:defaultValue:)` with keys in `Resources/Localizable.xcstrings`. Required bar: `en` + `ja`, with `state == "translated"` and a `ja` value **different from** `en` (the catalog contains keys whose `ar`/`bs`/`da` values are verbatim English at `state: needs_review`; that pattern does not count as localization). Locale bookkeeping: the catalog has 20 locales; `cmux.xcodeproj/project.pbxproj` `knownRegions` has 19 entries = **18 locales + Base**, missing `km` and `uk`.
- Rollout uses the `RightSidebarBetaFeatureSettings` `UserDefaults` beta-toggle pattern (`Sources/App/WorkspaceRuntimeSettings.swift:481`), not a PostHog flag (`scripts/lint-feature-flags.py` demands a `-release`/`-experiment`/`-permission` suffix, owner, `reviewBy`, and a single evaluation site).
- **Host/target macOS asymmetry.** The dev host is macOS 26.2 with Python 3.14.6; the product supports macOS 15. `CLAUDE.md` records that Foundation/SwiftUI/AttributeGraph semantics change silently across macOS majors and that every maintainer machine sitting on the fixed-behavior side is how issue #4529 hid. Layout-sensitive acceptance in this PRD must be re-checked on macOS 15 before the flag default is flipped.
- Regression tests follow the two-commit policy: failing test first (CI red), then the fix (CI green).

## 1.5 Required Toolchain

| Tool | Min Version | Install Command | Verify Command |
|------|-------------|-----------------|----------------|
| macOS (build host) | 15.0 | n/a | `sw_vers -productVersion` |
| Xcode | 16.0 | `xcodes install` / Mac App Store | `xcodebuild -version` |
| Python | 3.11 | preinstalled on macOS 15+ | `python3 --version` |
| git | 2.39 | `brew install git` | `git --version` |
| GhosttyKit.xcframework | matches the `ghostty` submodule SHA | `./scripts/ensure-ghosttykit.sh` | `xcodebuild -project cmux.xcodeproj -list` |

### Bootstrap gate — a hard precondition for every Verification Commands block

This worktree has **no** `GhosttyKit.xcframework`, and without it every `xcodebuild` invocation fails with exit 74 (`local binary target 'GhosttyKit' … does not contain a binary artifact`). `find` exits 0 when it matches nothing, so a `test -d … || find …` probe is useless; the real signal is whether `xcodebuild -list` resolves the package graph.

Run once per worktree before any other verification, and re-run if it ever fails:

```bash
set -euo pipefail
git submodule update --init --recursive
./scripts/ensure-ghosttykit.sh
xcodebuild -project cmux.xcodeproj -list >/dev/null
```

Every Verification Commands block below opens with `xcodebuild -project cmux.xcodeproj -list >/dev/null` so a missing bootstrap fails loudly instead of being misread as a code defect.

### How build settings are passed

Host `zig` is 0.16.0 while `ghostty/build.zig.zon` pins `.minimum_zig_version = "0.15.2"`, so zig steps must be skipped. `scripts/test-unit.sh` is `exec xcodebuild -project … -scheme cmux-unit … "$@"` and does **not** read or forward `CMUX_SKIP_ZIG_BUILD` from the environment — `scripts/reload.sh:731-734` exists precisely because env inheritance into run-script phases is not reliable. Therefore `CMUX_SKIP_ZIG_BUILD=1` is passed as an **xcodebuild build setting argument**, exactly as CI does (`.github/workflows/ci.yml:601`):

```bash
./scripts/test-unit.sh -only-testing:cmuxTests/<Suite> CMUX_SKIP_ZIG_BUILD=1 test
```

Passing any argument suppresses `test-unit.sh`'s implicit `test` action, so `test` is always supplied explicitly. Tests run on the **`cmux-unit`** scheme, never `cmux`.

## 2. Execution Phases

## Phase 1: Foundations

**Purpose:** This phase must come first because every later phase consumes something built here — the rollout flag, the rail container substrate, and the split behavior. Its four work items are **deliberately not a chain among themselves**: 1.1/1.2 (rail substrate) and 1.3/1.4 (quad split) are functionally independent. The reason no dependency exists is that a rail suppresses the split-button lane **unconditionally** (`appearance.showSplitButtons = false`, work item 1.1), so rail lane composition is invariant to how many buttons the host list contains, and separately `newTerminal`/`newBrowser` would create panel types that 1.2's placement matrix forbids in a rail. They are grouped in one phase rather than split into two sequential phases precisely because the spec forbids phases that could run in either order. Per-item `**Dependencies:**` lines state the real intra-phase ordering.

### 1.1 Rail dock store substrate and rollout flag

**Dependencies:** none

**Landing:** fork-only

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
      static let maxSlotsPerRail = 2
      static func makeConfiguration() -> BonsplitConfiguration
  }
  ```
  Structurally modeled on `DockSplitStore` (`Sources/DockSplitStore.swift:14`) but far smaller: tool panels only, no config-file seeding, no trust prompt, no remote-browser plumbing.
- `makeConfiguration()` sets: `allowSplits = true`, `allowTabReordering = true`, `allowCrossPaneTabMove = true`, `allowCloseLastPane = false`, `autoCloseEmptyPanes = true`, `tabBarVisibility = .multipleTabs` (`showsTabBar(tabCount:)` returns `tabCount >= 2`, `vendor/bonsplit/Sources/Bonsplit/Public/BonsplitConfiguration.swift:35-42`), and **`appearance.showSplitButtons = false`**. The lane is suppressed **unconditionally** because (a) at 140pt for five buttons it occupies 51–58% of a 240–276pt rail and crowds the tab strip (it does not clip — see the corrected lane arithmetic in §0), and (b) `newTerminal`/`newBrowser` would create terminal and browser panels in a rail, which work item 1.2's placement matrix forbids. Set `appearance.tabBarHeight = RightSidebarChromeMetrics.titlebarHeight` (`Sources/WindowChromeMetrics.swift:35`; the enum is declared at `:34`) so a rail tab bar matches today's mode-bar height.
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
- AC-1.1.b: `makeConfiguration()` returns `tabBarVisibility == .multipleTabs`, `allowCloseLastPane == false`, and `appearance.showSplitButtons == false` → a one-slot rail shows no tab bar, a rail cannot reach zero slots, and no terminal/browser creation buttons appear in a rail.
- AC-1.1.c: `./scripts/test-unit.sh -only-testing:cmuxTests/SidebarDockStoreTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.
- AC-1.1.d: `RightSidebarBetaFeatureSettings.sidebarDockEnabledKey == "sidebar.beta.dock.enabled"`, `defaultSidebarDockEnabled == false`, and `isSidebarDockEnabled` on an empty `UserDefaults` returns `false` → the gate exists in this phase and defaults off.
- AC-1.1.e: No new file under `Sources/Sidebar/` holds a store reference in a row-level view → `rg` finds no `@ObservedObject`/`@EnvironmentObject`/`@StateObject`/`@Bindable` in the new files.
- AC-1.1.f: The registry's own injection site uses `.environment(` naming the registry value, and no `.environmentObject(` call anywhere names a registry → the `@Observable` propagation mechanism is used for this type. A bare `grep '.environment('` would be vacuous: `Sources/AppDelegate.swift` already contains one such call on `PRD_BASE_SHA`, so the check must name the registry.

**Acceptance Tests**
- Test-1.1.a: Unit — `cmuxTests/SidebarDockStoreTests.swift` (NEW) `edgeEnumHasLeftAndRight()`.
- Test-1.1.b: Unit — `configurationSuppressesLaneAndHidesSingleTabBar()` asserts the three configuration values plus `showsTabBar(tabCount: 1) == false` and `showsTabBar(tabCount: 2) == true`.
- Test-1.1.c: The same suite is the executable gate for AC-1.1.c.
- Test-1.1.d: Unit — `sidebarDockFlagKeyDefaultsOffWhenAbsent()`.
- Test-1.1.e: Regression — `noStoreReferenceInRowViews()` greps the new files.
- Test-1.1.f: Regression — `registryUsesObservableEnvironmentInjection()`.

**Verification Commands**
```bash
set -euo pipefail
xcodebuild -project cmux.xcodeproj -list >/dev/null
test -f Sources/Sidebar/SidebarDockEdge.swift
test -f Sources/Sidebar/SidebarDockStore.swift
test -f Sources/Sidebar/SidebarDockStoreRegistry.swift
grep -qF 'showSplitButtons = false' Sources/Sidebar/SidebarDockStore.swift
grep -qF 'tabBarVisibility' Sources/Sidebar/SidebarDockStore.swift
grep -qF 'allowCloseLastPane' Sources/Sidebar/SidebarDockStore.swift
grep -qF 'sidebar.beta.dock.enabled' Sources/App/WorkspaceRuntimeSettings.swift
grep -qF 'defaultSidebarDockEnabled = false' Sources/App/WorkspaceRuntimeSettings.swift
rg -q '\.environment\([^)]*[Rr]egistry' Sources/AppDelegate.swift
! rg -q 'environmentObject\([^)]*[Rr]egistry' Sources/AppDelegate.swift
! rg -n '@(ObservedObject|EnvironmentObject|StateObject|Bindable)' Sources/Sidebar/SidebarDockStore.swift Sources/Sidebar/SidebarDockStoreRegistry.swift
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/SidebarDockStoreTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 1.2 Rail view, split behavior, and the non-drag split command

**Dependencies:** 1.1

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Add `Sources/Sidebar/SidebarDockPanelView.swift` (NEW), modeled on `DockPanelView` (`Sources/DockPanelView.swift:11`) including its `visibilityHostId` pattern and appearance-refresh observers. Signature: `init(store: SidebarDockStore, isRailVisible: Bool, windowAppearance: WindowAppearanceSnapshot)`.
- **Splitting a rail.** A drop on the rail's top or bottom band calls `BonsplitController.splitPane(_:orientation:movingTab:insertFirst:)` (`vendor/bonsplit/Sources/Bonsplit/Public/BonsplitController.swift:653`) with `orientation: .vertical` — stacked, top/bottom, per §0 — and `insertFirst: true` for the top band, `false` for the bottom.
- **Refusing side-by-side and third slots.** Implement `splitTabBar(_:shouldSplitPane:orientation:)` (`vendor/bonsplit/Sources/Bonsplit/Public/BonsplitDelegate.swift:38`, default `true` at `:104`) returning `false` when `orientation == .horizontal` or when `bonsplitController.allPaneIds.count >= SidebarDockStore.maxSlotsPerRail`. All three `splitPane` overloads consult this veto (`BonsplitController.swift:518`, `:589`, `:671`), so no submodule change is needed.
  - The veto is **veto-only and receives no tab identity**, so it cannot substitute a `moveTab`. A drop on the bottom band of an already-split rail is therefore **refused and the tab stays put** — it does not relocate into the existing bottom slot. Moving a tab into an existing slot is done by dropping on that slot's `.center` zone or its tab bar.
- **Deterministic non-drag affordance (required, not optional).** Per §0, the top/bottom bands are reachable only in `x ∈ [80, 196]` at a 276pt right rail, `x ∈ [80, 160]` at a default 240pt left rail, and **not at all** at a left rail configured ≤ 160pt (inside the supported `120...260` range). Drag is therefore not a dependable path and for a narrow left rail not a path at all. Add a tab context-menu item and a command-palette command, both localized, that split the rail and move the invoked tab to the new slot: `SidebarDockStore.splitRail(movingTab:toEdgeSlot:)` where `toEdgeSlot` is `.top`/`.bottom`. This is the path the acceptance tests drive, and the one documented as primary.
- Add `Sources/Sidebar/SidebarDockPlacementMatrix.swift` (NEW): a checked-in table declaring, per `PanelType`, whether it may occupy a rail slot. Rows: `rightSidebarTool` → allowed; `workspaceSelector` → allowed; every other `PanelType` case → refused. This adopts the one genuinely good artifact of the prior pass (`DockableSupportMatrix`) without its ambient-global machinery.
- Divider position defaults to `0.5`, clamped by `configuration.dividerPositionRange`, adjustable via `setDividerPosition(_:forSplit:fromExternal:)` (`BonsplitController.swift:1016`). Emptying a slot collapses the rail through `autoCloseEmptyPanes`.
- Localize the two new affordances with `en` + `ja` keys `sidebarDock.splitRail.top` and `sidebarDock.splitRail.bottom`.
- Failure modes: a split request for a disallowed `PanelType` is refused with a logged reason; a request on a rail already at `maxSlotsPerRail` is refused; a drop of a pane's only tab onto its own `.center` zone is a no-op (`PaneContainerView.swift:449-458`).

**Acceptance Criteria**
- AC-1.2.a: `splitRail(movingTab:toEdgeSlot: .bottom)` on a one-slot rail yields 2 slots with a `.vertical` split and the moved tab alone in the second slot → the requested arrangement is reachable deterministically.
- AC-1.2.b: `toEdgeSlot: .top` puts the moved tab in the **first** slot (`insertFirst == true`) → both halves are targetable.
- AC-1.2.c: `shouldSplitPane` returns `false` for `.horizontal` and for any rail already at `maxSlotsPerRail`, and a left-band drop leaves the tree unchanged → no side-by-side split and no third slot is ever created.
- AC-1.2.d: `./scripts/test-unit.sh -only-testing:cmuxTests/SidebarDockSplitTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.
- AC-1.2.e: The placement matrix refuses every `PanelType` except `rightSidebarTool` and `workspaceSelector` → no terminal, browser, markdown, or file-preview panel can occupy a rail slot.
- AC-1.2.f: Emptying one slot collapses the rail to 1 slot → `allPaneIds.count == 1`.
- AC-1.2.g: Both new affordance strings have `en` and `ja` entries with `state == "translated"` and differing values → the new UI text is genuinely localized.

**Acceptance Tests**
- Test-1.2.a: Integration — `cmuxTests/SidebarDockSplitTests.swift` (NEW) `splitRailToBottomPutsTabInSecondSlot()`.
- Test-1.2.b: Integration — `splitRailToTopInsertsFirst()`.
- Test-1.2.c: Regression — `railRefusesHorizontalAndThirdSlot()` calls the veto directly and then attempts a left-band drop.
- Test-1.2.d: The same suite is the executable gate for AC-1.2.d.
- Test-1.2.e: Regression — `placementMatrixRefusesNonToolPanels()` iterates every `PanelType` case.
- Test-1.2.f: Integration — `emptyingSlotCollapsesRail()`.
- Test-1.2.g: Unit — `splitRailStringsAreLocalized()` parses the xcstrings catalog.

**Verification Commands**
```bash
set -euo pipefail
xcodebuild -project cmux.xcodeproj -list >/dev/null
test -f Sources/Sidebar/SidebarDockPanelView.swift
test -f Sources/Sidebar/SidebarDockPlacementMatrix.swift
grep -qF 'shouldSplitPane' Sources/Sidebar/SidebarDockStore.swift
grep -qF 'orientation: .vertical' Sources/Sidebar/SidebarDockStore.swift
grep -qF 'maxSlotsPerRail' Sources/Sidebar/SidebarDockStore.swift
! rg -n 'orientation: \.horizontal' Sources/Sidebar/
python3 - <<'PY'
import json,sys
d=json.load(open("Resources/Localizable.xcstrings"))["strings"]
bad=[]
for k in ["sidebarDock.splitRail.top","sidebarDock.splitRail.bottom"]:
    loc=d.get(k,{}).get("localizations",{})
    en=loc.get("en",{}).get("stringUnit",{}); ja=loc.get("ja",{}).get("stringUnit",{})
    if ja.get("state")!="translated" or not ja.get("value") or ja.get("value")==en.get("value"):
        bad.append(k)
if bad: sys.exit("not genuinely localized: %s" % bad)
PY
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/SidebarDockSplitTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 1.3 Quad split shared action

**Dependencies:** none

**Landing:** fork-only

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

**Acceptance Tests**
- Test-1.3.a: Unit — `cmuxTests/QuadSplitActionTests.swift` (NEW) `performIsCallableOnWorkspace()`.
- Test-1.3.b: Integration — `quadSplitProducesFourPanes()`.
- Test-1.3.c: The same suite is the executable gate for AC-1.3.c.
- Test-1.3.d: Integration — `everyQuadPaneHasExactlyOneTerminal()`.
- Test-1.3.e: Regression — `quadSplitRespectsAllowSplitsFalse()`.
- Test-1.3.f: Regression — `quadRecipeShapeIsPinned()` greps the source for the two counts.
- Test-1.3.g: Integration — `quadSplitProducesTrueTwoByTwoTopology()` walks `bonsplitController.treeSnapshot()` asserting root orientation `horizontal` with both children `vertical` splits of two leaves, and separately asserts `focusedPaneId != paneId` immediately after the first split.

**Verification Commands**
```bash
set -euo pipefail
xcodebuild -project cmux.xcodeproj -list >/dev/null
test -f Sources/QuadSplitAction.swift
grep -qF 'static func perform(inPane' Sources/QuadSplitAction.swift
test "$(rg -c 'splitPaneWithNewTerminal' Sources/QuadSplitAction.swift)" = "3"
! rg -n 'isProgrammaticSplit' Sources/QuadSplitAction.swift
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/QuadSplitActionTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 1.4 Quad split button and entrypoints

**Dependencies:** 1.3

**Landing:** fork-only

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

**Acceptance Tests**
- Test-1.4.a: Unit — `cmuxTests/QuadSplitButtonTests.swift` (NEW) `defaultsEndWithQuadAndMapToCustomAction()`.
- Test-1.4.b: Regression — `bonsplitSubmoduleUnchanged()` asserts the pinned SHA and a clean submodule worktree.
- Test-1.4.c: The same suite is the executable gate for AC-1.4.c.
- Test-1.4.d: Unit — `everyQuadDispatchSiteHandlesTheCase()` asserts one behavior per site: a non-empty palette title and keyword set; `bonsplitAction == .custom("cmux.splitQuad")`; `defaultIcon == "square.split.2x2"`; `init?(configID: "cmux.splitQuad") != nil`; that `executeSurfaceTabBarCommandButton` with the quad identifier performs a quad split; and that `executeConfiguredCmuxAction` with the built-in quad action performs a quad split rather than returning without effect.
- Test-1.4.e: Integration — `dockFocusedQuadShortcutSplitsDock()`.
- Test-1.4.f: Regression — `allFiveEntrypointsShareOneActionPath()`.
- Test-1.4.g: Unit — `dockAppearanceIncludesQuadButton()`.

**Verification Commands**
```bash
set -euo pipefail
xcodebuild -project cmux.xcodeproj -list >/dev/null
grep -qF 'cmux.splitQuad' Sources/CmuxSurfaceTabBarBuiltInAction.swift
grep -qF 'square.split.2x2' Sources/CmuxSurfaceTabBarBuiltInAction.swift
grep -qF 'splitQuad' Sources/CmuxConfig.swift
grep -qF 'splitQuad' Sources/Workspace.swift
grep -qF 'splitQuad' Sources/DockSplitStore+Appearance.swift
grep -qF 'splitQuad' Sources/KeyboardShortcutSettings.swift
grep -qF 'splitQuad' Sources/cmuxApp.swift
# AppDelegate has two independent sites; a bare file-level grep would pass on the
# shortcut routing alone and miss the executeConfiguredCmuxAction switch entirely.
test "$(rg -c 'splitQuad' Sources/AppDelegate.swift)" -ge 2
python3 - <<'PY'
import re,sys
src=open("Sources/AppDelegate.swift").read().splitlines()
start=next(i for i,l in enumerate(src) if 'case .builtIn(let builtIn):' in l)
window="\n".join(src[start:start+140])
if '.splitQuad' not in window:
    sys.exit("executeConfiguredCmuxAction builtIn switch does not handle .splitQuad")
PY
grep -qF 'splitQuad' Sources/GhosttyTerminalView.swift
grep -qF 'splitQuad' Sources/TerminalController.swift
grep -qF 'splitQuad' Sources/ContentView+RightSidebarCommandPalette.swift
grep -qF 'splitQuad' Sources/ContentView+AgentChatCommandPalette.swift
grep -qF 'splitQuad' Packages/macOS/CmuxSettings/Sources/CmuxSettings/Values/ShortcutAction.swift
grep -qF 'splitQuad' Packages/macOS/CmuxSettings/Sources/CmuxSettings/Values/ShortcutAction+Defaults.swift
grep -qF 'splitQuad' web/data/cmux.schema.json
test "$(git rev-parse HEAD:vendor/bonsplit)" = "48643102d6b68400069429bd43c15d7bda2b00a1"
git -C vendor/bonsplit diff --quiet
git -C vendor/bonsplit diff --cached --quiet
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/QuadSplitButtonTests CMUX_SKIP_ZIG_BUILD=1 test
```

## Phase 2: Mount Both Rails

**Purpose:** This phase cannot start until Phase 1 exists, because its two mounting items (2.1 right rail, 2.3 left rail) both mount `SidebarDockPanelView` on a `SidebarDockStore` and read the rollout flag — all three delivered by 1.1 and 1.2. Its third item, 2.2, is the `WorkspaceSelectorPanel` adapter: it depends only on 1.1 and could technically have sat in Phase 1, but it lives here because its sole consumer is 2.3 and grouping the adapter with the mount that needs it keeps the left-rail work reviewable as one unit. The phase precedes Phase 3 because a tab cannot be moved between rails, nor a two-rail arrangement serialized, until both rails are dock spaces. Within the phase, 2.1 and 2.3 are independent of each other, and 2.3 depends on 2.2.

### 2.1 Right rail mounted on the dock store

**Dependencies:** 1.1, 1.2

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Replace `RightSidebarPanelView`'s `VStack { modeBar; contentForMode }` (`Sources/RightSidebarPanelView.swift:177-181`) with `SidebarDockPanelView` driven by the window's `SidebarDockStore(edge: .right)`, **behind `RightSidebarBetaFeatureSettings.isSidebarDockEnabled`**. With the flag off, the legacy path renders unchanged.
- **Tab set, stated per mode.** `RightSidebarMode` has six cases (`Sources/RightSidebarPanelView.swift:17-22`) but only three have a `Panel` adapter (`paneModes = [.files, .find, .sessions]`, `:59`). Dispositions:
  - `.files`, `.find`, `.sessions` → included, each backed by `RightSidebarToolPanel(workspace:mode:)` (`Sources/RightSidebarToolPanel.swift:22`).
  - `.feed` → **excluded** from the rail tab set; it keeps rendering through the legacy `contentForMode` path when selected. No `FeedToolPanel` is created by this PRD.
  - `.dock` → **excluded.** The Dock is itself a `BonsplitController`; nesting one inside a rail slot's Bonsplit pane is out of scope.
  - `.customSidebar` → **excluded**; it is already filtered out of `availableModes()` and renders `EmptyView()`.
  A fresh right rail therefore has exactly three tabs: Files, Find, Vault.
- **Source-of-truth contract for selection (the load-bearing rule).** `SidebarDockStore` is the **sole source of truth**. `FileExplorerState.mode` becomes a *derived mirror* defined as *the mode of the selected tab in the focused slot*. It is written exactly once, from `splitTabBar(_:didSelectTab:inPane:)` and `splitTabBar(_:didFocusPane:)` — never from a view body, per §1. `mode`'s public setter is replaced by `SidebarDockStore.focusTab(for:)`, and all existing setters are rewritten to call it: tab click (`Sources/RightSidebarPanelView.swift:238-245`), `keyDown` (`:500-508`), command palette (`Sources/ContentView+RightSidebarCommandPalette.swift`), CLI/socket (`Sources/RightSidebarRemoteCommand.swift`, `Sources/AppDelegate.swift:6644`/`:6771`/`:6917`), and focus memory (`Sources/MainWindowFocusController.swift:147`/`:157`). When two slots are visible, `mode` names only the focused slot's selection — it is explicitly incapable of describing both, which is why the store, not `mode`, is persisted. On restore the snapshot wins and `rightSidebar.mode` is overwritten from it.
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
- AC-2.1.d: `FileExplorerState.mode` changes when focus moves between two slots with different selections, and is written only from the two delegate callbacks → the derived-mirror contract holds and no view body writes it.
- AC-2.1.e: `RightSidebar` and `RightSidebarModeBar` resolve with the flag on → the container identifiers survive.
- AC-2.1.f: Every UI test asserting `RightSidebarModeButton.*` or the mode-bar height is conditionalized on the flag → the known identifier loss does not silently red CI.
- AC-2.1.g: Any new header string has `en` + `ja` with `state == "translated"` and differing values.

**Acceptance Tests**
- Test-2.1.a: Regression — `cmuxTests/RightSidebarDockMountTests.swift` (NEW) `flagOffKeepsLegacyModeBar()`.
- Test-2.1.b: Integration — `freshRightRailHasExactlyThreeToolTabs()`.
- Test-2.1.c: The same suite is the executable gate for AC-2.1.c.
- Test-2.1.d: Integration — `modeMirrorsFocusedSlotSelection()` plus a grep asserting no `mode =` write outside the two callbacks.
- Test-2.1.e: Integration — `containerAccessibilityIdentifiersSurvive()`.
- Test-2.1.f: Regression — `modeButtonUITestsAreFlagConditionalized()` greps the three conditionalized UI test files for the flag guard, and asserts `SettingsSidebarBetaBehaviorUITests.swift` is NOT required to carry one.
- Test-2.1.g: Unit — `rightRailHeaderStringsAreLocalized()`.

**Verification Commands**
```bash
set -euo pipefail
xcodebuild -project cmux.xcodeproj -list >/dev/null
grep -qF 'isSidebarDockEnabled' Sources/RightSidebarPanelView.swift
grep -qF 'RightSidebarChromeMetrics' Sources/Sidebar/SidebarDockPanelView.swift
for f in cmuxUITests/FeedSidebarUITests.swift cmuxUITests/RightSidebarChromeHeightUITests.swift cmuxUITests/BonsplitTabDragUITests.swift; do
  grep -qF 'isSidebarDockEnabled' "$f" || grep -qF 'sidebar.beta.dock.enabled' "$f" || { echo "not conditionalized: $f"; exit 1; }
done
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/RightSidebarDockMountTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 2.2 Workspace list as a dockable panel

**Dependencies:** 1.1

**Landing:** fork-only

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

**Acceptance Tests**
- Test-2.2.a: Unit — `cmuxTests/WorkspaceSelectorPanelTests.swift` (NEW) `panelTypeRoundTripsIncludingMixedCase()`.
- Test-2.2.b: Unit — `panelReportsTypeAndFactoryFailsClosed()`.
- Test-2.2.c: The same suite is the executable gate for AC-2.2.c.
- Test-2.2.d: Regression — the lazy-layout guard plus `noStoreInRowViewsOfNewPanel()`.
- Test-2.2.e: Regression — `guardedFunctionNamesPreserved()`.
- Test-2.2.f: Unit — `workspacesTitleIsLocalized()`.

**Verification Commands**
```bash
set -euo pipefail
xcodebuild -project cmux.xcodeproj -list >/dev/null
grep -qF 'workspaceSelector' Sources/Panels/Panel.swift
test -f Sources/Sidebar/WorkspaceSelectorPanel.swift
grep -qF 'workspaceScrollContent' Sources/ContentView.swift
grep -qF 'workspaceRows' Sources/ContentView.swift
python3 tests/test_ci_sidebar_lazy_layout_guard.py
! rg -n '@(ObservedObject|EnvironmentObject|StateObject|Bindable)' Sources/Sidebar/WorkspaceSelectorPanel.swift
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/WorkspaceSelectorPanelTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 2.3 Left rail mounted on the dock store

**Dependencies:** 2.2

**Landing:** fork-only

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

**Acceptance Tests**
- Test-2.3.a: Integration — `cmuxTests/LeftSidebarDockMountTests.swift` (NEW) `soleWorkspaceSelectorShowsNoTabBar()`.
- Test-2.3.b: Integration — `secondPanelRevealsTabBar()`.
- Test-2.3.c: The same suite is the executable gate for AC-2.3.c.
- Test-2.3.d: Regression — `leftRailGeometryFilesUnchanged()` compares against the pinned base blobs.
- Test-2.3.e: Regression — the existing `cmuxTests/SidebarTabDragPayloadProviderTests.swift` suite still passes.
- Test-2.3.f: Unit — `emptyLeftRailReseedsWorkspaceSelector()`.

**Verification Commands**
```bash
set -euo pipefail
xcodebuild -project cmux.xcodeproj -list >/dev/null
BASE=69b2c55e2795640ca6bef02b1b17d6ecf3c4fa76
git cat-file -e "$BASE" 2>/dev/null || { echo "PRD_BASE_SHA unresolvable"; exit 1; }
for f in Sources/Sidebar/SidebarState.swift Sources/Sidebar/SidebarLayoutModel.swift; do
  test "$(git hash-object "$f")" = "$(git rev-parse "$BASE:$f")" || { echo "modified: $f"; exit 1; }
done
grep -qF 'SidebarDockStore' Sources/ContentView.swift
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/LeftSidebarDockMountTests CMUX_SKIP_ZIG_BUILD=1 test
./scripts/test-unit.sh -only-testing:cmuxTests/SidebarTabDragPayloadProviderTests CMUX_SKIP_ZIG_BUILD=1 test
```

## Phase 3: Cross-Rail Moves and Persistence

**Purpose:** This phase cannot start until Phase 2 has mounted both rails, because a tab cannot move between rails that are not both dock spaces, and the persisted arrangement cannot be captured until there is a two-rail arrangement to capture. Cross-rail movement and persistence are one phase rather than two because the schema shape is fixed by Phase 2 (two rails, ≤2 slots each) and cross-rail movement adds no schema surface — a tool panel serialized in `leftSidebarDock` is byte-identical however it arrived. Their only coupling is 3.2's restore-time guard against a placement-matrix-disallowed panel, which is one guard, not a schema driver; the `**Dependencies:**` lines encode that ordering. The phase's third item, 3.3, carries the same arrangement into named saved layouts and depends on 3.2 because it reuses the captured shape; it is in this phase rather than a later one because "wherever layouts are saved" is a single requirement spanning two storage mechanisms and splitting them across phases would let the project be declared done with only half of it satisfied.

### 3.1 Moving a tool panel between rails

**Dependencies:** 2.1, 2.3

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Add `Sources/Sidebar/SidebarDockStore+ExternalDrop.swift` (NEW), setting `bonsplitController.onExternalTabDrop` on each rail store. Bonsplit routes a drag begun in a different controller to the receiving controller as external; this is the mechanism `DockSplitStore` uses at `Sources/DockSplitStore.swift:113-120`.
- The live panel is **moved, not copied**: remove it from the source store's `panels`/`surfaceIdToPanelId` and insert into the destination's, preserving `id` and `stableSurfaceIdentity` so session identity and focus history survive.
- A drop on the destination rail's bottom band creates the destination's second slot with `orientation: .vertical, insertFirst: false` — the arrangement the request describes.
- **The handler must route `.split` destinations through `bonsplitController.splitPane`.** `ExternalTabDropRequest.Destination` (`vendor/bonsplit/Sources/Bonsplit/Public/BonsplitController.swift:9-24`) includes `.split(targetPane:orientation:insertFirst:)`, and the zone-derived destination is handed to the host (`vendor/bonsplit/Sources/Bonsplit/Internal/Views/PaneContainerView.swift:495-497`), so a drop onto the destination rail's **left or right** band arrives as `.split(orientation: .horizontal)` for the host to act on. 1.2's `shouldSplitPane` veto is consulted only by the `splitPane` overloads (`BonsplitController.swift:518`, `:589`, `:671`), so it protects this path **only if** the handler goes through them. Implementing the split by hand here would bypass the veto and admit a side-by-side rail split via the cross-rail route.
- Declare a **new** UTType `com.cmux.sidebar-panel-tab.transfer` in `Resources/Info.plist` under `UTExportedTypeDeclarations`, conforming to `public.data`, alongside the three existing declarations (`com.splittabbar.tabtransfer`, `com.cmux.sidebar-tab-reorder`, `com.cmux.filepreview.transfer`). Reusing `com.cmux.sidebar-tab-reorder` is forbidden: it carries workspace ids and is already accepted by terminals, browsers, and file-preview panes, so reuse would make a tool tab droppable onto a terminal as a workspace.
- Enforce `SidebarDockPlacementMatrix` (1.2) on receipt.
- Failure modes: a disallowed `PanelType` is refused and the drag returns to origin; a move that would leave the left rail with no panels when the workspace selector is its only panel is refused.

**Acceptance Criteria**
- AC-3.1.a: A tab moved from the right rail to the left rail's bottom band lands in the left rail's second slot and is absent from the right rail → the requested cross-rail move works.
- AC-3.1.b: The moved panel keeps its `id` and `stableSurfaceIdentity` → it is a move, not a re-creation.
- AC-3.1.c: `./scripts/test-unit.sh -only-testing:cmuxTests/SidebarDockCrossRailTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.
- AC-3.1.d: `Resources/Info.plist` declares `com.cmux.sidebar-panel-tab.transfer` conforming to `public.data`, with 4 unique identifiers total → the new type exists and is distinct from the reorder type.
- AC-3.1.e: A placement-matrix-disallowed `PanelType` is refused on drop → no terminal or browser lands in a rail.
- AC-3.1.f: A move that would empty the left rail of its only panel is refused → the rail invariant holds.
- AC-3.1.g: A cross-rail drop whose destination is `.split(orientation: .horizontal)` is refused with the destination tree unchanged, and the handler reaches `bonsplitController.splitPane` for `.split` destinations → the 1.2 veto also governs the cross-rail path and side-by-side rail splits cannot sneak in through it.

**Acceptance Tests**
- Test-3.1.a: Integration — `cmuxTests/SidebarDockCrossRailTests.swift` (NEW) `rightRailTabMovesToLeftRailSecondSlot()`.
- Test-3.1.b: Regression — `crossRailMovePreservesPanelIdentity()`.
- Test-3.1.c: The same suite is the executable gate for AC-3.1.c.
- Test-3.1.d: Unit — `sidebarPanelTabUTTypeDeclaredAndDistinct()`.
- Test-3.1.e: Regression — `crossRailDropRefusesDisallowedPanelType()`.
- Test-3.1.f: Regression — `moveRefusedWhenItWouldEmptyLeftRail()`.
- Test-3.1.g: Regression — `externalHorizontalSplitDestinationIsRefused()` submits a `.split(orientation: .horizontal)` external destination and asserts the destination tree is unchanged.

**Verification Commands**
```bash
set -euo pipefail
xcodebuild -project cmux.xcodeproj -list >/dev/null
test -f Sources/Sidebar/SidebarDockStore+ExternalDrop.swift
grep -qF 'onExternalTabDrop' Sources/Sidebar/SidebarDockStore+ExternalDrop.swift
grep -qF 'splitPane' Sources/Sidebar/SidebarDockStore+ExternalDrop.swift
python3 - <<'PY'
import plistlib,sys
d=plistlib.load(open("Resources/Info.plist","rb"))
decls=d["UTExportedTypeDeclarations"]
ids=[t["UTTypeIdentifier"] for t in decls]
assert len(ids)==len(set(ids)), ids
target="com.cmux.sidebar-panel-tab.transfer"
assert target in ids, ids
assert target != "com.cmux.sidebar-tab-reorder"
row=next(t for t in decls if t["UTTypeIdentifier"]==target)
assert "public.data" in row.get("UTTypeConformsTo", []), row
PY
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/SidebarDockCrossRailTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 3.2 Persist and restore the arrangement in the session snapshot

**Dependencies:** 3.1

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Add two additive optional fields to `SessionWindowSnapshot` (`Sources/SessionPersistence.swift:1867`), mirroring `var dock: SessionSplitContainerSnapshot? = nil` (`:1876`):
  `var leftSidebarDock: SessionSplitContainerSnapshot? = nil` and `var rightSidebarDock: SessionSplitContainerSnapshot? = nil`.
- **Do not bump `SessionSnapshotSchema.currentVersion`** (currently `1`, `Sources/SessionPersistence.swift:14`). `Optional … = nil` is the established pattern, proven by `legacySessionWithoutDockFieldsDecodesCleanly()` in `cmuxTests/DockSessionPersistenceTests.swift`.
- Reuse `SessionSplitContainerSnapshot` (`Sources/SessionSplitContainerSnapshot.swift:8`) verbatim. The stacked split serializes as `SessionSplitLayoutSnapshot(orientation: .vertical, dividerPosition:)`; per-slot ordered tabs and selection as `SessionPaneLayoutSnapshot.panelIds`/`.selectedPanelId`. Do not add a third `SessionWorkspaceLayoutSnapshot` case.
- Add `Sources/Sidebar/SidebarDockStore+SessionSnapshot.swift` (NEW) and `Sources/Sidebar/SidebarDockStore+SessionRestore.swift` (NEW), modeled on the `DockSplitStore` equivalents, using `SessionSplitContainerLayoutCodec` (`Sources/SessionSplitContainerLayoutCodec.swift:8`): `snapshot(panelIdForTabId:)`, `pruned(_:keeping:)`, `restoreScaffold(_:)`, then `applyDividerPositions(snapshotNode:liveNode:)`.
- Wire capture into `Sources/AppDelegate.swift:4535-4547` (beside `sidebar` and `dock`) and restore at `:3568-3572` / `:8715-8732`. **Add both fields to the autosave dirty fingerprint at `Sources/AppDelegate.swift:3992-4000`**, which today hashes only left-sidebar visibility, width, and selection — without this the 8-second autosave never notices a rearrangement, which is the highest-risk silent-data-loss path in this PRD and therefore carries its own acceptance criterion.
- **Legacy migration, non-destructive.** Right-rail state lives in global `UserDefaults` today (`rightSidebar.mode`, `fileExplorer.isVisible`, `fileExplorer.width`, `Sources/FileExplorerState.swift:7-15`). On first launch with the flag on and `rightSidebarDock == nil`, seed a one-slot right rail with the three tool tabs and the selection taken from `rightSidebar.mode`. Leave every legacy key intact and unmodified so turning the flag off returns the user to their exact prior state. This PRD does **not** retire `fileExplorer.dividerPosition`: it is orthogonal, would be an ungated behavior change, and `FileExplorerState` does read it in `init` (`:54-55`) even though nothing renders it.
- **Restore is non-destructive.** A snapshot describing more slots than `maxSlotsPerRail` is restored **as-is** if it round-trips; the cap is enforced on new splits only. This deliberately avoids destroying data that a future cap raise would want (§5).
- Failure modes: a `panelId` with no decodable panel drops that tab and keeps the rest, never failing the window decode; a matrix-disallowed panel type in a rail snapshot is dropped.

**Acceptance Criteria**
- AC-3.2.a: `SessionWindowSnapshot` declares both fields as `SessionSplitContainerSnapshot?` defaulted to `nil` → the fields are additive.
- AC-3.2.b: `Sources/SessionPersistence.swift` still contains `static let currentVersion = 1` → no existing session file is invalidated, checked by content rather than by a diff.
- AC-3.2.c: `./scripts/test-unit.sh -only-testing:cmuxTests/SidebarDockPersistenceTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.
- AC-3.2.d: A session JSON with both keys absent decodes with both fields `nil` → old snapshots keep working.
- AC-3.2.e: A two-slot rail round-trips orientation, divider position, per-slot ordered `panelIds`, and `selectedPanelId` → the arrangement is fully persisted.
- AC-3.2.f: The autosave dirty fingerprint changes when a rail is rearranged → an arrangement is not silently lost at the 8-second boundary.
- AC-3.2.g: With `rightSidebarDock == nil` and `rightSidebar.mode == "find"`, the seeded rail has one slot with Find selected, and all legacy `UserDefaults` keys are unchanged → migration is non-destructive.
- AC-3.2.h: A snapshot describing 3 slots restores as 3 slots, and a new split on it is refused → restore is non-destructive while the cap still binds new splits.

**Acceptance Tests**
- Test-3.2.a: Unit — `cmuxTests/SidebarDockPersistenceTests.swift` (NEW) `windowSnapshotDeclaresOptionalRailFields()`.
- Test-3.2.b: Regression — `schemaVersionStillOne()`.
- Test-3.2.c: The same suite is the executable gate for AC-3.2.c.
- Test-3.2.d: Regression — `legacySessionWithoutRailFieldsDecodesCleanly()`, modeled on the same-named dock test.
- Test-3.2.e: Integration — `twoSlotRailRoundTrips()`.
- Test-3.2.f: Regression — `autosaveFingerprintReactsToRearrangement()`.
- Test-3.2.g: Integration — `seedsFromLegacyModeAndLeavesKeysIntact()`.
- Test-3.2.h: Regression — `restoreIsNonDestructiveAboveSlotCap()`.

**Verification Commands**
```bash
set -euo pipefail
xcodebuild -project cmux.xcodeproj -list >/dev/null
grep -qF 'var leftSidebarDock: SessionSplitContainerSnapshot? = nil' Sources/SessionPersistence.swift
grep -qF 'var rightSidebarDock: SessionSplitContainerSnapshot? = nil' Sources/SessionPersistence.swift
grep -qF 'static let currentVersion = 1' Sources/SessionPersistence.swift
test -f Sources/Sidebar/SidebarDockStore+SessionSnapshot.swift
test -f Sources/Sidebar/SidebarDockStore+SessionRestore.swift
grep -qF 'fileExplorer.dividerPosition' Sources/FileExplorerState.swift
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/SidebarDockPersistenceTests CMUX_SKIP_ZIG_BUILD=1 test
./scripts/test-unit.sh -only-testing:cmuxTests/DockSessionPersistenceTests CMUX_SKIP_ZIG_BUILD=1 test
./scripts/test-unit.sh -only-testing:cmuxTests/SessionPersistenceTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 3.3 Named saved layouts carry the arrangement

**Dependencies:** 3.2

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- "Wherever layouts are saved" is two mechanisms. 3.2 covered the live session file (`~/Library/Application Support/cmux/session-<safeBundleId>.json`). This item covers **named saved layouts**: `~/.config/cmux/layouts.json`, managed by `Sources/SavedLayoutStore.swift`, element `CmuxSavedLayout { name, description, workspace: CmuxWorkspaceDefinition }`.
- Add an optional field to `CmuxWorkspaceDefinition` (`Sources/CmuxWorkspaceDefinition.swift:3`) and declare the shape explicitly in `Sources/Sidebar/CmuxSidebarDockDefinition.swift` (NEW). A session snapshot cannot be reused here because it carries live panel UUIDs, meaningless in a reusable template:
  ```swift
  struct CmuxSidebarDockDefinition: Codable, Sendable, Hashable {
      struct Slot: Codable, Sendable, Hashable {
          var panels: [String]      // RightSidebarMode raw values, or "workspaceSelector"
          var selected: String?     // must be a member of `panels`
      }
      struct Rail: Codable, Sendable, Hashable {
          var slots: [Slot]         // 1 or 2 on write; more tolerated on read
          var split: Double?        // clamped 0.1...0.9, as CmuxSplitDefinition does
      }
      var left: Rail?
      var right: Rail?
  }
  ```
  JSON keys are the property names verbatim (`left`, `right`, `slots`, `panels`, `selected`, `split`). `selected` is explicit because the declarative schema cannot express per-pane tab selection through the surrounding `focus` convention — a documented gap at `Sources/Workspace+LayoutCapture.swift:159-163` (issue #7444).
- `layouts.json` has no version field, and an optional field on `CmuxWorkspaceDefinition` is transparently forward- and backward-compatible; every other field there already uses `decodeIfPresent`, so no migration is needed.
- Capture in `Sources/Workspace+LayoutCapture.swift` (`captureLayoutDefinition()`), apply in `Sources/TabManager+SavedLayouts.swift`.
- Failure modes: an unknown panel string is skipped and the rest applied; a `split` outside `0.1...0.9` is clamped; `selected` not in `panels` falls back to the first entry.

**Acceptance Criteria**
- AC-3.3.a: `CmuxWorkspaceDefinition` gains the optional field decoded with `decodeIfPresent` → old `layouts.json` files decode unchanged.
- AC-3.3.b: A pre-change `layouts.json` decodes with the field `nil` → back-compat holds without a version field.
- AC-3.3.c: `./scripts/test-unit.sh -only-testing:cmuxTests/SidebarDockSavedLayoutTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.
- AC-3.3.d: Saving a layout from a window with a two-slot right rail and applying it to a fresh window reproduces two slots with the same panel strings, order, selection, and ratio → the arrangement travels with named layouts.
- AC-3.3.e: A `split` of `0.02` is clamped to `0.1` → ratios are sanitized as `CmuxSplitDefinition` does.
- AC-3.3.f: An unknown panel string is skipped without throwing → a forward-compatible file does not break the apply path.
- AC-3.3.g: A `selected` value absent from `panels` falls back to the first entry → malformed templates degrade rather than crash.

**Acceptance Tests**
- Test-3.3.a: Unit — `cmuxTests/SidebarDockSavedLayoutTests.swift` (NEW) `definitionDecodesIfPresent()`.
- Test-3.3.b: Regression — `legacyLayoutsFileDecodesWithNilField()`.
- Test-3.3.c: The same suite is the executable gate for AC-3.3.c.
- Test-3.3.d: Integration — `saveThenApplyReproducesTwoSlotRail()`.
- Test-3.3.e: Unit — `splitRatioIsClamped()`.
- Test-3.3.f: Regression — `unknownPanelStringIsSkipped()`.
- Test-3.3.g: Regression — `invalidSelectedFallsBackToFirst()`.

**Verification Commands**
```bash
set -euo pipefail
xcodebuild -project cmux.xcodeproj -list >/dev/null
test -f Sources/Sidebar/CmuxSidebarDockDefinition.swift
# A bare `grep decodeIfPresent` would pass on the base commit; assert the new field
# specifically, since every pre-existing field already uses decodeIfPresent.
rg -q 'decodeIfPresent\(\s*CmuxSidebarDockDefinition\.self,\s*forKey:\s*\.sidebarDock\s*\)' Sources/CmuxWorkspaceDefinition.swift
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/SidebarDockSavedLayoutTests CMUX_SKIP_ZIG_BUILD=1 test
./scripts/test-unit.sh -only-testing:cmuxTests/SavedLayoutStoreTests CMUX_SKIP_ZIG_BUILD=1 test
./scripts/test-unit.sh -only-testing:cmuxTests/SavedLayoutDefinitionTests CMUX_SKIP_ZIG_BUILD=1 test
```

## Phase 4: Rollout Surfacing, Localization Audit, and Documentation

**Purpose:** This phase cannot start until Phases 1 through 3 are complete, because both work items take the finished feature as input: the Settings row exposes a flag whose feature must be dogfoodable end to end before a user is invited to enable it, and the localization audit's input is the complete set of user-facing surfaces the project actually added. Note the flag itself is defined in 1.1, not here — only its user-facing surfacing is deferred.

### 4.1 Settings surfacing and configuration

**Dependencies:** 1.1, 2.1, 2.3, 3.1, 3.2, 3.3

**Landing:** fork-only

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

**Acceptance Tests**
- Test-4.1.a: Integration — `cmuxTests/SidebarDockBetaFlagTests.swift` (NEW) `settingsRowAndConfigFileRoundTrip()`.
- Test-4.1.b: Regression — the feature-flag lint.
- Test-4.1.c: The same suite is the executable gate for AC-4.1.c.
- Test-4.1.d: Regression — `flagOffWritesNoRailFields()`.
- Test-4.1.e: Regression — `togglingFlagKeepsSnapshotLoadable()`.
- Test-4.1.f: Unit — `settingsRowStringsAreLocalized()`.

**Verification Commands**
```bash
set -euo pipefail
xcodebuild -project cmux.xcodeproj -list >/dev/null
grep -qF 'sidebar.beta.dock.enabled' Sources/App/WorkspaceRuntimeSettings.swift
python3 scripts/lint-feature-flags.py
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/SidebarDockBetaFlagTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 4.2 Localization audit and documentation

**Dependencies:** 1.2, 1.4, 2.1, 2.2, 2.3, 4.1

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Enumerate every user-facing surface this project added and verify each has `en` + `ja` entries with `state == "translated"` and a `ja` value differing from `en`. The complete key list: `sidebarDock.splitRail.top`, `sidebarDock.splitRail.bottom` (1.2); the five quad keys `shortcut.splitQuad.label`, `menu.view.splitQuad`, `command.terminalSplitQuad.title`, `terminalContextMenu.splitQuad`, `workspace.tooltip.splitQuad` (1.4) — note there is deliberately **no** `command.terminalSplitQuad.subtitle`, because every built-in config action shares the single subtitle `command.cmuxConfig.builtInSubtitle` (`Sources/CmuxConfig.swift:1400`) and no per-action subtitle mechanism exists; demanding such a key would make this criterion unsatisfiable; `sidebarDock.workspaces.title` (2.2); the right-rail header strings (2.1); and the Settings row strings (4.1).
- Web-side catalogs: add `cmux.splitQuad` to the `nightlyActionRegistryDesc` and `actionTypeBuiltin` strings in `web/messages/en.json` and `web/messages/ja.json`; these are prose sentences carrying inline element tags, so the TSX consumer that renders them must gain a matching tag handler. Add the `splitQuad` entry with `en`/`ja` descriptions to the `split-panes` category in `web/data/cmux-shortcuts.ts`.
- **The shipped Dock docs page is localized and must not be missed:** `web/app/[locale]/(landing)/docs/dock/page.tsx` renders via `useTranslations("docs.dock")` from `web/messages/{en,ja}.json`. Updating only the internal `docs/dock.md` would leave the user-visible page stale in both locales, violating §1's "update every supported message catalog". Update the `docs.dock` keys covering the split affordances and shortcuts, including the Dock-focused shortcut behavior described at `docs/dock.md:23`.
- Run the prescribed audit: parse the touched localization files, compare changed keys across `en`/`ja`, and `rg` the changed Swift/TS/TSX/docs files for newly introduced bare English in `Text(`, `Button(`, `.help(`, `.safeHelp(`, `.tooltip(`, alert titles, and accessibility labels. Record the result in the handoff, including anything unverified. `defaultValue`, English fallback text, and schema descriptions do not count.
- Record the locale bookkeeping accurately: `Resources/Localizable.xcstrings` has 20 locales; `knownRegions` has 19 entries = 18 locales + Base, missing `km` and `uk`; `CLAUDE.md` and `skills/cmux-localization/SKILL.md` both say "English and Japanese". This PRD meets the `en` + `ja` bar and does not attempt the other 18.
- Add `docs/sidebar-docking.md` (NEW) documenting: rails as dock spaces; that a horizontal divider is Bonsplit `.vertical`; the drop bands being 25% edge bands with an 80pt floor, with the reachable band given for **both** rails (`x ∈ [80, 196]` at a 276pt right rail, `x ∈ [80, 160]` at a 240pt left rail, and unreachable at a left rail ≤ 160pt) and the non-drag command named as the primary path; the `maxSlotsPerRail` cap of 2 slots and its non-destructive restore; cross-rail moves; the placement matrix; and both persistence mechanisms (the session file and `layouts.json`).
- Update `docs/dock.md` to distinguish the Dock from sidebar dock spaces, and add a `CHANGELOG.md` entry.

**Acceptance Criteria**
- AC-4.2.a: Every key in the enumerated list has `en` + `ja` with `state == "translated"` and differing values → the audit passes for the complete surface list.
- AC-4.2.b: `docs/sidebar-docking.md` documents the orientation inversion, the drop-band geometry **with both rails' numbers including the unreachable ≤160pt left-rail case**, the slot cap, and both persistence mechanisms → the four non-obvious constraints are written down against the real worst case.
- AC-4.2.c: All CI guard scripts pass → `./scripts/check-pbxproj.sh`, `python3 scripts/check-workspace-package-groups.py --check`, `python3 scripts/check-package-resolved-policy.py`, `./tests/test_ci_pbxproj_test_wiring.sh`, and `python3 tests/test_ci_sidebar_lazy_layout_guard.py` all exit 0.
- AC-4.2.d: `web/messages/en.json` and `ja.json` both contain `cmux.splitQuad`, and the `docs.dock` keys mention the quad affordance → the user-visible docs page is not stale in either locale.
- AC-4.2.e: `docs/dock.md` distinguishes the Dock from sidebar dock spaces → the two features are not conflated.
- AC-4.2.f: No bare English literal appears in a user-facing Swift call in any file this project changed → `rg` over the changed set is clean.

**Acceptance Tests**
- Test-4.2.a: Unit — `cmuxTests/SidebarDockLocalizationAuditTests.swift` (NEW) `everyProjectKeyIsGenuinelyLocalized()` over the explicit key list.
- Test-4.2.b: Unit — `sidebarDockingDocCoversFourConstraints()`.
- Test-4.2.c: Regression — the five CI guard scripts.
- Test-4.2.d: Unit — `webCatalogsAndDockDocsPageMentionQuad()`.
- Test-4.2.e: Unit — `dockDocDistinguishesRails()`.
- Test-4.2.f: Regression — `noBareEnglishInChangedFiles()`.

**Verification Commands**
```bash
set -euo pipefail
xcodebuild -project cmux.xcodeproj -list >/dev/null
test -f docs/sidebar-docking.md
grep -qF 'Bonsplit `.vertical`' docs/sidebar-docking.md
grep -qF 'maxSlotsPerRail' docs/sidebar-docking.md
grep -qF '160' docs/sidebar-docking.md
grep -qF '276' docs/sidebar-docking.md
grep -qF 'layouts.json' docs/sidebar-docking.md
grep -qF 'session-' docs/sidebar-docking.md
grep -qiF 'sidebar dock' docs/dock.md
grep -qF 'cmux.splitQuad' web/messages/en.json
grep -qF 'cmux.splitQuad' web/messages/ja.json
grep -qF 'splitQuad' web/data/cmux-shortcuts.ts
python3 - <<'PY'
import json,sys
d=json.load(open("Resources/Localizable.xcstrings"))["strings"]
keys=["sidebarDock.splitRail.top","sidebarDock.splitRail.bottom","sidebarDock.workspaces.title",
      "shortcut.splitQuad.label","menu.view.splitQuad","command.terminalSplitQuad.title","terminalContextMenu.splitQuad","workspace.tooltip.splitQuad"]
bad=[]
for k in keys:
    loc=d.get(k,{}).get("localizations",{})
    en=loc.get("en",{}).get("stringUnit",{}); ja=loc.get("ja",{}).get("stringUnit",{})
    if ja.get("state")!="translated" or not ja.get("value") or ja.get("value")==en.get("value"):
        bad.append(k)
if bad: sys.exit("not genuinely localized: %s" % bad)
PY
./scripts/check-pbxproj.sh
python3 scripts/check-workspace-package-groups.py --check
python3 scripts/check-package-resolved-policy.py
./tests/test_ci_pbxproj_test_wiring.sh
python3 tests/test_ci_sidebar_lazy_layout_guard.py
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/SidebarDockLocalizationAuditTests CMUX_SKIP_ZIG_BUILD=1 test
```

## 3. Completion Criteria

The project is complete when all of the following hold. Verification commands are run from the feature branch with `PRD_BASE_SHA` (`69b2c55e27…`) fetched and resolvable, after the §1.5 bootstrap gate has succeeded once in the worktree.

1. Every work item's Verification Commands block exits 0.
2. A tagged Debug build succeeds: `CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag sidebar-dock`.
3. With the flag on: the non-drag split command puts a chosen tool tab into a new bottom slot of a rail with the other tabs above; a tool tab moves from the right rail into the left rail's second slot; both arrangements survive quit and relaunch; and saving then applying a named layout reproduces them.
4. With the flag off, both rails behave exactly as on `PRD_BASE_SHA`, no session-snapshot rail field is written, and the three conditionalized UI test suites pass.
5. The pane tab-bar split-button row shows five buttons ending in the quad splitter; the quad action produces a true 2×2 topology per AC-1.3.g (not merely four panes) and is reachable from all **five** entrypoints listed in 1.4; the pinned `vendor/bonsplit` SHA is unchanged and its worktree clean.
6. `Sources/SessionPersistence.swift` still declares `static let currentVersion = 1`, and a session file written by `PRD_BASE_SHA` still restores without loss.
7. The localization audit of 4.2 is recorded in the handoff with `en` + `ja` for every enumerated key.
8. All CI guard scripts in AC-4.2.c pass, and `./scripts/lint-pbxproj-test-wiring.sh` passes with all 12 new test suites wired (one per work item).

## 4. Rollout & Validation

### Rollout Strategy

- All rail behavior ships behind `sidebar.beta.dock.enabled`, default `false`, for the whole PRD. The quad split ships **unflagged** — additive, no persistence surface.
- Phase order is the rollout order. Within Phase 1 the quad-split items (1.3, 1.4) and the substrate items (1.1, 1.2) are independent and may be landed in either order or in parallel.
- **Everything in this PRD lands fork-only, on `main`.** No work item is upstream-bound, so nothing here blocks on an external review cycle. This is a deliberate change from an earlier draft that routed the quad split upstream: the `.custom("cmux.splitQuad")` design exists because *this fork* cannot push to `manaflow-ai/bonsplit`, and upstream — which owns bonsplit — would reasonably prefer a built-in case, so shipping the indirect design upstream would invite rework and leave the fork's copy diverging anyway. Optional upstream contributions are recorded in §5 and are explicitly not prerequisites.
- Because nothing is double-landed, there is no duplicate-change reconciliation problem. If an upstream contribution is later pursued, the sequence is: land upstream first, take it into the fork through the `upstream-main` mirror, then delete the fork's local copy in the same commit — never open both PRs in parallel, because `Resources/Localizable.xcstrings` (a 4176-key JSON) and the two `CmuxConfig` default lists would conflict by construction. Record any accepted divergence in `docs/ghostty-fork.md`, which `CLAUDE.md` designates for exactly that.
- If an upstream PR is ever opened, the mechanics need a remote that does not exist locally today (only `origin`, the fork): `git remote add upstream https://github.com/manaflow-ai/cmux.git`, `git fetch upstream main`, `git switch -c <topic> upstream/main`, `git push -u origin <topic>`, `gh pr create --repo manaflow-ai/cmux --head stokd-cloud:<topic> --base main`. Note `origin/upstream-main` currently resolves to the same commit as `main`, so a mirror fetch is a no-op today.
- Rollback: turning the flag off restores the pre-PRD rails with no data migration, because 3.2 preserves every legacy `UserDefaults` key unmodified and the new snapshot fields are simply unread.
- Rollback triggers: any main-thread CPU regression attributable to the rails (the `LazyLayoutViewCache` spin-loop class), any session-snapshot decode failure in the field, or loss of a rail arrangement across relaunch.
- Flipping the default to `true` is out of scope and requires a separate decision after dogfood, including a macOS 15 pass (§1).

### Post-Launch Validation

- Watch for `LazyLayoutViewCache` main-thread spin symptoms after enabling the flag. Standing guards: `python3 tests/test_ci_sidebar_lazy_layout_guard.py` (legacy files only) and `./scripts/verify-main-thread-ca-transactions.sh`. Remember the guard cannot see the new sidebar files; the `rg` assertions in 1.1 and 2.2 are the coverage for those.
- Confirm session snapshots keep loading: a decode failure discards the whole file, so watch for any rise in zero-window startups.
- Verify the autosave fingerprint genuinely captures rearrangements (AC-3.2.f) — a miss silently loses arrangements at the 8-second boundary.
- Confirm the quad button appears in the main workspace pane tab bars and in Dock pane tab bars, and that the remote-tmux embedded lane — which filters to only `splitRight`/`splitDown` (`Sources/BonsplitConfiguration+RemoteTmuxEmbedded.swift:22-29`) — still behaves with an unknown custom id present in the host list. A fourth render site exists in the debug Tab Bar Backdrop Lab (`Sources/cmuxApp.swift:3757`), which passes Bonsplit's own four defaults and is deliberately excluded.
- Re-check rail drag ergonomics at **both** floors, since the side bands are a flat 160pt below 320pt width: the 276pt right rail (58% consumed, `x ∈ [80, 196]`) and the 240pt default left rail (67%, `x ∈ [80, 160]`). Then verify the ≤160pt left-rail case explicitly, where the drag path does not exist and the non-drag command must be the only route — confirm it is discoverable there.

## 5. Open Questions

Every ambiguity was resolved autonomously; the decisions are recorded here. Three genuine unknowables remain, none blocking any Phase 1 work item.

- Decision: **Which sidebar hosts Find/Vault/Files** — the **right** sidebar, grounded purely in code: `RightSidebarPanelView.modeBar` (`Sources/RightSidebarPanelView.swift:216`) is the only Find/Vault/Files tab row in the repository and the left sidebar has no tab row. An earlier draft of this PRD cited a screenshot as evidence; no image content is relied on here.
- Decision: **Do not resurrect `CmuxDockable`** — build on Bonsplit plus the existing `RightSidebarToolPanel` and `SessionSplitContainerSnapshot`, because (a) the request keeps the rails segregated, removing the canvas-placement abstraction's purpose; (b) `CmuxDockable` is not on `main`, so adopting it means first landing ~6,300 lines of canvas refactor that is 195 commits stale and collides with subsequently-merged upstream Dock work; and (c) Bonsplit already provides stacked splitting, tab reordering, cross-container drops, and layout persistence.
- Decision: **No `vendor/bonsplit` modification** — use `SplitActionButton.Action.custom("cmux.splitQuad")` via `requestCustomAction`, because the submodule is owned by `manaflow-ai` and this fork cannot push to it.
- Decision: **Everything lands fork-only** — an earlier draft marked the quad split `upstream-PR`, which was incoherent: its central design choice is justified by a fork-only access constraint that upstream does not share, and Phases 2–4 would then have depended on an external merge. Fork-only removes the blocking risk and the double-landing conflict.
- Decision: **Quad button position and icon** — appended 5th and last with `square.split.2x2`, matching "vertical, then horizontal, then split quad at the end" and the `square.split.2x1`/`1x2` family.
- Decision: **Quad shortcut `⌃⌘D`, and it is an addition the request did not ask for** — the request asked only for a button. `⌃⌘D` was chosen after auditing all 13 `key: "d"` bindings across `Sources/KeyboardShortcutSettings.swift` and `Packages/macOS/CmuxSettings/Sources/CmuxSettings/Values/ShortcutAction+Defaults.swift`; the near neighbours are `⌘D` (splitRight), `⌘⇧D` (splitDown), `⌥⌘D` / `⌥⌘⇧D` (browser splits), `⌃⌘⇧D` (`openDiffViewer`), `⌥⌃⌘D`, and `⌃D` (`diffViewerScrollHalfPageDown`). `⌃⌘D` is unbound. An earlier draft justified this by noting `⌃⌘=` was taken, which was a non-sequitur.
- Decision: **"Split horizontally" means Bonsplit `.vertical`** — a horizontal divider producing top and bottom, which the request describes explicitly ("Files on the bottom, Find/Vault on the top"). Restated at every use site because an inverted implementation is the likeliest failure mode.
- Decision: **Two slots per rail as a named constant, with non-destructive restore** — `SidebarDockStore.maxSlotsPerRail = 2` is enforced on new splits only. The request describes a top/bottom halving, but it also says "I'm going to add several new things to this area", which is the strongest available argument against a hard cap. So the cap binds new splits while restore is deliberately non-destructive (AC-3.2.h), meaning a future cap raise never has to recover data this project discarded. An earlier draft pruned 3-slot snapshots to 2 and would have destroyed exactly that.
- Decision: **No side-by-side splits inside a rail, enforced by delegate veto** — a `.horizontal` split at 276pt yields two ~138pt columns no tool renders usably. Zone removal is impossible from host code: `DropZone`'s five cases and `zoneForLocation` are private to the internal `PaneContainerView`, and `BonsplitConfiguration` has no drop-zone knob. The veto `splitTabBar(_:shouldSplitPane:orientation:)` is consulted by all three `splitPane` overloads, so it is sufficient. Accepted cost: the left/right zone highlight still appears during a drag and the drop is then refused.
- Decision: **Ship a non-drag split command as the primary path** — because the left/right bands consume 160 of 276pt and the top/bottom bands are reachable only in `x ∈ [80, 196]`, drag alone is not dependable. The context-menu and palette command in 1.2 make the interaction deterministic and are what the acceptance tests drive.
- Decision: **`RightSidebarModeButton.<mode>` accessibility identifiers are lost under the flag** — Bonsplit tabs carry no identifier and expose no injection API, so preserving them needs a submodule change. Three UI test suites — the ones that actually assert the identifier or the mode-bar height — are conditionalized on the flag instead (2.1); `SettingsSidebarBetaBehaviorUITests` only mentions the identifier in comments and is excluded. This is real test-coverage debt, accepted because the container identifiers survive and the flag defaults off.
- Decision: **Rail tab set is Files, Find, Vault only** — `.feed` and `.customSidebar` keep the legacy path and `.dock` is excluded because nesting a `BonsplitController` inside a Bonsplit pane is out of scope.
- Decision: **The rail split-button lane is suppressed unconditionally** (`showSplitButtons = false`) — a five-button lane is 140pt of a 240–276pt rail and crowds the tab strip, and `newTerminal`/`newBrowser` would create panel types the placement matrix forbids. Two earlier drafts got the supporting argument wrong and both errors are recorded here so the reasoning is not re-derived incorrectly: the first claimed the 5th button forced Phase 2 to choose a lane composition; the second claimed a hard "69pt budget" that four buttons already overflowed. Neither is true — `maximumSplitButtonLaneWidth` is a `max(...)` whose `minimumVisibleSplitButtonLaneWidth` term guarantees full visibility for up to `minimumFullyVisibleSplitButtonCount = 5` buttons at any width, so the lane never clips. Unconditional suppression is what actually makes the quad button and the rail work independent.
- Decision: **`SidebarDockStore` is the sole source of truth for selection**, with `FileExplorerState.mode` a derived mirror of the focused slot's selected tab, written only from two delegate callbacks. Necessary because `mode` is a single scalar and cannot describe two visible slots.
- Decision: **Persist to both layout mechanisms** — the live session file and `~/.config/cmux/layouts.json`, because "wherever layouts are saved" is literally two files.
- Decision: **Keep legacy right-sidebar `UserDefaults` keys, and do not retire `fileExplorer.dividerPosition`** — non-destructive migration makes a flag-off downgrade lossless. Retiring the dead divider key would be an ungated behavior change orthogonal to this work, and `FileExplorerState` does read it in `init` even though nothing renders it.
- Decision: **Localize `en` + `ja` only**, with a genuine-translation check (`state == "translated"` and `ja != en`) because the catalog contains keys whose non-English values are verbatim English at `needs_review`.
- Decision: **Right-rail geometry stays in global `UserDefaults`** — not migrated into the per-window snapshot, even though the asymmetry with the left rail is a real wart, because it is orthogonal and would enlarge an already-large change. Recorded as a follow-up.
- Follow-up (not blocking): contribute a host-configurable drop-zone set to `manaflow-ai/bonsplit` so left/right bands can be disabled for fixed-width containers, which would remove both the cosmetic highlight and the 160pt dead-band ergonomics problem.
- Follow-up (not blocking): contribute `Bonsplit.Tab.accessibilityIdentifier` upstream so per-tab identifiers can be restored and the conditionalized UI tests re-enabled.
- Follow-up (not blocking): contribute a built-in bonsplit `.splitQuad` case upstream, which would let the fork drop its `.custom` indirection.
- Open question: Should a rail arrangement be **per-window** or **per-workspace**? This PRD attaches it to `SessionWindowSnapshot`, matching where the left sidebar's state and the window Dock already live. `SessionWorkspaceSnapshot` also carries a `dock` field, so a per-workspace variant is expressible without a schema change if dogfood shows users want it. Does not block any work item.
- Open question: When the same tool panel is docked in a rail **and** open as a main-area pane, should they share one instance? Today `RightSidebarToolPanel` lazily creates its own stores per instance (`Sources/RightSidebarToolPanel.swift:32-57`), so the current behavior is two independent instances and this PRD preserves it. A product question for dogfood.
- Process note, recorded for the reader's calibration: this document went through three parallel adversarial review rounds plus one re-review, all of which returned REJECT and whose findings are incorporated above. The review budget was exhausted at the re-review, so its six blocking findings — the false lane arithmetic, the missed exhaustive switch at `Sources/AppDelegate.swift:15493`, the left-rail drop-band geometry, the missing 2×2 topology criterion, the vacuous `.environment(` guard, and the three-vs-four UI-suite contradiction — were fixed inline and each fix was verified directly against the repo, but **the corrected document has not itself been through a further independent adversarial pass**. The highest-residual-risk areas, in order, are: the exhaustive-switch enumeration (five sites claimed; a sixth would break the build), the chrome disposition table in 2.1 (seven affordances, each asserted to be preserved or dropped), and the `CmuxSidebarDockDefinition` shape in 3.3 (no consumer exists yet to validate it against).
- Open question: Is losing the per-tab keyboard-shortcut hint overlay and the window-drag-handle behavior in the right rail's tab bar (2.1's chrome disposition table) acceptable, or does either need a replacement affordance before the flag default flips? Requires dogfood to answer; does not block implementation.
