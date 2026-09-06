import AppKit
import Bonsplit
import CmuxSettings
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("Auto Split force button", .serialized)
struct AutoSplitForceButtonTests {
    @Test("force off keeps Split Quad last button")
    @MainActor
    func forceOffKeepsSplitQuad() {
        let buttons = AutoSplitAction.presentSplitButtons(
            QuadSplitAction.defaultSplitActionButtons,
            forceEnabled: false
        )
        #expect(buttons.last?.id == CmuxSurfaceTabBarBuiltInAction.splitQuad.configID)
        #expect(buttons.last?.tooltip == String(localized: "workspace.tooltip.splitQuad", defaultValue: "Split Quad"))
    }

    @Test("force on remaps presentation but keeps splitQuad id")
    @MainActor
    func forceOnRemapsPresentation() {
        let shape = GdockAutoSplitterSettings.Shape.clamped(rows: 2, cols: 3)
        let buttons = AutoSplitAction.presentSplitButtons(
            [
                BonsplitConfiguration.SplitActionButton(
                    id: CmuxSurfaceTabBarBuiltInAction.splitQuad.configID,
                    systemImage: "square.split.2x2",
                    tooltip: "Split Quad",
                    action: .custom("cmux.splitQuad")
                )
            ],
            forceEnabled: true,
            shape: shape
        )
        #expect(buttons.count == 1)
        #expect(buttons[0].id == "cmux.splitQuad")
        #expect(buttons[0].tooltip == GdockAutoSplitterSettings.autoSplitTooltip(shape: shape))
        if case .custom(let id) = buttons[0].action {
            #expect(id == "cmux.splitQuad")
        } else {
            Issue.record("expected custom cmux.splitQuad action")
        }
    }

    @Test("omitted splitQuad is not inserted")
    @MainActor
    func omittedSplitQuadIsNotInserted() {
        let source: [BonsplitConfiguration.SplitActionButton] = [
            BonsplitConfiguration.SplitActionButton(
                id: "cmux.splitRight",
                systemImage: "square.split.2x1",
                tooltip: "Split Right",
                action: .splitRight
            )
        ]
        let presented = AutoSplitAction.presentSplitButtons(source, forceEnabled: true)
        #expect(presented.count == 1)
        #expect(presented[0].id == "cmux.splitRight")
    }

    @Test("remote embedded still filters custom split buttons")
    @MainActor
    func remoteEmbeddedFiltersCustomButtons() {
        var configuration = BonsplitConfiguration()
        configuration.appearance.splitButtons = AutoSplitAction.presentSplitButtons(
            QuadSplitAction.defaultSplitActionButtons,
            forceEnabled: true
        )
        let embedded = configuration.remoteTmuxEmbedded
        #expect(embedded.appearance.splitButtons.allSatisfy {
            $0.action == .splitRight || $0.action == .splitDown
        })
        #expect(!embedded.appearance.splitButtons.contains(where: {
            if case .custom = $0.action { return true }
            return false
        }))
    }
}
