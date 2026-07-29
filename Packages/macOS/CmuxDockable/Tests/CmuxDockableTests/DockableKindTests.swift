import Foundation
import Testing
@testable import CmuxDockable

struct DockableKindTests {
    /// Literal expected raw-value set matching app `PanelType` strings.
    /// Package tests cannot import `PanelType`; app-level bidirectional parity
    /// is deferred to W2.
    private static let expectedRawValues: Set<String> = [
        "terminal",
        "browser",
        "markdown",
        "filepreview",
        "rightSidebarTool",
        "leftWorkspaceSelector",
        "customSidebar",
        "agentSession",
        "project",
        "extensionBrowser",
        "workspaceTodo",
        "cloudVMLoading",
    ]

    @Test func rawValueParityWithPanelType() {
        #expect(DockableKind.allCases.count == 12)
        let actual = Set(DockableKind.allCases.map(\.rawValue))
        #expect(actual == Self.expectedRawValues)

        for raw in Self.expectedRawValues {
            #expect(DockableKind(rawValue: raw) != nil, "DockableKind missing raw value \(raw)")
        }

        // Explicit filePreview casing: case name is filePreview, raw is filepreview.
        #expect(DockableKind.filePreview.rawValue == "filepreview")
    }

    @Test func codableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for kind in DockableKind.allCases {
            let data = try encoder.encode(kind)
            let decoded = try decoder.decode(DockableKind.self, from: data)
            #expect(decoded == kind)
        }

        // Lenient mixed-case decode (parity with PanelType-style decoding).
        let mixedCase = Data(#""FilePreview""#.utf8)
        let decodedMixed = try decoder.decode(DockableKind.self, from: mixedCase)
        #expect(decodedMixed == .filePreview)

        let mixedSidebar = Data(#""RightSidebarTool""#.utf8)
        let decodedSidebar = try decoder.decode(DockableKind.self, from: mixedSidebar)
        #expect(decodedSidebar == .rightSidebarTool)
    }
}
