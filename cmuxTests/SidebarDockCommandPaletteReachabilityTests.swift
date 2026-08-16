import AppKit
import Bonsplit
import Combine
import CmuxCommandPalette
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
private final class PaletteRailPanel: Panel {
    let objectWillChange = ObservableObjectPublisher()
    let id = UUID()
    let stableSurfaceIdentity = PanelStableSurfaceIdentity()
    let panelType: PanelType = .rightSidebarTool
    let displayTitle: String
    let displayIcon: String? = "folder"
    let isDirty = false

    init(_ title: String) { displayTitle = title }
    func close() {}
    func focus() {}
    func unfocus() {}
    func triggerFlash(reason: WorkspaceAttentionFlashReason) { _ = reason }
}

/// VAL-RAIL-001/003 public palette reachability: query → production registry
/// result ids → registered handler mutation (not store/invoker-direct dogfood).
@MainActor
@Suite("SidebarDock command palette reachability", .serialized)
struct SidebarDockCommandPaletteReachabilityTests {
    private func multiTabRightTarget() throws -> (SidebarDockStore, SidebarDockActionInvoker.Target, [TabID]) {
        let store = SidebarDockStore(edge: .right, windowId: UUID(), collapsedSectionHeight: 28)
        store.updateRailContentHeight(800)
        var tabs: [TabID] = []
        for title in ["Files", "Find", "Vault"] {
            let panel = PaletteRailPanel(title)
            let tab = try #require(store.attachPanel(panel))
            tabs.append(tab)
        }
        #expect(store.sectionCount == 1)
        let paneId = try #require(store.orderedSectionPaneIds().first)
        let target = SidebarDockActionInvoker.Target(
            store: store,
            tabId: tabs[0],
            paneId: paneId
        )
        return (store, target, tabs)
    }

    @Test func flagOffAndMissingTargetKeepDockCommandsUnavailable() throws {
        let (_, target, _) = try multiTabRightTarget()
        for commandId in SidebarDockCommand.allCommandIds {
            #expect(
                ContentView.sidebarDockPaletteCommandIsAvailable(
                    commandId,
                    flagEnabled: false,
                    target: target
                ) == false,
                "Flag-off must hide \(commandId)"
            )
            #expect(
                ContentView.sidebarDockPaletteCommandIsAvailable(
                    commandId,
                    flagEnabled: true,
                    target: nil
                ) == false,
                "Missing rail target must hide \(commandId)"
            )
        }
    }

    @Test func eligibleTargetSurfacesCollapseAndNewSectionInRegistryQuery() throws {
        let (store, target, _) = try multiTabRightTarget()
        #expect(
            ContentView.sidebarDockPaletteCommandIsAvailable(
                SidebarDockCommand.collapseSection,
                flagEnabled: true,
                target: target
            ),
            "Collapse must be available for an expanded sole section"
        )
        #expect(
            ContentView.sidebarDockPaletteCommandIsAvailable(
                SidebarDockCommand.moveTabToNewSectionBottom,
                flagEnabled: true,
                target: target
            ),
            "Move-to-new-section must be available when geometry allows"
        )

        let collapseHits = ContentView.sidebarDockPaletteRegistryResults(
            query: "collapse section",
            flagEnabled: true,
            target: target,
            limit: 20
        )
        #expect(
            collapseHits.contains { $0.commandId == SidebarDockCommand.collapseSection },
            "Production registry query must return collapse command id; got \(collapseHits.map(\.commandId))"
        )

        let sectionHits = ContentView.sidebarDockPaletteRegistryResults(
            query: "new section below",
            flagEnabled: true,
            target: target,
            limit: 20
        )
        #expect(
            sectionHits.contains { $0.commandId == SidebarDockCommand.moveTabToNewSectionBottom },
            "Production registry query must return move-bottom command id; got \(sectionHits.map(\.commandId))"
        )

        // Wrong context still empty.
        let flagOffHits = ContentView.sidebarDockPaletteRegistryResults(
            query: "collapse section",
            flagEnabled: false,
            target: target,
            limit: 20
        )
        #expect(flagOffHits.isEmpty)
        _ = store
    }

    @Test func registeredHandlerExecutionCollapsesFocusedSection() throws {
        let (store, target, _) = try multiTabRightTarget()
        #expect(!store.isSoleSectionCollapsed)

        let hits = ContentView.sidebarDockPaletteRegistryResults(
            query: "collapse",
            flagEnabled: true,
            target: target,
            limit: 10
        )
        let collapse = try #require(
            hits.first(where: { $0.commandId == SidebarDockCommand.collapseSection })
        )

        // Handler factory must be the registered-handler shape (returns Bool),
        // not a direct store/invoker call from the test or dogfood method.
        let handler = ContentView.sidebarDockPaletteRegisteredHandler(
            commandId: collapse.commandId,
            store: store,
            tabId: target.tabId,
            paneId: target.paneId
        )
        #expect(handler() == true)
        #expect(store.isSoleSectionCollapsed)

        let expandHits = ContentView.sidebarDockPaletteRegistryResults(
            query: "expand",
            flagEnabled: true,
            target: SidebarDockActionInvoker.Target(
                store: store,
                tabId: target.tabId,
                paneId: target.paneId
            ),
            limit: 10
        )
        let expand = try #require(
            expandHits.first(where: { $0.commandId == SidebarDockCommand.expandSection })
        )
        let expandHandler = ContentView.sidebarDockPaletteRegisteredHandler(
            commandId: expand.commandId,
            store: store,
            tabId: target.tabId,
            paneId: target.paneId
        )
        #expect(expandHandler() == true)
        #expect(!store.isSoleSectionCollapsed)
    }

    @Test func contributionsBindWhenToWindowScopedAvailabilityPredicate() {
        let contributions = ContentView.commandPaletteSidebarDockCommandContributions(
            windowId: UUID()
        )
        #expect(contributions.count == SidebarDockCommand.allCommandIds.count)
        let ids = Set(contributions.map(\.commandId))
        for commandId in SidebarDockCommand.allCommandIds {
            #expect(ids.contains(commandId))
        }
        // Descriptors always publish; live `when` still gates flag/target.
        // With no live app registry, window-scoped when must stay false.
        let context = CommandPaletteContextSnapshot()
        for contribution in contributions {
            #expect(
                contribution.when(context) == false
                    || RightSidebarBetaFeatureSettings.isSidebarDockEnabled(),
                "\(contribution.commandId) when must not be unconditionally true"
            )
        }
    }

    @Test func debugCommandPaletteQueryRunIsRegisteredInDebugCatalog() throws {
#if DEBUG
        #expect(
            TerminalController.v2DebugMethodNames.contains("debug.command_palette.query_run"),
            "DEBUG dogfood method must live under debug.command_palette.*"
        )
        #expect(
            TerminalController.commandPaletteDebugQueryRunMethodName
                == "debug.command_palette.query_run"
        )
#else
        #expect(Bool(true))
#endif
    }

    @Test func debugQueryRunSourceRoutesThroughRegisteredHandlerNotInvokerDirect() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let debugURL = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("TerminalController+ControlDebugContext.swift")
        let source = try String(contentsOf: debugURL, encoding: .utf8)
        #expect(source.contains("debug.command_palette.query_run") || source.contains("controlDebugCommandPaletteQueryRun"))
        #expect(source.contains("sidebarDockPaletteRegisteredHandler") || source.contains("sidebarDockPaletteRegistryResults"))
        // Must not short-circuit dogfood execute via store/invoker-only path.
        #expect(!source.contains("SidebarDockActionInvoker.performFocused"))
    }
}
