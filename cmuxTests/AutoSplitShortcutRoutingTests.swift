import Foundation
import Testing
import CmuxSettings

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("Auto Split shortcut")
struct AutoSplitShortcutRoutingTests {
    @Test("default Auto Split is Cmd+Y and does not collide")
    func defaultIsCommandYWithoutCollision() {
        let autoSplit = KeyboardShortcutSettings.Action.autoSplit.defaultShortcut
        #expect(autoSplit == StoredShortcut(key: "y", command: true, shift: false, option: false, control: false))
        #expect(KeyboardShortcutSettings.Action.gdockNextQuadPane.defaultShortcut.isUnbound)
        #expect(KeyboardShortcutSettings.publicShortcutActions.contains(.autoSplit))
        #expect(KeyboardShortcutSettings.settingsVisibleActions.contains(.autoSplit))

        let collisions = KeyboardShortcutSettings.Action.allCases.filter { action in
            action != .autoSplit
                && !autoSplit.isUnbound
                && action.defaultShortcut == autoSplit
        }
        #expect(collisions.isEmpty)
    }

    @Test("package ShortcutAction catalogs autoSplit as Cmd+Y")
    func packageShortcutActionCatalogsAutoSplit() {
        #expect(ShortcutAction.autoSplit.rawValue == "autoSplit")
        #expect(ShortcutAction.autoSplit.group == .panes)
        #expect(ShortcutAction.autoSplit.defaultStroke == ShortcutStroke(key: "y", command: true))
        #expect(ShortcutAction.gdockNextQuadPane.defaultStroke == nil)
    }

    @Test("palette command id uses gdock prefix")
    func paletteCommandIdUsesGdockPrefix() {
        #expect(GdockAutoSplitterSettings.autoSplitCommandId.hasPrefix("palette.gdock."))
    }
}
