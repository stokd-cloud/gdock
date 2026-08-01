import Foundation
import Observation
import SwiftUI

/// Per-window registry of the left and right rail stores.
///
/// Injected via `.environment(registry)` (not `.environmentObject`) because
/// the type is `@Observable`, not `ObservableObject`. Read only above row
/// boundaries — never from LazyVStack/List row views.
@MainActor
@Observable
final class SidebarDockStoreRegistry {
    let windowId: UUID
    let left: SidebarDockStore
    let right: SidebarDockStore

    init(windowId: UUID) {
        self.windowId = windowId
        self.left = SidebarDockStore(edge: .left, windowId: windowId)
        self.right = SidebarDockStore(edge: .right, windowId: windowId)
    }

    func store(for edge: SidebarDockEdge) -> SidebarDockStore {
        switch edge {
        case .left: return left
        case .right: return right
        }
    }
}

// MARK: - SwiftUI environment

private struct SidebarDockStoreRegistryKey: EnvironmentKey {
    static let defaultValue: SidebarDockStoreRegistry? = nil
}

extension EnvironmentValues {
    var sidebarDockStoreRegistry: SidebarDockStoreRegistry? {
        get { self[SidebarDockStoreRegistryKey.self] }
        set { self[SidebarDockStoreRegistryKey.self] = newValue }
    }
}
