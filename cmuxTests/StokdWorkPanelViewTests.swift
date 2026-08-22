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

        #expect(store.selectToolMode(.files, focus: true))
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

    @Test func presentationLocalizesKnownStatusesAndFormatsTimestamps() {
        let japanese = Locale(identifier: "ja")

        #expect(
            StokdWorkPresentation.statusText("in_progress", locale: japanese)
                == String(
                    localized: "stokdWork.status.inProgress",
                    defaultValue: "In progress",
                    locale: japanese
                )
        )
        #expect(StokdWorkPresentation.statusText("future_state", locale: japanese) == "future state")
        #expect(
            StokdWorkPresentation.updatedAtText(
                "2026-08-20T11:00:00Z",
                locale: japanese
            ) != "2026-08-20T11:00:00Z"
        )
        #expect(StokdWorkPresentation.updatedAtText("not-a-date", locale: japanese) == "not-a-date")
    }
}
