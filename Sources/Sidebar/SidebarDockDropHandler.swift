import Bonsplit
import Foundation

/// RED stub: always refuses so edge-band / shared-path tests fail until green.
@MainActor
enum SidebarDockDropHandler {
    enum Outcome: Equatable, Sendable {
        case createdSection(position: SidebarDockSectionPosition)
        case movedIntoPane
        case samePaneNoop
        case refused(reason: RefusalReason)

        var isSuccess: Bool {
            switch self {
            case .createdSection, .movedIntoPane, .samePaneNoop: return true
            case .refused: return false
            }
        }

        var reasonCode: String {
            switch self {
            case .createdSection(let position): return "created_\(position.rawValue)"
            case .movedIntoPane: return "moved_into_pane"
            case .samePaneNoop: return "same_pane_noop"
            case .refused(let reason): return reason.rawValue
            }
        }
    }

    enum RefusalReason: String, Equatable, Sendable {
        case horizontal
        case disallowedPanel
        case geometry
        case missingTab
        case emptyRailGuard
        case unknown
    }

    @discardableResult
    static func handle(
        store: SidebarDockStore,
        tabId: TabID,
        zone: SidebarDockEdgeBand.Zone,
        targetPaneId: PaneID? = nil
    ) -> Outcome {
        // Intentionally unconnected until green wiring.
        _ = store
        _ = tabId
        _ = zone
        _ = targetPaneId
        return .refused(reason: .unknown)
    }

    @discardableResult
    static func handleExternal(
        store: SidebarDockStore,
        request: BonsplitController.ExternalTabDropRequest
    ) -> Bool {
        _ = store
        _ = request
        return false
    }
}
