# cmux Canvas Dockable Refactor

## 0. Source Context

**Derived From:** "refactor of the cmux canvas system with the singular task of making every visible object derive from the same common dockable type so everything can be moved around wherever you want."
**Feature Name:** cmux Canvas Dockable Refactor
**PRD Owner:** brian.stoker@eonesolutions.com
**Last Updated:** 2026-07-23
**Repository:** `apps/ghostty-dock` submodule — fork `stokd-cloud/ghostty-dock`, upstream `manaflow-ai/cmux`.

### Summary

The cmux canvas today hard-codes an asymmetry: terminals are a special case
(`CanvasPaneContent.terminal(TerminalPanel, …)` mounted directly as an AppKit
subview) while every other visible object is lumped into
`CanvasPaneContent.hosted(any Panel, NSView)`. That enum, plus a
terminal/browser-only `openNewCanvasPane` and an 11-optional-field
`SessionPanelSnapshot`, means "move/dock this object anywhere" only fully works
for terminals. This refactor introduces **one common `Dockable` protocol** that
every visible object derives from, collapses the content-kind switch into a
single generic mount, generalizes canvas-pane creation to any object kind, and
unifies persistence — so any visible object can be docked, split, moved between
panes/workspaces/windows, floated on the freeform canvas, and restored, with no
per-type special-casing. The entire change is **fork-only**: the upstream
canvas geometry (`CmuxCanvas`) and mount seam (`CmuxCanvasUI`) are already
content-agnostic and are not modified.

## 1. Objectives & Constraints

### Objectives
- Introduce a single common type — `Dockable` — that every visible canvas object
  conforms to, so canvas code never branches on concrete content type.
- Eliminate the `CanvasPaneContent` `.terminal` vs `.hosted` enum and all
  terminal-vs-hosted branching inside `CanvasPaneContentMount`.
- Generalize new-pane creation from `CanvasNewPaneType { terminal, browser }` to
  any `DockableKind`, via a factory registry.
- Unify session persistence from the 11-optional-field `SessionPanelSnapshot`
  into a single `DockableSnapshot { id, kind, payload }` with a backward-compatible
  decoder for existing on-disk sessions.
- Preserve terminal-specific behavior (window-portal detach/reattach, occlusion)
  and browser-specific behavior (webview visibility) as **opt-in capabilities**
  (`PortalHostable`, `setDockRendering`) rather than enum branches.

### Constraints
- **Fork-only:** no file under `Packages/macOS/CmuxCanvas/Sources` or
  `Packages/macOS/CmuxCanvasUI/Sources` (upstream-owned) may be modified, so the
  fork stays cleanly rebasable on `manaflow-ai/cmux`.
- **No behavioral regression:** terminals keep direct portal-detached mounting;
  browsers keep webview visibility control; session restore of pre-refactor
  sessions must succeed.
- **Swift 6 language mode** (`.swiftLanguageMode(.v6)`, `ExistentialAny`,
  `InternalImportsByDefault`) — matches `CmuxCanvas/Package.swift`.
- **`@MainActor` isolation:** all mounting/lifecycle types are main-actor, matching
  `CanvasPaneContentMounting`.
- Preserve the existing 11 content kinds (parity with `PanelType`): `terminal`,
  `browser`, `markdown`, `filePreview`, `rightSidebarTool`, `customSidebar`,
  `agentSession`, `project`, `extensionBrowser`, `workspaceTodo`, `cloudVMLoading`.

## 1.5 Required Toolchain

| Tool | Min Version | Install Command | Verify Command |
|------|-------------|-----------------|----------------|
| macOS | 14.0 | (OS) | `sw_vers -productVersion` |
| Xcode | 15.0 | App Store / `xcodes install` | `xcodebuild -version` |
| Swift | 6.0 | (bundled with Xcode) | `swift --version` |
| Zig | latest | `brew install zig` | `zig version` |

One-time setup (submodules + GhosttyKit.xcframework):

```bash
cd apps/ghostty-dock && ./scripts/setup.sh
```

> **Working directory for all Verification Commands:** the `apps/ghostty-dock`
> repository root. `./scripts/*` and `Packages/macOS/*` paths are relative to it.
> `swift test --package-path Packages/macOS/<Pkg>` runs without a full Xcode app
> build; `./scripts/reload.sh --tag <slug>` performs the full app compile.

## 2. Execution Phases

## Phase 1: Establish the common Dockable contract package

**Purpose:** Every downstream change conforms to or switches on the `Dockable`
type; the type must exist and be independently verified before any panel can
adopt it or any enum can be collapsed. This phase adds a new, self-contained SPM
package and touches no app code, so it is a pure, `swift test`-verifiable
foundation with zero regression surface.

### 1.1 Create `CmuxDockable` package skeleton and `DockableKind`

**Implementation Details**
- Create new SPM package `Packages/macOS/CmuxDockable` with
  `Package.swift` (`swift-tools-version: 6.0`, `platforms: [.macOS(.v14), .iOS(.v17)]`,
  library product `CmuxDockable`, target `CmuxDockable`, test target
  `CmuxDockableTests`), mirroring `Packages/macOS/CmuxCanvas/Package.swift`
  swiftSettings (`.swiftLanguageMode(.v6)`, `ExistentialAny`, `InternalImportsByDefault`).
- Add `Sources/CmuxDockable/DockableKind.swift`:
  `public enum DockableKind: String, Codable, Sendable, CaseIterable` with exactly
  these 11 cases and raw values, matching `Sources/Panels/Panel.swift` `PanelType`
  EXACTLY (only `filePreview` has an explicit lowercased raw value; all others use
  the implicit case-name raw value):
  `terminal="terminal"`, `browser="browser"`, `markdown="markdown"`,
  `filePreview="filepreview"`, `rightSidebarTool="rightSidebarTool"`,
  `customSidebar="customSidebar"`, `agentSession="agentSession"`,
  `project="project"`, `extensionBrowser="extensionBrowser"`,
  `workspaceTodo="workspaceTodo"`, `cloudVMLoading="cloudVMLoading"`.
  Include a lenient `init(from:)` decoding case-insensitive raw values (parity with
  `PanelType.init(from:)`).
- NOTE: `PanelType` is NOT `CaseIterable`, so the parity test MUST NOT iterate
  `PanelType.allCases`. It asserts against a literal expected raw-value set and a
  bidirectional round-trip (`PanelType(rawValue:)` ↔ `DockableKind(rawValue:)`).
- Failure modes: raw-value drift from `PanelType` — guarded by the exact-string
  parity test in AC-1.1.b (any casing change breaks it, which is the point).

**Acceptance Criteria**
- AC-1.1.a: `Packages/macOS/CmuxDockable/Package.swift` exists declaring targets
  `CmuxDockable` and `CmuxDockableTests` → package resolves.
- AC-1.1.b: `DockableKind` has exactly 11 cases and its raw-value set equals the
  literal set `{"terminal","browser","markdown","filepreview","rightSidebarTool",
  "customSidebar","agentSession","project","extensionBrowser","workspaceTodo",
  "cloudVMLoading"}`, AND for each expected raw value `PanelType(rawValue:)` and
  `DockableKind(rawValue:)` are both non-nil (bidirectional round-trip) → parity
  test passes. (Does NOT reference `PanelType.allCases`, which does not exist.)
- AC-1.1.c: `swift test --package-path Packages/macOS/CmuxDockable` → exit 0.

**Acceptance Tests**
- Test-1.1.a: Unit — `DockableKindTests.rawValueParityWithPanelType` asserts
  `DockableKind.allCases.count == 11`, that `Set(DockableKind.allCases.map(\.rawValue))`
  equals the literal expected set above, and that every expected raw value maps
  non-nil through both `PanelType(rawValue:)` and `DockableKind(rawValue:)`.
- Test-1.1.b: Unit — `DockableKindTests.codableRoundTrip` encodes and decodes every
  case and asserts equality; decodes a mixed-case raw value (`"FilePreview"`) to `.filePreview`.

**Verification Commands**
```bash
cd apps/ghostty-dock
test -f Packages/macOS/CmuxDockable/Package.swift
swift build --package-path Packages/macOS/CmuxDockable
swift test --package-path Packages/macOS/CmuxDockable --filter DockableKindTests
```

### 1.2 Define the `Dockable` protocol, capabilities, and mount context

**Implementation Details**
- Add `Sources/CmuxDockable/Dockable.swift`:
  `@MainActor public protocol Dockable: AnyObject, Identifiable where ID == UUID`
  with requirements:
  - `var dockableKind: DockableKind { get }`
  - `var dockableTitle: String { get }`
  - `func makeDockContentView(context: DockableMountContext) -> NSView`
  - `func setDockRendering(_ rendering: Bool)`
  - `func tearDownDockMount()`
- Add default implementations (protocol extension): `setDockRendering(_:)` no-op,
  `tearDownDockMount()` no-op. `makeDockContentView` has NO default (required).
- Add `Sources/CmuxDockable/PortalHostable.swift`:
  `@MainActor public protocol PortalHostable: Dockable` with the full signatures
  `func detachContentFromPortal() -> NSView` (returns the detached content view to
  mount into the pane container) and `func reattachContentToPortal(_ view: NSView) -> Void`
  (returns the given view to the window portal system on unmount) — the opt-in
  capability the generic mount uses instead of a `.terminal` enum branch. Signatures
  mirror the current `.terminal`-case detach/reattach handling in
  `CanvasPaneContentMount` (`Sources/Canvas/CanvasPaneContent.swift`).
- Add `Sources/CmuxDockable/DockableMountContext.swift`:
  `public struct DockableMountContext` carrying `let container: NSView` and
  `let onFocus: @MainActor (UUID) -> Void` (the same inputs the current
  `CanvasPaneContentMount` init takes).
- Depend on `CmuxCanvasUI` for the `CanvasPaneContentMounting` seam so `CmuxDockable`
  can vend a mounting handle in 1.3 / Phase 3; import AppKit.
- Failure modes: a `Dockable` that is also `PortalHostable` must have its
  detach/reattach honored by the mount (covered in Phase 3); protocol-witness
  compile errors surface at build time.

**Acceptance Criteria**
- AC-1.2.a: `protocol Dockable` and `protocol PortalHostable: Dockable` are declared
  in `Sources/CmuxDockable/` → grep confirms both.
- AC-1.2.b: Default extensions make `setDockRendering`/`tearDownDockMount` optional
  for conformers, while `makeDockContentView` remains required → a conformer that
  implements only `dockableKind`, `dockableTitle`, `makeDockContentView` compiles.
- AC-1.2.c: `swift build --package-path Packages/macOS/CmuxDockable` → exit 0.

**Acceptance Tests**
- Test-1.2.a: Unit — `DockableProtocolTests.minimalConformerCompilesAndDefaults`
  defines a stub conformer implementing only the required members, asserts
  `setDockRendering(true)`/`tearDownDockMount()` are callable (defaulted) and
  `makeDockContentView` returns the expected `NSView`.
- Test-1.2.b: Unit — `DockableProtocolTests.portalHostableRefinesDockable` asserts a
  `PortalHostable` value is usable as `any Dockable`.

**Verification Commands**
```bash
cd apps/ghostty-dock
grep -rq 'protocol Dockable' Packages/macOS/CmuxDockable/Sources
grep -rq 'protocol PortalHostable: Dockable' Packages/macOS/CmuxDockable/Sources
swift build --package-path Packages/macOS/CmuxDockable
swift test --package-path Packages/macOS/CmuxDockable --filter DockableProtocolTests
```

### 1.3 Add the `DockableRegistry` (kind → factory + payload decode)

**Implementation Details**
- Add `Sources/CmuxDockable/DockableRegistry.swift`:
  `@MainActor public final class DockableRegistry` with:
  - `public static let shared = DockableRegistry()`
  - `public func register(kind: DockableKind, make: @escaping @MainActor () -> any Dockable, decode: @escaping @MainActor (Data) -> (any Dockable)?)`
  - `public func make(kind: DockableKind) -> (any Dockable)?`
  - `public func decode(kind: DockableKind, payload: Data) -> (any Dockable)?`
- The registry holds no app types; factories are injected by the app in Phase 2.3.
- `dependencies` on work item 1.2 (needs `Dockable`/`DockableKind`).
- Failure modes: `make`/`decode` for an unregistered kind returns `nil` (callers
  must handle); double-registration overwrites (last wins) — asserted in tests.

**Acceptance Criteria**
- AC-1.3.a: `DockableRegistry` exposes `register`, `make`, and `decode` → grep confirms.
- AC-1.3.b: Registering a stub factory then `make(kind:)` returns a non-nil `Dockable`
  of that kind; `make` for an unregistered kind returns `nil` → test passes.
- AC-1.3.c: `swift test --package-path Packages/macOS/CmuxDockable` → exit 0 (whole suite).

**Acceptance Tests**
- Test-1.3.a: Unit — `DockableRegistryTests.registerThenMakeReturnsConformer` registers
  a stub for `.markdown`, asserts `make(kind: .markdown)?.dockableKind == .markdown`.
- Test-1.3.b: Unit — `DockableRegistryTests.unregisteredKindReturnsNil` asserts
  `make(kind: .project)` is `nil` before registration.
- Test-1.3.c: Unit — `DockableRegistryTests.decodeRoundTrip` registers a decode that
  parses a payload and asserts the rehydrated conformer matches.

**Verification Commands**
```bash
cd apps/ghostty-dock
grep -Eq 'func register\(kind:|func make\(kind:|func decode\(kind:' Packages/macOS/CmuxDockable/Sources/CmuxDockable/DockableRegistry.swift
swift test --package-path Packages/macOS/CmuxDockable
```

## Phase 2: Conform every visible object to Dockable

**Purpose:** The enum collapse in Phase 3 is only safe once the general
(`Dockable`) path exists for all 11 content kinds; this phase adds the
conformances and capability implementations without removing any special-case,
so the app continues to build and behave identically (both paths coexist). It
cannot start before Phase 1 because there is no protocol to conform to.

### 2.1 Wire `CmuxDockable` into the app and make `Panel` refine `Dockable`

**Implementation Details**
- Add `CmuxDockable` as a dependency of the app target (in `cmux.xcodeproj` /
  the app's local package graph) so app Sources can `import CmuxDockable`.
- Edit `Sources/Panels/Panel.swift`: change `public protocol Panel` to refine
  `Dockable` (`public protocol Panel: Dockable`). Add a protocol extension mapping
  existing members to `Dockable` requirements where an existing accessor already
  exists (e.g. `dockableTitle` → existing title), so most conformers need no edit.
- Provide `dockableKind` on each panel by mapping the panel's existing `PanelType`
  (`var dockableKind: DockableKind { DockableKind(rawValue: self.type.rawValue)! }`
  in a shared extension keyed on the panel's `type`).
- `makeDockContentView` default routes to the panel's existing hosted view
  construction (the current `.hosted` NSView path), so all non-terminal panels get
  a correct default; terminal overrides in 2.2.
- Failure modes: any of the 11 panels failing to satisfy `Dockable` is a compile
  error (caught by the full build); `DockableKind(rawValue:)!` force-unwrap is
  guarded by the 1.1 parity test.

**Acceptance Criteria**
- AC-2.1.a: `Sources/Panels/Panel.swift` declares `protocol Panel: Dockable` → grep confirms.
- AC-2.1.b: The app target compiles with `import CmuxDockable` resolving → full build exits 0.
- AC-2.1.c: All 11 panel classes satisfy `Dockable` (no missing-witness errors) → build exits 0.

**Acceptance Tests**
- Test-2.1.a: Integration — full app build (`./scripts/reload.sh --tag canvas-dockable`)
  succeeds, proving every `Panel` conformer satisfies `Dockable`.
- Test-2.1.b: Regression — existing `cmuxTests` panel tests still pass under Xcode test.

**Verification Commands**
```bash
cd apps/ghostty-dock
grep -Eq 'protocol Panel: *Dockable' Sources/Panels/Panel.swift
grep -q 'import CmuxDockable' Sources/Panels/Panel.swift
./scripts/reload.sh --tag canvas-dockable
```

### 2.2 Move terminal/browser special behavior behind capabilities

**Implementation Details**
- `Sources/Panels/TerminalPanel.swift`: conform `TerminalPanel` to `PortalHostable`.
  Implement `detachContentFromPortal()` / `reattachContentToPortal()` by relocating
  the portal-detach/reattach logic currently embedded in
  `Sources/Canvas/CanvasPaneContent.swift` `CanvasPaneContentMount` (`.terminal`
  branch, lines ~53–66 and ~164–178) and `makeDockContentView` returning the
  `GhosttySurfaceScrollView` (the current direct-mount view).
- `TerminalPanel.setDockRendering(_:)` implements occlusion enable/disable (current
  terminal occlusion behavior from the mount's `.terminal` rendering branch).
- `Sources/Panels/BrowserPanel.swift`: implement `setDockRendering(_:)` to drive
  webview visibility (current `.hosted` browser visibility behavior).
- No enum removed yet; the mount still switches, but the behavior now also exists
  behind protocol methods, ready for Phase 3 to call generically.
- Failure modes: duplicated logic drift between the enum branch and the capability
  method (temporary, resolved in Phase 3 when the enum branch is deleted).

**Acceptance Criteria**
- AC-2.2.a: `TerminalPanel` conforms to `PortalHostable` and implements both portal
  methods → grep confirms `PortalHostable` on `TerminalPanel`.
- AC-2.2.b: `BrowserPanel` overrides `setDockRendering(_:)` → grep confirms.
- AC-2.2.c: Full app build exits 0 with the capabilities present.

**Acceptance Tests**
- Test-2.2.a: Integration — full build succeeds with `TerminalPanel: PortalHostable`.
- Test-2.2.b: Regression — manual/UI: a terminal pane still mounts portal-detached
  and a browser pane still hides its webview off-screen (documented repro in PR).

**Verification Commands**
```bash
cd apps/ghostty-dock
grep -Eq 'PortalHostable' Sources/Panels/TerminalPanel.swift
grep -Eq 'func setDockRendering' Sources/Panels/BrowserPanel.swift
./scripts/reload.sh --tag canvas-dockable
```

### 2.3 Register all 11 `DockableKind` factories at app startup

**Implementation Details**
- In the app's startup path (`Sources/AppDelegate.swift` `applicationDidFinishLaunching`
  or an existing bootstrap seam), call `DockableRegistry.shared.register(...)` for
  each of the 11 `DockableKind` cases, wiring `make` to the existing panel
  constructors (e.g. `TerminalPanel()`, `BrowserPanel()`, …).
- The `make` factory is FINAL in this phase (it is what Phase 3.3's
  `openNewCanvasPane(kind:)` consumes). The `decode` closure is registered here as a
  documented TRUE passthrough that IGNORES its `Data` argument and returns `make()`
  (an unhydrated default instance); it is a placeholder only. Phase 4.1 REPLACES each
  `decode` with a real payload codec. This is intentional and self-consistent:
  nothing in Phases 2–3 calls `decode` (session restore of the new `DockableSnapshot`
  format is first exercised in Phase 4.2), so Phase 2.3 has NO runtime dependency on
  Phase 4.1 — only the later, richer `decode` behavior does.
- `dependencies`: work items 1.3, 2.1. (No dependency on Phase 4 — the passthrough
  `decode` is complete and correct for the Phase 2–3 scope.)
- Failure modes: a missing `make` registration means `openNewCanvasPane(kind:)`
  (Phase 3) returns nil for that kind — guarded by AC-2.3.b enumerating all 11.

**Acceptance Criteria**
- AC-2.3.a: Startup registers a factory for every `DockableKind` case → a startup
  assertion / test enumerates `DockableKind.allCases` and asserts
  `DockableRegistry.shared.make(kind:)` is non-nil for each.
- AC-2.3.b: `DockableRegistry.shared.make(kind:)` returns non-nil for all 11 kinds
  after startup → test passes.
- AC-2.3.c: Full app build exits 0.

**Acceptance Tests**
- Test-2.3.a: Integration — `cmuxTests/DockableRegistrationTests.allKindsRegistered`
  runs startup registration then asserts non-nil `make` for every `DockableKind` case.

**Verification Commands**
```bash
cd apps/ghostty-dock
grep -Eq 'DockableRegistry.shared.register' Sources/AppDelegate.swift
./scripts/reload.sh --tag canvas-dockable
xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug -destination "platform=macOS" test -only-testing:cmuxTests/DockableRegistrationTests/allKindsRegistered
```

## Phase 3: Collapse `CanvasPaneContent` into one generic mount

**Purpose:** This is the core of the refactor and realizes "move/dock anything
anywhere." It can only run after Phase 2 because deleting the `.terminal`
special case is only safe once every object provides the general `Dockable`
path (and terminals/browsers provide their behavior as capabilities). Removing
the enum before universal conformance would break non-terminal mounting.

### 3.1 Rewrite `CanvasPaneContentMount` to drive `any Dockable`

**Implementation Details**
- Edit `Sources/Canvas/CanvasPaneContent.swift`: change
  `CanvasPaneContentMount` to hold `private let dockable: any Dockable` instead of
  `private let content: CanvasPaneContent`.
- Replace all six type-branch sites (attach/detach, constraint layout, terminal
  accessor, presentation update, occlusion vs visibility, unmount teardown) with
  protocol calls:
  - mount: `let view = dockable.makeDockContentView(context: ctx)`; if
    `let portal = dockable as? PortalHostable`, use `portal.detachContentFromPortal()`.
  - `setRendering(_:)` → `dockable.setDockRendering(_:)`.
  - `unmount()` → `dockable.tearDownDockMount()`; if `PortalHostable`,
    `portal.reattachContentToPortal(view)`.
- Remove the enum-pattern-match accessor `var terminalPanel: TerminalPanel?`
  (currently `if case .terminal(let panel, _) = content` at
  `Sources/Canvas/CanvasPaneContent.swift:115`). Replace every caller with a
  `(dockable as? any PortalHostable)`/`(mount.dockable as? TerminalPanel)` cast at
  the call site (audit callers via `grep -rn 'terminalPanel' Sources/`). No caller
  may depend on the deleted accessor.
- Keep conformance to `CanvasPaneContentMounting` (upstream `CmuxCanvasUI` seam) —
  its signatures are unchanged.
- Failure modes: a kind that needs rendering/teardown but relied on the old
  `.hosted` NSView lifecycle — covered by defaults in 1.2 and capability overrides in 2.2.

**Acceptance Criteria**
- AC-3.1.a: `CanvasPaneContentMount` stores `any Dockable` and contains no `switch`
  on `CanvasPaneContent` → the file exists AND grep confirms `any Dockable` AND no
  `case .terminal`/`case .hosted` remain (file-existence guarded so a moved/deleted
  file cannot vacuously pass).
- AC-3.1.b: The mount still conforms to `CanvasPaneContentMounting` → grep confirms.
- AC-3.1.c: The `var terminalPanel` enum-pattern accessor is gone →
  `! grep -rq 'if case .terminal' Sources/`. Full app build exits 0.

**Acceptance Tests**
- Test-3.1.a: Integration — full build succeeds with the enum-free mount.
- Test-3.1.b: Regression — UI repro (in PR): terminal, browser, and markdown panes
  each mount, render, and unmount correctly on the freeform canvas.

**Verification Commands**
```bash
cd apps/ghostty-dock
test -f Sources/Canvas/CanvasPaneContent.swift
grep -q 'any Dockable' Sources/Canvas/CanvasPaneContent.swift
test -f Sources/Canvas/CanvasPaneContent.swift && ! grep -Eq 'case \.(terminal|hosted)' Sources/Canvas/CanvasPaneContent.swift
grep -q 'CanvasPaneContentMounting' Sources/Canvas/CanvasPaneContent.swift
! grep -rq 'if case .terminal' Sources/
./scripts/reload.sh --tag canvas-dockable
```

### 3.2 Delete the `CanvasPaneContent` enum

**Implementation Details**
- Remove `enum CanvasPaneContent { case terminal(...) case hosted(...) }` from
  `Sources/Canvas/CanvasPaneContent.swift`.
- Update every constructor/caller that produced a `CanvasPaneContent` value to pass
  `any Dockable` directly (search Sources for `CanvasPaneContent.` and `.terminal(` /
  `.hosted(` construction sites).
- `dependencies`: work item 3.1.
- Failure modes: a stray caller still constructing the enum → compile error (caught
  by build) and by the grep invariant below.

**Acceptance Criteria**
- AC-3.2.a: `enum CanvasPaneContent` no longer exists anywhere under `Sources/` →
  `! grep -rq 'enum CanvasPaneContent' Sources/`.
- AC-3.2.b: No construction of `CanvasPaneContent` remains → `! grep -rq 'CanvasPaneContent\.' Sources/`.
- AC-3.2.c: Full app build exits 0.

**Acceptance Tests**
- Test-3.2.a: Integration — full build succeeds with the enum removed.
- Test-3.2.b: Regression — `cmuxTests` canvas/panel suites pass under Xcode test.

**Verification Commands**
```bash
cd apps/ghostty-dock
! grep -rq 'enum CanvasPaneContent' Sources/
! grep -rq 'CanvasPaneContent\.' Sources/
./scripts/reload.sh --tag canvas-dockable
```

### 3.3 Generalize `openNewCanvasPane` and delete `CanvasNewPaneType`

**Implementation Details**
- Edit `Sources/Canvas/Workspace+CanvasLayout.swift`: replace
  `func openNewCanvasPane(type: CanvasNewPaneType, …)` with
  `func openNewCanvasPane(kind: DockableKind, …)` that obtains the object via
  `DockableRegistry.shared.make(kind:)` (returning `nil` if unregistered) instead of
  the hardcoded `.terminal`/`.browser` switch.
- Delete `enum CanvasNewPaneType`.
- Update all call sites of `openNewCanvasPane(type:)` (search Sources) to pass a
  `DockableKind`; menu/command entries that offered only terminal/browser may now
  offer any kind (scope decision recorded in §5).
- `dependencies`: work items 2.3, 3.2.
- Failure modes: a call site passing an unregistered kind → `make` returns nil and
  `openNewCanvasPane` returns nil (no crash); asserted by AC-3.3.b.

**Acceptance Criteria**
- AC-3.3.a: `openNewCanvasPane(kind: DockableKind…)` exists and `enum CanvasNewPaneType`
  is gone → grep confirms both (`! grep -rq 'enum CanvasNewPaneType' Sources/`).
- AC-3.3.b: `openNewCanvasPane(kind:)` returns a pane for a registered kind (e.g.
  `.markdown`), demonstrating a non-terminal/non-browser object opens as a canvas
  pane → test passes.
- AC-3.3.c: Full app build exits 0.

**Acceptance Tests**
- Test-3.3.a: Integration — `cmuxTests/CanvasNewPaneTests.opensMarkdownPane` calls
  `openNewCanvasPane(kind: .markdown)` and asserts a pane with a `.markdown` Dockable
  is created (proves the generalization beyond terminal/browser).
- Test-3.3.b: Regression — opening terminal and browser panes still works.

**Verification Commands**
```bash
cd apps/ghostty-dock
grep -Eq 'func openNewCanvasPane\(\s*kind: *DockableKind' Sources/Canvas/Workspace+CanvasLayout.swift
! grep -rq 'enum CanvasNewPaneType' Sources/
./scripts/reload.sh --tag canvas-dockable
xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug -destination "platform=macOS" test -only-testing:cmuxTests/CanvasNewPaneTests/opensMarkdownPane
```

## Phase 4: Unify persistence on Dockable

**Purpose:** The runtime model must be unified (Phase 3) before the serialized
model is; this phase collapses the 11-optional-field snapshot into a
Dockable-driven snapshot and adds a legacy decoder so existing sessions restore.
It runs last among the code phases because rehydration depends on the
`DockableRegistry` and the generic mount produced earlier.

### 4.1 Add per-Dockable payload codecs

**Implementation Details**
- Add to `Dockable` (in `CmuxDockable`): `func encodeDockPayload() throws -> Data`
  WITH a protocol-extension DEFAULT returning empty `Data`. Decode is registry-driven
  (`DockableRegistry.decode`). The default means every conformer compiles; only
  stateful panels override.
- STATEFUL panels — the 9 that today have a `Session<Type>PanelSnapshot`: `terminal`,
  `browser`, `markdown`, `filePreview`, `rightSidebarTool`, `customSidebar`,
  `agentSession`, `project`, `workspaceTodo`. Each OVERRIDES `encodeDockPayload` by
  JSON-encoding its existing per-type snapshot struct, and REPLACES its Phase-2.3
  passthrough `decode` with one that JSON-decodes that struct and constructs the panel.
- CONTENT-LESS kinds — `extensionBrowser` and `cloudVMLoading` (verified: NO
  `SessionExtensionBrowserPanelSnapshot`/`SessionCloudVMLoadingPanelSnapshot` exists in
  `Sources/SessionPersistence.swift`). These use the default empty-`Data` payload and
  keep the passthrough `decode` (rehydrate via `make()`). If a later item finds
  `ExtensionBrowserPanel` needs an extension identifier persisted, add a minimal
  payload struct then (recorded in §5).
- All 11 kinds are thus explicitly accounted for (9 stateful + 2 content-less).
- `dependencies`: work items 1.3, 2.3.
- Failure modes: a panel whose payload fails to encode → `encodeDockPayload` throws
  and the snapshot writer logs+skips that pane (documented), never crashing restore.

**Acceptance Criteria**
- AC-4.1.a: `Dockable` declares `encodeDockPayload()` and each stateful panel implements
  it → grep confirms the protocol requirement and ≥1 panel implementation.
- AC-4.1.b: Encoding then decoding a panel's payload via the registry reproduces an
  equal panel snapshot → round-trip test passes.
- AC-4.1.c: `swift build --package-path Packages/macOS/CmuxDockable` exits 0 and full app build exits 0.

**Acceptance Tests**
- Test-4.1.a: Unit — `DockableRegistryTests.payloadRoundTripForStub` (package) round-trips a stub payload.
- Test-4.1.b: Integration — `cmuxTests/DockablePayloadTests.markdownPayloadRoundTrip`
  encodes a `MarkdownPanel` payload and decodes an equal one via the registry.

**Verification Commands**
```bash
cd apps/ghostty-dock
grep -Eq 'func encodeDockPayload' Packages/macOS/CmuxDockable/Sources/CmuxDockable/Dockable.swift
swift build --package-path Packages/macOS/CmuxDockable
./scripts/reload.sh --tag canvas-dockable
```

### 4.2 Replace `SessionPanelSnapshot` serialization with `DockableSnapshot`

**Implementation Details**
- Add `struct DockableSnapshot: Codable, Sendable { var id: UUID; var kind: DockableKind; var payload: Data }`
  in `CmuxDockable` (RESOLVED — not `Sources/SessionPersistence.swift`). Because
  `payload` is opaque `Data`, `CmuxDockable` imports NONE of the app's session types,
  so there is no dependency cycle (app → CmuxDockable, never the reverse). The save
  path in `Sources/SessionPersistence.swift` imports `CmuxDockable` and USES the type.
- Change the canvas/session save path (`Sources/SessionPersistence.swift`,
  `Sources/Canvas/Workspace+CanvasLayout.swift` `canvasSessionPaneSnapshots()`) to
  write `DockableSnapshot` produced from each pane's `any Dockable`
  (`id`, `dockableKind`, `encodeDockPayload()`).
- Change the restore path to rehydrate each pane via
  `DockableRegistry.shared.decode(kind:payload:)`.
- The 11-optional-field `SessionPanelSnapshot` struct remains ONLY as a legacy
  decode input (handled in 4.3); new writes use `DockableSnapshot`.
- `dependencies`: work items 3.3, 4.1.
- Failure modes: an unregistered kind on restore → `decode` returns nil, that pane is
  skipped with a log (session still restores the rest).

**Acceptance Criteria**
- AC-4.2.a: The save path emits `DockableSnapshot` values → grep confirms `DockableSnapshot`
  usage in `Sources/SessionPersistence.swift`.
- AC-4.2.b: Save→restore of a live session with terminal + browser + markdown panes
  reproduces the same three panes (ids, kinds) → round-trip test passes.
- AC-4.2.c: Full app build exits 0.

**Acceptance Tests**
- Test-4.2.a: Integration — `cmuxTests/DockableSnapshotTests.saveRestoreRoundTrip`
  builds a canvas with 3 kinds, serializes, restores, and asserts pane id/kind parity.

**Verification Commands**
```bash
cd apps/ghostty-dock
grep -q 'DockableSnapshot' Sources/SessionPersistence.swift
./scripts/reload.sh --tag canvas-dockable
xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug -destination "platform=macOS" test -only-testing:cmuxTests/DockableSnapshotTests
```

### 4.3 Backward-compatible decode of legacy `SessionPanelSnapshot`

**Implementation Details**
- In the restore path, when a stored snapshot is in the legacy shape (11 optional
  per-type fields — detect by decoding `SessionPanelSnapshot` and reading the non-nil
  field / `type`), map it to a `DockableSnapshot` (kind from `type`; payload = JSON of
  the matching non-nil per-type sub-snapshot) and rehydrate via the registry.
- Add a committed fixture `cmuxTests/fixtures/legacy-session-panel.json` capturing a
  pre-refactor `SessionPanelSnapshot` for a terminal + a markdown panel.
- `dependencies`: work item 4.2.
- Failure modes: a legacy field combination not covered → log + skip that pane;
  restore of the remaining panes must still succeed (asserted).

**Acceptance Criteria**
- AC-4.3.a: A stored legacy `SessionPanelSnapshot` fixture restores into the correct
  `DockableKind` panes → test passes.
- AC-4.3.b: Restoring a session file containing BOTH legacy and new snapshots yields
  all panes → test passes.
- AC-4.3.c: Full app build exits 0 and the migration test target passes.

**Acceptance Tests**
- Test-4.3.a: Integration — `cmuxTests/LegacySnapshotMigrationTests.decodesLegacyTerminalAndMarkdown`
  loads `cmuxTests/fixtures/legacy-session-panel.json` and asserts a `.terminal` and a
  `.markdown` Dockable are produced.
- Test-4.3.b: Regression — mixed legacy+new session restores all panes.

**Verification Commands**
```bash
cd apps/ghostty-dock
test -f cmuxTests/fixtures/legacy-session-panel.json
./scripts/reload.sh --tag canvas-dockable
xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug -destination "platform=macOS" test -only-testing:cmuxTests/LegacySnapshotMigrationTests
```

## Phase 5: Confirm fork-only landing surface and rebase safety

**Purpose:** The landing/rebase guarantee can only be asserted against the final
diff, so it runs last. This refactor must leave upstream-owned canvas code
untouched; this phase proves the entire change is fork-only and the fork stays
cleanly rebasable on `manaflow-ai/cmux`, and it records the (empty) upstream-PR set.

### 5.1 Assert zero upstream-owned canvas files were modified

**Implementation Details**
- The upstream-owned canvas surface is `Packages/macOS/CmuxCanvas/Sources/**` and
  `Packages/macOS/CmuxCanvasUI/Sources/**` (content-agnostic geometry + mount seam).
  This refactor must NOT modify any file there — all changes live in the new
  `Packages/macOS/CmuxDockable` package and app `Sources/` (fork-only).
- Compute the task diff file set against the fork's merge base with `origin/main`
  and assert it contains no upstream-owned canvas source path.
- Failure modes: any change under the upstream paths fails the guard — the fix is to
  relocate the change into `CmuxDockable` or app `Sources/`, never to modify upstream.

**Acceptance Criteria**
- AC-5.1.a: `git diff --name-only origin/main..HEAD` (TWO-dot: commits on HEAD not in
  origin/main — the branch's own changes; rebase onto origin/main first so the base is
  current) contains no path matching `Packages/macOS/CmuxCanvas(UI)?/Sources` → guard
  exits 0.
- AC-5.1.b: The new package `Packages/macOS/CmuxDockable` IS present in the diff →
  grep confirms (positive control that the refactor landed there).
- AC-5.1.c: No cyclic Swift package dependency was introduced by adding the
  `CmuxDockable` dependency → a clean build emits no `cyclic`/`circular` dependency
  diagnostic.

**Acceptance Tests**
- Test-5.1.a: Regression — the diff-scope guard (below) exits 0 on the finished branch.
- Test-5.1.b: Regression — `swift build --package-path Packages/macOS/CmuxCanvas` and
  `Packages/macOS/CmuxCanvasUI` still build unchanged.
- Test-5.1.c: Regression — the dependency-cycle guard (below) exits 0.

**Verification Commands**
```bash
cd apps/ghostty-dock
git fetch origin
git rebase origin/main
! git diff --name-only origin/main..HEAD | grep -E 'Packages/macOS/CmuxCanvas(UI)?/Sources'
git diff --name-only origin/main..HEAD | grep -q 'Packages/macOS/CmuxDockable/'
swift build --package-path Packages/macOS/CmuxCanvas
swift build --package-path Packages/macOS/CmuxCanvasUI
! swift build --package-path Packages/macOS/CmuxDockable 2>&1 | grep -Eiq 'cyclic|circular'
```

### 5.2 Green build + tests on the finished tree; changelog note

**Implementation Details**
- Run the full package test suites and the full app build on the completed branch.
- Add a changelog/docs entry describing the Dockable unification (per PR template
  checklist "I updated docs/changelog if needed").
- `dependencies`: work item 5.1.
- Failure modes: any red test blocks landing.

**Acceptance Criteria**
- AC-5.2.a: `swift test --package-path Packages/macOS/CmuxDockable` and
  `swift test --package-path Packages/macOS/CmuxCanvas` exit 0.
- AC-5.2.b: Full app build exits 0.
- AC-5.2.c: The repo-root `CHANGELOG.md` (which exists) contains a "Dockable" entry →
  grep on `CHANGELOG.md` specifically confirms (not any `.md`, so the PRD itself
  cannot satisfy it).

**Acceptance Tests**
- Test-5.2.a: Integration — full package test suites pass.
- Test-5.2.b: Integration — full app build passes.

**Verification Commands**
```bash
cd apps/ghostty-dock
swift test --package-path Packages/macOS/CmuxDockable
swift test --package-path Packages/macOS/CmuxCanvas
./scripts/reload.sh --tag canvas-dockable
test -f CHANGELOG.md && grep -iq 'Dockable' CHANGELOG.md
```

## 3. Completion Criteria

- A single `Dockable` protocol (in `Packages/macOS/CmuxDockable`) is the common
  type for all 11 visible object kinds; `PortalHostable` and `setDockRendering`
  carry the only content-specific behavior, as opt-in capabilities.
- `enum CanvasPaneContent` and `enum CanvasNewPaneType` no longer exist anywhere
  under `Sources/`; `CanvasPaneContentMount` drives `any Dockable` with no
  type-switch; `openNewCanvasPane(kind: DockableKind)` can open any registered kind.
- Session persistence uses `DockableSnapshot`; pre-refactor sessions restore via the
  legacy decoder; a save→restore round trip of 3 distinct kinds preserves panes.
- The entire diff is fork-only: no `CmuxCanvas`/`CmuxCanvasUI` source modified; the
  fork remains rebasable on `manaflow-ai/cmux`.
- All Verification Commands across Phases 1–5 exit 0; the full app builds.

## 4. Rollout & Validation

### Rollout Strategy
- Land as a single fork-only branch (`task/<hash>-cmux-canvas-dockable-refactor`),
  merged after all phase Verification Commands pass and bot reviews are resolved
  (per the repo PR template).
- No user-facing feature flag is required: the refactor is behavior-preserving. If
  desired during bring-up, gate the newly-enabled "open any kind as a canvas pane"
  menu entries (Phase 3.3) behind an existing settings/debug toggle; rollback =
  revert the branch (self-contained; upstream untouched).
- Rollback trigger: any regression in terminal portal mounting, browser visibility,
  or session restore of an existing session.

### Post-Launch Validation
- Session restore success rate for pre-refactor sessions (no dropped panes).
- Manual matrix: for each of the 11 kinds, open as a canvas pane, move/split between
  panes, move to a new window/workspace, quit, relaunch — object survives in place.
- No crash reports referencing `DockableRegistry.make` returning nil for a
  user-openable kind.

## 5. Open Questions

- Decision: Common type is a **protocol** (`Dockable`), not a base class — chose a
  protocol because Swift favors protocol-oriented composition, panels are already
  a `protocol Panel` with heterogeneous storage (AppKit + SwiftUI + web), and a
  shared base class would force an unnatural inheritance hierarchy across
  `NSHostingView`/AppKit/GhosttyKit-backed views.
- Decision: The abstraction lives in a **new fork-only SPM package**
  `Packages/macOS/CmuxDockable` (not in app `Sources/` and not in upstream
  `CmuxCanvas`) — chose this for `swift test` verifiability and to keep the upstream
  canvas rebasable (all coupling stays fork-side). Matches the user's stated
  preference for the cleaner-separation option.
- Decision: `DockableKind` mirrors the existing 11 `PanelType` cases rather than
  introducing a new taxonomy — chose parity to make the migration mechanical and the
  legacy-snapshot mapping 1:1; a future item may prune content-less kinds
  (`cloudVMLoading`).
- Decision: All work items are **fork-only**; the upstream-PR set is empty — chose
  this because the content-kind coupling exists solely in fork-owned files
  (`Sources/Canvas/CanvasPaneContent.swift`, `Sources/Panels/*`) and the upstream
  `CanvasPaneContentMounting` seam plus `CanvasLayout`/`CanvasPane` models are
  already content-agnostic (verified: the package "never sees panel types").
- Open: Should Phase 3.3 immediately expose "open any of the 11 kinds" in the
  new-pane UI, or keep the visible menu to terminal/browser/markdown initially and
  enable the rest behind a debug toggle? (Does not block Phase 1–2; resolve during
  Phase 3 UI wiring.)
- Decision: `DockableSnapshot` lives in `CmuxDockable` with `payload: Data` (opaque) —
  chose this because an opaque `Data` payload means the package imports none of the
  app's session types, so no dependency cycle is possible (app → CmuxDockable only).
  Resolved at authoring time; Phase 4.2 implements it, Phase 5.1 guards against cycles.
- Open: Does `ExtensionBrowserPanel` need any state persisted (e.g. extension id / URL)?
  Currently treated as content-less (no existing `Session…Snapshot`), so its payload is
  empty. If restore must reopen the same extension, Phase 4.1 adds a minimal payload
  struct. Does not block Phases 1–3.
