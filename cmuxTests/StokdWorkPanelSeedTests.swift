import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite("Stokd Work panel seeding")
struct StokdWorkPanelSeedTests {
    @Test func coldEnableSeedsWorkAfterCanonicalTools() throws {
        let workspace = Workspace(title: "Work", workingDirectory: "/tmp", portOrdinal: 0)
        let store = SidebarDockStore(edge: .right, windowId: UUID())

        #expect(SidebarDockSeeding.seedRightIfEmpty(
            store: store,
            workspace: workspace,
            preferredMode: .files,
            includeStokdWork: true
        ))
        #expect(SidebarDockSeeding.orderedRightModes(in: store) == [.files, .find, .sessions, .stokdWork])
        #expect(!SidebarDockSeeding.seedRightIfEmpty(
            store: store,
            workspace: workspace,
            preferredMode: .files,
            includeStokdWork: true
        ))
        #expect(SidebarDockSeeding.orderedRightModes(in: store).filter { $0 == .stokdWork }.count == 1)
    }

    @Test func flagOffKeepsCanonicalThreeTools() {
        let workspace = Workspace(title: "Work", workingDirectory: "/tmp", portOrdinal: 0)
        let store = SidebarDockStore(edge: .right, windowId: UUID())

        #expect(SidebarDockSeeding.seedRightIfEmpty(
            store: store,
            workspace: workspace,
            preferredMode: .files,
            includeStokdWork: false
        ))
        #expect(SidebarDockSeeding.orderedRightModes(in: store) == [.files, .find, .sessions])
    }

    @Test func existingCustomOrderAppendsWorkWithoutChangingSelection() throws {
        let workspace = Workspace(title: "Work", workingDirectory: "/tmp", portOrdinal: 0)
        let store = SidebarDockStore(edge: .right, windowId: UUID())
        for mode in [RightSidebarMode.sessions, .files, .find] {
            _ = try #require(store.attachPanel(RightSidebarToolPanel(workspace: workspace, mode: mode), select: false))
        }
        #expect(store.selectToolMode(.files, focus: false))

        #expect(SidebarDockSeeding.seedRightIfEmpty(
            store: store,
            workspace: workspace,
            preferredMode: .sessions,
            includeStokdWork: true
        ))
        #expect(SidebarDockSeeding.orderedRightModes(in: store) == [.sessions, .files, .find, .stokdWork])
        #expect(store.focusedToolMode() == .files)
    }

    @Test func rightSeedNeverMutatesLeftRail() throws {
        let workspace = Workspace(title: "Work", workingDirectory: "/tmp", portOrdinal: 0)
        let left = SidebarDockStore(edge: .left, windowId: UUID())
        #expect(SidebarDockSeeding.seedLeftIfEmpty(store: left, workspace: workspace))
        let before = left.sectionSnapshots()

        #expect(!SidebarDockSeeding.seedRightIfEmpty(
            store: left,
            workspace: workspace,
            preferredMode: .files,
            includeStokdWork: true
        ))
        #expect(left.sectionSnapshots() == before)
    }
}
