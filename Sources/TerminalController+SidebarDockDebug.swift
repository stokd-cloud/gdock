import Foundation

#if DEBUG
/// RED stub: namespace listed but handlers intentionally unconnected.
extension TerminalController {
    nonisolated static let sidebarDockDebugMethodNames: [String] = [
        // Intentionally empty until green so catalog registration fails.
    ]

    func v2DebugSidebarDock(method: String, params: [String: Any]) -> V2CallResult? {
        _ = method
        _ = params
        return .err(code: "unavailable", message: "Intentionally unconnected until green wiring", data: nil)
    }
}
#endif
