import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite("Stokd Work panel view actions")
struct StokdWorkPanelViewTests {
    @Test func sharedCommandSelectsWorkThroughDockInvoker() throws {
        let workspace = Workspace(title: "Work", workingDirectory: "/tmp", portOrdinal: 0)
        let store = SidebarDockStore(edge: .right, windowId: UUID())
        let files = RightSidebarToolPanel(workspace: workspace, mode: .files)
        let work = RightSidebarToolPanel(workspace: workspace, mode: .stokdWork)
        _ = try #require(store.attachPanel(files, select: true))
        _ = try #require(store.attachPanel(work, select: false))

        #expect(store.focusedToolMode() == .files)
        #expect(SidebarDockCommand.showStokdWork == "palette.gdock.showStokdWork")
        #expect(SidebarDockActionInvoker.perform(
            commandId: SidebarDockCommand.showStokdWork,
            store: store,
            tabId: nil,
            paneId: nil
        ))
        #expect(store.focusedToolMode() == .stokdWork)
    }
}
