import AppKit
import Bonsplit
import CmuxAppKitSupportUI
import CmuxSettings
import CmuxSettingsUI
import SwiftUI

/// App-owned environment installed while a canvas pane builds its dock content
/// view. ``Panel/makeDockContentView(context:)`` reads this to construct the
/// SwiftUI hosting path that previously lived behind the hosted canvas content branch.
@MainActor
struct DockableCanvasMountEnvironment {
    let workspace: Workspace?
    let isWorkspaceVisible: Bool
    let portalPriority: Int
    let appearance: PanelAppearance
    let windowAppearance: WindowAppearanceSnapshot
    let settingsRuntime: SettingsRuntime?
}

/// Main-actor holder for the canvas mount environment.
@MainActor
enum DockableCanvasMountEnvironmentStorage {
    static var current: DockableCanvasMountEnvironment?

    static func install(_ environment: DockableCanvasMountEnvironment) {
        current = environment
    }

    static func clear() {
        current = nil
    }

    static func withEnvironment<T>(
        _ environment: DockableCanvasMountEnvironment,
        _ body: () -> T
    ) -> T {
        install(environment)
        defer { clear() }
        return body()
    }
}
