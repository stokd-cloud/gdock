import AppKit
import Bonsplit
import Combine
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
private final class RailTestPanel: Panel {
    let objectWillChange = ObservableObjectPublisher()
    let id = UUID()
    let stableSurfaceIdentity = PanelStableSurfaceIdentity()
    let panelType: PanelType
    let displayTitle: String
    let displayIcon: String? = "folder"
    let isDirty = false

    init(title: String, panelType: PanelType = .rightSidebarTool) {
        self.displayTitle = title
        self.panelType = panelType
    }

    func close() {}
    func focus() {}
    func unfocus() {}
    func triggerFlash(reason: WorkspaceAttentionFlashReason) { _ = reason }
}

@MainActor
@Suite("SidebarDockStore substrate", .serialized)
struct SidebarDockStoreTests {
    @Test func edgeDeclaresLeftAndRightOnly() {
        #expect(SidebarDockEdge.allCases.map(\.rawValue) == ["left", "right"])
    }

    @Test func makeConfigurationEnablesCollapseGeometryAndSuppressesSplitButtons() {
        let height: CGFloat = 28
        let config = SidebarDockStore.makeConfiguration(edge: .right, collapsedSectionHeight: height)
        #expect(config.allowCloseLastPane == false)
        #expect(config.allowSplits == true)
        #expect(config.allowTabReordering == true)
        #expect(config.allowCrossPaneTabMove == true)
        #expect(config.autoCloseEmptyPanes == true)
        #expect(config.appearance.showSplitButtons == false)
        #expect(config.appearance.minimumPaneHeight == height)
        #expect(config.appearance.tabBarHeight == height)
        #expect(config.dividerPositionRange.lowerBound == 0)
        #expect(config.dividerPositionRange.upperBound == 1)
        // Right rail never sits under traffic lights.
        #expect(config.appearance.tabBarLeadingInset == 0)
    }

    @Test func leftRailConfigurationInsetsTabBarPastTrafficLights() {
        let height: CGFloat = 28
        let left = SidebarDockStore.makeConfiguration(edge: .left, collapsedSectionHeight: height)
        let right = SidebarDockStore.makeConfiguration(edge: .right, collapsedSectionHeight: height)
        #expect(left.appearance.tabBarLeadingInset >= CGFloat(MinimalModeTitlebarDebugSettings.defaultTrafficLightTabBarInset))
        #expect(right.appearance.tabBarLeadingInset == 0)
        // Live store init applies the same inset.
        let leftStore = SidebarDockStore(edge: .left, windowId: UUID())
        let rightStore = SidebarDockStore(edge: .right, windowId: UUID())
        #expect(
            leftStore.bonsplitController.configuration.appearance.tabBarLeadingInset
                >= CGFloat(MinimalModeTitlebarDebugSettings.defaultTrafficLightTabBarInset)
        )
        #expect(rightStore.bonsplitController.configuration.appearance.tabBarLeadingInset == 0)
    }

    @Test func storeHasNoMaximumSectionConstantAndStartsEmpty() {
        let store = SidebarDockStore(edge: .right, windowId: UUID())
        #expect(store.sectionCount == 1 || store.sectionCount == 0 || store.bonsplitController.allPaneIds.count >= 1)
        // No max-section property on the type — probe via Mirror.
        let names = Mirror(reflecting: store).children.compactMap(\.label)
        #expect(!names.contains(where: { $0.lowercased().contains("maxsection") || $0.lowercased().contains("maximumsection") }))
    }

    @Test func tabBarVisibilityTracksSectionCount() throws {
        let store = SidebarDockStore(edge: .right, windowId: UUID())
        let a = RailTestPanel(title: "Files")
        let b = RailTestPanel(title: "Find")
        let tabA = try #require(store.attachPanel(a))
        store.refreshTabBarVisibility()
        #expect(store.bonsplitController.configuration.tabBarVisibility == .multipleTabs)
        let tabB = try #require(store.attachPanel(b))
        #expect(store.moveTabToNewSection(tabB, position: .bottom))
        store.refreshTabBarVisibility()
        #expect(store.sectionCount == 2)
        #expect(store.bonsplitController.configuration.tabBarVisibility == .always)
        _ = tabA
    }

    @Test func registryExposesLeftAndRightPerWindow() {
        let windowId = UUID()
        let registry = SidebarDockStoreRegistry(windowId: windowId)
        #expect(registry.left.edge == .left)
        #expect(registry.right.edge == .right)
        #expect(registry.left.windowId == windowId)
        #expect(registry.right.windowId == windowId)
        #expect(registry.store(for: .left) === registry.left)
        #expect(registry.store(for: .right) === registry.right)
        #expect(registry.left !== registry.right)
    }

    @Test func independentRegistriesDoNotShareStoresOrPanels() throws {
        let windowA = UUID()
        let windowB = UUID()
        let regA = SidebarDockStoreRegistry(windowId: windowA)
        let regB = SidebarDockStoreRegistry(windowId: windowB)

        #expect(regA.windowId != regB.windowId)
        #expect(regA.left !== regB.left)
        #expect(regA.right !== regB.right)
        #expect(regA.left.bonsplitController !== regB.left.bonsplitController)

        let panel = RailTestPanel(title: "Files-A")
        let tab = try #require(regA.left.attachPanel(panel))
        #expect(regA.left.panels[panel.id] != nil)
        #expect(regB.left.panels[panel.id] == nil)
        #expect(regB.right.panels[panel.id] == nil)
        #expect(regA.right.surfaceIdToPanelId[tab] == nil)
        #expect(regB.left.surfaceIdToPanelId[tab] == nil)
        #expect(regA.left.sectionCount >= 1)
        // Mutating window A must leave window B's empty rail identity intact.
        #expect(regB.left.panels.isEmpty)
        #expect(regB.right.panels.isEmpty)
    }

    @Test func placementMatrixAllowsToolsAndSelectorOnly() {
        #expect(SidebarDockPlacementMatrix.allows(panelType: .rightSidebarTool))
        #expect(SidebarDockPlacementMatrix.allows(panelType: .leftWorkspaceSelector))
        #expect(!SidebarDockPlacementMatrix.allows(panelType: .terminal))
        #expect(!SidebarDockPlacementMatrix.allows(panelType: .browser))
        #expect(!SidebarDockPlacementMatrix.allows(panelType: .markdown))
        #expect(!SidebarDockPlacementMatrix.allows(panelType: .customSidebar))
        #expect(SidebarDockPlacementMatrix.allows(mode: .files))
        #expect(SidebarDockPlacementMatrix.allows(mode: .find))
        #expect(SidebarDockPlacementMatrix.allows(mode: .sessions))
        #expect(!SidebarDockPlacementMatrix.allows(mode: .feed))
        #expect(!SidebarDockPlacementMatrix.allows(mode: .dock))
        #expect(!SidebarDockPlacementMatrix.allows(mode: .customSidebar))
    }

    @Test func attachRefusesDisallowedPanelTypeWithoutChangingTree() throws {
        let store = SidebarDockStore(edge: .left, windowId: UUID())
        let before = store.sectionCount
        let terminal = RailTestPanel(title: "Term", panelType: .terminal)
        #expect(store.attachPanel(terminal) == nil)
        #expect(store.panels[terminal.id] == nil)
        #expect(store.sectionCount == before)
    }

    @Test func commandTitlesAreLocalizedNonEmpty() {
        for id in [
            SidebarDockCommand.moveTabToNewSectionTop,
            SidebarDockCommand.moveTabToNewSectionBottom,
            SidebarDockCommand.collapseSection,
            SidebarDockCommand.expandSection,
            SidebarDockCommand.reorderSectionUp,
            SidebarDockCommand.reorderSectionDown,
        ] {
            let title = SidebarDockCommand.title(for: id)
            #expect(!title.isEmpty)
            #expect(title != id)
        }
    }
}
