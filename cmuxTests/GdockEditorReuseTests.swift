import Foundation
import Testing

#if canImport(cmux_DEV)
    @testable import cmux_DEV
#elseif canImport(cmux)
    @testable import cmux
#endif

@Suite("Gdock editor reuse and Monaco find")
struct GdockEditorReuseTests {
    @Test("opening a file that is already in a Monaco panel reuses that panel")
    func reusesExistingMonacoPanelForTheSamePath() {
        let panelId = UUID()
        let path = "/repo/Sources/AppDelegate.swift"
        let result = GdockEditorReusePlanner.panelIdToFocus(
            filePath: path,
            openEditors: [
                (panelId: panelId, filePath: path),
                (panelId: UUID(), filePath: "/repo/Sources/Other.swift"),
            ]
        )
        #expect(result == panelId)
    }

    @Test("path comparison is standardized so duplicate slashes still match")
    func standardizedPathsMatch() {
        let panelId = UUID()
        let result = GdockEditorReusePlanner.panelIdToFocus(
            filePath: "/repo/Sources/./AppDelegate.swift",
            openEditors: [(panelId: panelId, filePath: "/repo/Sources/AppDelegate.swift")]
        )
        #expect(result == panelId)
    }

    @Test("a file with no open editor is not reused")
    func missingEditorIsNotReused() {
        let result = GdockEditorReusePlanner.panelIdToFocus(
            filePath: "/repo/New.swift",
            openEditors: [(panelId: UUID(), filePath: "/repo/Old.swift")]
        )
        #expect(result == nil)
    }

    @Test("find on a Monaco editor uses the Monaco find widget")
    func monacoFindUsesEditorWidget() {
        #expect(GdockEditorFindDispatch.target(editorPageActive: true) == .monacoWidget)
    }

    @Test("find on a normal browser panel stays on find-in-page")
    func browserFindStaysOnFindInPage() {
        #expect(GdockEditorFindDispatch.target(editorPageActive: false) == .browserFindInPage)
    }
}
