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

    /// Shared action path for context menu and command palette.
    @MainActor
    static func perform(
        commandId: String,
        store: SidebarDockStore,
        tabId: TabID?,
        paneId: PaneID?
    ) -> Bool {
        switch commandId {
        case moveTabToNewSectionTop:
            guard let tabId else { return false }
            return store.moveTabToNewSection(tabId, position: .top)
        case moveTabToNewSectionBottom:
            guard let tabId else { return false }
            return store.moveTabToNewSection(tabId, position: .bottom)
        case collapseSection:
            guard let paneId else { return false }
            return store.collapseSection(paneId: paneId)
        case expandSection:
            guard let paneId else { return false }
            if store.sectionCount == 1 {
                return store.expandSoleSection()
            }
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
