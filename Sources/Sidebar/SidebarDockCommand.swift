import Bonsplit
import Foundation

/// Shared command identifiers and mutation path for rail context menus and the command palette.
enum SidebarDockCommand {
    static let moveTabToNewSectionTop = "sidebarDock.moveTabToNewSection.top"
    static let moveTabToNewSectionBottom = "sidebarDock.moveTabToNewSection.bottom"
    static let collapseSection = "sidebarDock.section.collapse"
    static let expandSection = "sidebarDock.section.expand"
    static let reorderSectionUp = "sidebarDock.section.reorderUp"
    static let reorderSectionDown = "sidebarDock.section.reorderDown"

    /// Every actor-facing rail command id (palette, context menu, header controls).
    static let allCommandIds: [String] = [
        moveTabToNewSectionTop,
        moveTabToNewSectionBottom,
        collapseSection,
        expandSection,
        reorderSectionUp,
        reorderSectionDown,
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

        static let none = Eligibility(
            canMoveTabToNewSectionTop: false,
            canMoveTabToNewSectionBottom: false,
            canCollapse: false,
            canExpand: false,
            canReorderUp: false,
            canReorderDown: false
        )

        func isAvailable(_ commandId: String) -> Bool {
            switch commandId {
            case SidebarDockCommand.moveTabToNewSectionTop: return canMoveTabToNewSectionTop
            case SidebarDockCommand.moveTabToNewSectionBottom: return canMoveTabToNewSectionBottom
            case SidebarDockCommand.collapseSection: return canCollapse
            case SidebarDockCommand.expandSection: return canExpand
            case SidebarDockCommand.reorderSectionUp: return canReorderUp
            case SidebarDockCommand.reorderSectionDown: return canReorderDown
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

        return Eligibility(
            canMoveTabToNewSectionTop: canMove,
            canMoveTabToNewSectionBottom: canMove,
            canCollapse: resolvedPane != nil && !isCollapsed && store.sectionCount >= 1,
            canExpand: resolvedPane != nil && isCollapsed,
            canReorderUp: store.sectionCount >= 2 && (paneIndex ?? 0) > 0,
            canReorderDown: store.sectionCount >= 2
                && paneIndex.map { $0 + 1 < panes.count } == true
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
            default:
                return MenuItem(id: commandId, title: title(for: commandId), isEnabled: enabled)
            }
        }
    }

    /// Tab context-menu "Move Tab" destinations that create a new vertical section.
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
        default:
            return false
        }
    }
}
