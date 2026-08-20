import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite("Stokd Work panel persistence")
struct StokdWorkPanelPersistenceTests {
    @Test func workLayoutRoundTripsMembershipOrderAndSelection() throws {
        let workspace = Workspace(title: "Work", workingDirectory: "/tmp", portOrdinal: 0)
        let source = SidebarDockStore(edge: .right, windowId: UUID())
        source.seedRootPanels([
            RightSidebarToolPanel(workspace: workspace, mode: .sessions),
            RightSidebarToolPanel(workspace: workspace, mode: .files),
            RightSidebarToolPanel(workspace: workspace, mode: .stokdWork),
            RightSidebarToolPanel(workspace: workspace, mode: .find),
        ])
        #expect(source.selectToolMode(.stokdWork, focus: false))

        let captured = try #require(SidebarDockSessionPersistence.capture(store: source))
        let data = try JSONEncoder().encode(captured)
        let decoded = try JSONDecoder().decode(SessionSidebarRailSnapshot.self, from: data)
        let restored = SidebarDockStore(edge: .right, windowId: UUID())

        #expect(SidebarDockSessionPersistence.restore(
            snapshot: decoded,
            into: restored,
            workspace: workspace,
            includeStokdWork: true
        ))
        #expect(SidebarDockSeeding.orderedRightModes(in: restored) == [.sessions, .files, .stokdWork, .find])
        #expect(restored.focusedToolMode() == .stokdWork)
    }

    @Test func unknownKindsAreSkippedWithoutDroppingKnownTabs() throws {
        let workspace = Workspace(title: "Work", workingDirectory: "/tmp", portOrdinal: 0)
        let filesPayload = try JSONEncoder().encode(SessionRightSidebarToolPanelSnapshot(mode: .files))
        let snapshot = SessionSidebarRailSnapshot(
            sections: [
                SessionSidebarRailSectionSnapshot(
                    id: UUID(),
                    tabs: [
                        SessionSidebarRailTabSnapshot(id: UUID(), kind: "futureStokdPanel", payload: Data()),
                        SessionSidebarRailTabSnapshot(
                            id: UUID(),
                            kind: PanelType.rightSidebarTool.rawValue,
                            payload: filesPayload
                        ),
                    ],
                    selectedTabId: nil
                ),
            ]
        )
        let restored = SidebarDockStore(edge: .right, windowId: UUID())

        #expect(SidebarDockSessionPersistence.restore(
            snapshot: snapshot,
            into: restored,
            workspace: workspace,
            includeStokdWork: true
        ))
        #expect(SidebarDockSeeding.orderedRightModes(in: restored) == [.files])
    }

    @Test func legacyWindowSnapshotDecodesWithoutRailFields() throws {
        let data = try #require("""
        {
          "tabManager": { "workspaces": [] },
          "sidebar": { "isVisible": true, "selection": "tabs" }
        }
        """.data(using: .utf8))

        let snapshot = try JSONDecoder().decode(SessionWindowSnapshot.self, from: data)

        #expect(snapshot.leftRail == nil)
        #expect(snapshot.rightRail == nil)
        #expect(SessionSnapshotSchema.currentVersion == 1)
    }
}
