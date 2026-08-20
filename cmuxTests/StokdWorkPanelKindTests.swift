import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite("Stokd Work panel kind", .serialized)
struct StokdWorkPanelKindTests {
    @Test func stableKindRoundTripsThroughPersistedToolSnapshot() throws {
        #expect(RightSidebarMode.stokdWork.rawValue == "stokdWork")

        let data = try JSONEncoder().encode(
            SessionRightSidebarToolPanelSnapshot(mode: .stokdWork)
        )
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: String]
        )
        #expect(json["mode"] == "stokdWork")

        let decoded = try JSONDecoder().decode(
            SessionRightSidebarToolPanelSnapshot.self,
            from: data
        )
        #expect(decoded.mode == .stokdWork)
    }

    @Test func workPanelAttachesOnlyToTheRightRail() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let right = SidebarDockStore(edge: .right, windowId: UUID())
        let left = SidebarDockStore(edge: .left, windowId: UUID())

        let rightPanel = RightSidebarToolPanel(workspace: workspace, mode: .stokdWork)
        #expect(right.attachPanel(rightPanel) != nil)

        let leftPanel = RightSidebarToolPanel(workspace: workspace, mode: .stokdWork)
        #expect(left.attachPanel(leftPanel) == nil)
        #expect(left.panels[leftPanel.id] == nil)
    }

    @Test func unknownPersistedToolKindIsDroppedWithoutFailingDecode() throws {
        let data = try #require(#"{"mode":"stokdFuture"}"#.data(using: .utf8))
        let decoded = try JSONDecoder().decode(
            SessionRightSidebarToolPanelSnapshot.self,
            from: data
        )
        #expect(decoded.mode == nil)
    }
}
