import Bonsplit
import Foundation

/// Shared command identifiers and mutation path for rail context menus and the command palette.
enum SidebarDockCommand {
    static let showStokdWork = "palette.gdock.showStokdWork"
    static let moveTabToNewSectionTop = "sidebarDock.moveTabToNewSection.top"
    static let moveTabToNewSectionBottom = "sidebarDock.moveTabToNewSection.bottom"
    static let collapseSection = "sidebarDock.section.collapse"
    static let expandSection = "sidebarDock.section.expand"
    static let reorderSectionUp = "sidebarDock.section.reorderUp"
    static let reorderSectionDown = "sidebarDock.section.reorderDown"
    /// Cross-rail tab: into the other rail's selected/focused section.
    static let moveTabToOtherRailSelected = "sidebarDock.moveTabToOtherRail.selected"
    /// Cross-rail tab: new vertical section at top of the other rail.
    static let moveTabToOtherRailTop = "sidebarDock.moveTabToOtherRail.top"
    /// Cross-rail tab: new vertical section at bottom of the other rail.
    static let moveTabToOtherRailBottom = "sidebarDock.moveTabToOtherRail.bottom"
    /// Cross-rail whole section → other rail top.
    static let moveSectionToOtherRailTop = "sidebarDock.moveSectionToOtherRail.top"
    /// Cross-rail whole section → other rail bottom.
    static let moveSectionToOtherRailBottom = "sidebarDock.moveSectionToOtherRail.bottom"

    /// Every actor-facing rail command id (palette, context menu, header controls).
    static let allCommandIds: [String] = [
        moveTabToNewSectionTop,
        moveTabToNewSectionBottom,
        collapseSection,
        expandSection,
        reorderSectionUp,
        reorderSectionDown,
        moveTabToOtherRailSelected,
        moveTabToOtherRailTop,
        moveTabToOtherRailBottom,
        moveSectionToOtherRailTop,
        moveSectionToOtherRailBottom,
    ]

    /// Localized titles for palette / context menu (en default; ja in catalog).
    static func title(for commandId: String) -> String {
        switch commandId {
        case moveTabToNewSectionTop:
            return String(localized: "sidebarDock.moveToNewSection.top", defaultValue: "Move Tab to New Section Above")
        case moveTabToNewSectionBottom:
            return String(localized: "sidebarDock.moveToNewSection.bottom", defaultValue: "Move Tab to New Section Below")
        case collapseSection:
            return String(localized: "sidebarDock.section.collapse", defaultValue: "Collapse Section")
        case expandSection:
            return String(localized: "sidebarDock.section.expand", defaultValue: "Expand")
        case reorderSectionUp:
            return String(localized: "sidebarDock.section.reorderUp", defaultValue: "Move Section Up")
        case reorderSectionDown:
            return String(localized: "sidebarDock.section.reorderDown", defaultValue: "Move Section Down")
        case moveTabToOtherRailSelected:
            return String(localized: "sidebarDock.moveTabToOtherRail.selected", defaultValue: "Move Tab to Other Rail")
        case moveTabToOtherRailTop:
            return String(localized: "sidebarDock.moveTabToOtherRail.top", defaultValue: "Move Tab to Other Rail (New Section Above)")
        case moveTabToOtherRailBottom:
            return String(localized: "sidebarDock.moveTabToOtherRail.bottom", defaultValue: "Move Tab to Other Rail (New Section Below)")
        case moveSectionToOtherRailTop:
            return String(localized: "sidebarDock.moveSectionToOtherRail.top", defaultValue: "Move Section to Other Rail (Top)")
        case moveSectionToOtherRailBottom:
            return String(localized: "sidebarDock.moveSectionToOtherRail.bottom", defaultValue: "Move Section to Other Rail (Bottom)")
        default:
            return commandId
        }
    }

    /// Palette / menu group subtitle for rail section commands.
    static var commandGroupSubtitle: String {
        String(localized: "sidebarDock.command.subtitle", defaultValue: "Sidebar Dock")
    }

    /// Live eligibility for actor surfaces. Unsafe actions stay unavailable.
    struct Eligibility: Equatable, Sendable {
        var canMoveTabToNewSectionTop: Bool
        var canMoveTabToNewSectionBottom: Bool
        var canCollapse: Bool
        var canExpand: Bool
        var canReorderUp: Bool
        var canReorderDown: Bool
        var canMoveTabToOtherRail: Bool
        var canMoveSectionToOtherRail: Bool

        static let none = Eligibility(
            canMoveTabToNewSectionTop: false,
            canMoveTabToNewSectionBottom: false,
            canCollapse: false,
            canExpand: false,
            canReorderUp: false,
            canReorderDown: false,
            canMoveTabToOtherRail: false,
            canMoveSectionToOtherRail: false
        )

        func isAvailable(_ commandId: String) -> Bool {
            switch commandId {
            case SidebarDockCommand.moveTabToNewSectionTop: return canMoveTabToNewSectionTop
            case SidebarDockCommand.moveTabToNewSectionBottom: return canMoveTabToNewSectionBottom
            case SidebarDockCommand.collapseSection: return canCollapse
            case SidebarDockCommand.expandSection: return canExpand
            case SidebarDockCommand.reorderSectionUp: return canReorderUp
            case SidebarDockCommand.reorderSectionDown: return canReorderDown
            case SidebarDockCommand.moveTabToOtherRailSelected,
                 SidebarDockCommand.moveTabToOtherRailTop,
                 SidebarDockCommand.moveTabToOtherRailBottom:
                return canMoveTabToOtherRail
            case SidebarDockCommand.moveSectionToOtherRailTop,
                 SidebarDockCommand.moveSectionToOtherRailBottom:
                return canMoveSectionToOtherRail
            default: return false
            }
        }

        var availableCommandIds: [String] {
            SidebarDockCommand.allCommandIds.filter { isAvailable($0) }
        }
    }

    /// Immutable menu row for section context menus and focused-section chrome.
    struct MenuItem: Equatable, Identifiable, Sendable {
        let id: String
        let title: String
        let isEnabled: Bool
    }

    /// Evaluate live eligibility for a focused rail tab/pane without a second selection store.
    @MainActor
    static func eligibility(
        store: SidebarDockStore,
        tabId: TabID?,
        paneId: PaneID?
    ) -> Eligibility {
        let panes = store.orderedSectionPaneIds()
        let resolvedPane: PaneID? = {
            if let paneId { return paneId }
            if let tabId { return store.paneId(forTabId: tabId) }
            return store.bonsplitController.focusedPaneId ?? panes.first
        }()
        let resolvedTab: TabID? = {
            if let tabId { return tabId }
            guard let resolvedPane else { return nil }
            return store.bonsplitController.selectedTab(inPane: resolvedPane)?.id
                ?? store.bonsplitController.tabs(inPane: resolvedPane).first?.id
        }()

        let geometryAllows = store.configurationAllowsNewSection()
        let canMove: Bool = {
            guard let resolvedTab else { return false }
            guard store.surfaceIdToPanelId[resolvedTab] != nil else { return false }
            // Net section growth needs a live multi-tab source (VAL-RAIL-003/007).
            // Sole-tab create would leave Empty placeholders or only relocate.
            guard let pane = store.paneId(forTabId: resolvedTab) else { return false }
            guard store.bonsplitController.tabs(inPane: pane).count > 1 else { return false }
            // Moving a tab into a new section never empties the rail — it stays on this edge.
            return geometryAllows
        }()

        let paneIndex = resolvedPane.flatMap { pane in
            panes.firstIndex(where: { $0.id == pane.id })
        }
        let isCollapsed: Bool = {
            if store.sectionCount == 1 { return store.isSoleSectionCollapsed }
            guard let resolvedPane else { return false }
            return store.isSectionCollapsed(paneId: resolvedPane)
        }()

        // Cross-rail: refuse final-rail-empty and disallowed panels.
        let canCrossRailTab: Bool = {
            guard let resolvedTab,
                  let panelId = store.surfaceIdToPanelId[resolvedTab],
                  let panel = store.panels[panelId] else {
                return false
            }
            let destEdge: SidebarDockEdge = store.edge == .left ? .right : .left
            guard SidebarDockPlacementMatrix.allows(panel: panel, on: destEdge) else {
                return false
            }
            return !store.wouldEmptyRail(removing: resolvedTab)
        }()
        let canCrossRailSection: Bool = {
            guard let resolvedPane else { return false }
            let sid = store.sectionId(forPane: resolvedPane)
            return !store.wouldEmptyRail(removingSection: sid)
        }()

        return Eligibility(
            canMoveTabToNewSectionTop: canMove,
            canMoveTabToNewSectionBottom: canMove,
            canCollapse: resolvedPane != nil && !isCollapsed && store.sectionCount >= 1,
            canExpand: resolvedPane != nil && isCollapsed,
            canReorderUp: store.sectionCount >= 2 && (paneIndex ?? 0) > 0,
            canReorderDown: store.sectionCount >= 2
                && paneIndex.map { $0 + 1 < panes.count } == true,
            canMoveTabToOtherRail: canCrossRailTab,
            canMoveSectionToOtherRail: canCrossRailSection
        )
    }

    /// Section-level context menu / header control items for the focused pane.
    @MainActor
    static func sectionMenuItems(
        store: SidebarDockStore,
        paneId: PaneID?
    ) -> [MenuItem] {
        let eligibility = eligibility(store: store, tabId: nil, paneId: paneId)
        let sectionCommands = [
            collapseSection,
            expandSection,
            reorderSectionUp,
            reorderSectionDown,
            moveSectionToOtherRailTop,
            moveSectionToOtherRailBottom,
        ]
        return sectionCommands.compactMap { commandId in
            let enabled = eligibility.isAvailable(commandId)
            // Hide expand when not collapsed and collapse when already collapsed so
            // the menu stays short; keep reorder rows disabled rather than hidden.
            switch commandId {
            case expandSection where !enabled:
                return nil
            case collapseSection where !enabled && eligibility.canExpand:
                return nil
            case moveSectionToOtherRailTop, moveSectionToOtherRailBottom:
                // Only show when a cross-rail move is safe (not final-rail-empty).
                return enabled
                    ? MenuItem(id: commandId, title: title(for: commandId), isEnabled: true)
                    : nil
            default:
                return MenuItem(id: commandId, title: title(for: commandId), isEnabled: enabled)
            }
        }
    }

    /// Tab context-menu "Move Tab" destinations (same-rail section create + cross-rail).
    @MainActor
    static func tabMoveDestinations(
        store: SidebarDockStore,
        tabId: TabID
    ) -> [TabContextMoveDestination] {
        let eligibility = eligibility(store: store, tabId: tabId, paneId: store.paneId(forTabId: tabId))
        var destinations: [TabContextMoveDestination] = []
        if eligibility.canMoveTabToNewSectionTop {
            destinations.append(TabContextMoveDestination(
                id: moveTabToNewSectionTop,
                title: title(for: moveTabToNewSectionTop),
                isEnabled: true
            ))
        }
        if eligibility.canMoveTabToNewSectionBottom {
            destinations.append(TabContextMoveDestination(
                id: moveTabToNewSectionBottom,
                title: title(for: moveTabToNewSectionBottom),
                isEnabled: true
            ))
        }
        if eligibility.canMoveTabToOtherRail {
            for commandId in [
                moveTabToOtherRailSelected,
                moveTabToOtherRailTop,
                moveTabToOtherRailBottom,
            ] {
                destinations.append(TabContextMoveDestination(
                    id: commandId,
                    title: title(for: commandId),
                    isEnabled: true
                ))
            }
        }
        return destinations
    }

    /// Shared action path for context menu and command palette.
    @MainActor
    static func perform(
        commandId: String,
        store: SidebarDockStore,
        tabId: TabID?,
        paneId: PaneID?
    ) -> Bool {
        if commandId == showStokdWork {
            return store.selectToolMode(.stokdWork, focus: true)
        }

        // Refuse unsafe invocations even if a caller skips the menu enablement gate.
        let gate = eligibility(store: store, tabId: tabId, paneId: paneId)
        guard gate.isAvailable(commandId) else { return false }

        switch commandId {
        case moveTabToNewSectionTop:
            guard let tabId else { return false }
            return store.moveTabToNewSection(tabId, position: .top)
        case moveTabToNewSectionBottom:
            guard let tabId else { return false }
            return store.moveTabToNewSection(tabId, position: .bottom)
        case collapseSection:
            if store.sectionCount == 1 {
                return store.collapseSoleSection()
            }
            guard let paneId else { return false }
            return store.collapseSection(paneId: paneId)
        case expandSection:
            if store.sectionCount == 1 {
                return store.expandSoleSection()
            }
            guard let paneId else { return false }
            return store.expandSection(paneId: paneId)
        case reorderSectionUp:
            guard let paneId else { return false }
            let panes = store.orderedSectionPaneIds()
            guard let index = panes.firstIndex(where: { $0.id == paneId.id }), index > 0 else { return false }
            return store.reorderSection(from: index, to: index - 1)
        case reorderSectionDown:
            guard let paneId else { return false }
            let panes = store.orderedSectionPaneIds()
            guard let index = panes.firstIndex(where: { $0.id == paneId.id }),
                  index + 1 < panes.count else { return false }
            return store.reorderSection(from: index, to: index + 1)
        case moveTabToOtherRailSelected,
             moveTabToOtherRailTop,
             moveTabToOtherRailBottom,
             moveSectionToOtherRailTop,
             moveSectionToOtherRailBottom:
            return performCrossRail(
                commandId: commandId,
                store: store,
                tabId: tabId,
                paneId: paneId
            )
        default:
            return false
        }
    }

    /// Cross-rail tab/section commands share `SidebarDockTransfer` with drag.
    @MainActor
    private static func performCrossRail(
        commandId: String,
        store: SidebarDockStore,
        tabId: TabID?,
        paneId: PaneID?
    ) -> Bool {
        guard let registry = store.registry else { return false }
        let destEdge: SidebarDockEdge = store.edge == .left ? .right : .left

        switch commandId {
        case moveTabToOtherRailSelected,
             moveTabToOtherRailTop,
             moveTabToOtherRailBottom:
            let resolvedTab: TabID? = {
                if let tabId { return tabId }
                if let paneId {
                    return store.bonsplitController.selectedTab(inPane: paneId)?.id
                        ?? store.bonsplitController.tabs(inPane: paneId).first?.id
                }
                return store.bonsplitController.focusedPaneId.flatMap {
                    store.bonsplitController.selectedTab(inPane: $0)?.id
                }
            }()
            guard let resolvedTab,
                  let panelId = store.surfaceIdToPanelId[resolvedTab] else {
                return false
            }
            let destination: SidebarDockTransfer.TabDestination = {
                switch commandId {
                case moveTabToOtherRailTop:
                    return .newVerticalSection(position: .top)
                case moveTabToOtherRailBottom:
                    return .newVerticalSection(position: .bottom)
                default:
                    return .intoSelectedSection()
                }
            }()
            return SidebarDockTransfer.moveTab(
                registry: registry,
                panelId: panelId,
                from: store.edge,
                to: destEdge,
                destination: destination
            ).isSuccess
        case moveSectionToOtherRailTop, moveSectionToOtherRailBottom:
            let resolvedPane: PaneID? = {
                if let paneId { return paneId }
                if let tabId { return store.paneId(forTabId: tabId) }
                return store.bonsplitController.focusedPaneId
                    ?? store.orderedSectionPaneIds().first
            }()
            guard let resolvedPane else { return false }
            let sectionId = store.sectionId(forPane: resolvedPane)
            let destination: SidebarDockTransfer.SectionDestination =
                commandId == moveSectionToOtherRailTop ? .top : .bottom
            return SidebarDockTransfer.moveSection(
                registry: registry,
                sectionId: sectionId,
                from: store.edge,
                to: destEdge,
                destination: destination
            ).isSuccess
        default:
            return false
        }
    }
}
