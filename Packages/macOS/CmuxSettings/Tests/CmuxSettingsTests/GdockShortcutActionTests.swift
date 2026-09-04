import Testing
@testable import CmuxSettings

@Suite("gdock shortcut actions")
struct GdockShortcutActionTests {
    @Test("gdock quad shortcut actions are pane-scoped and defaulted")
    func gdockQuadShortcutActionsArePaneScopedAndDefaulted() {
        #expect(ShortcutAction.gdockNextQuadPane.rawValue == "gdock.nextQuadPane")
        #expect(ShortcutAction.gdockQuadPaneWorkspaces.rawValue == "gdock.quadPaneWorkspaces")
        #expect(ShortcutAction.gdockNextQuadPane.group == .panes)
        #expect(ShortcutAction.gdockQuadPaneWorkspaces.group == .panes)
        #expect(ShortcutAction.autoSplit.rawValue == "autoSplit")
        #expect(ShortcutAction.autoSplit.defaultStroke == ShortcutStroke(key: "y", command: true))
        #expect(ShortcutAction.gdockNextQuadPane.defaultStroke == nil)
        #expect(
            ShortcutAction.gdockQuadPaneWorkspaces.defaultStroke ==
                ShortcutStroke(key: "y", command: true, shift: true)
        )
    }
}
