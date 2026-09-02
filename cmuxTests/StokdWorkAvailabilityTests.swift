import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// VAL-GATE-001 / VAL-GATE-002: Work is a default right-sidebar tool with every
/// beta flag off and knows nothing about the sidebar dock.
@Suite("Stokd Work availability")
struct StokdWorkAvailabilityTests {
    @Test func workIsADefaultToolWithEveryBetaFlagOff() {
        #expect(
            RightSidebarMode.availableModes(feedEnabled: false, dockEnabled: false, stokdPanelsEnabled: false)
                == [.files, .find, .sessions, .stokdWork]
        )
        #expect(RightSidebarMode.stokdWork.isAvailable(feedEnabled: false, dockEnabled: false, stokdPanelsEnabled: false))
    }

    @Test func workSourcesHaveNoDockDependency() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let stokdDirectory = root.appendingPathComponent("Sources/Stokd", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(atPath: stokdDirectory.path)
            .filter { $0.hasSuffix(".swift") }
        #expect(!files.isEmpty)
        let forbidden = ["SidebarDock", "sidebar.beta.dock.enabled", "localhost", "8167", "http://", "URLSession"]
        for file in files {
            let text = try String(contentsOf: stokdDirectory.appendingPathComponent(file), encoding: .utf8)
            for needle in forbidden {
                #expect(!text.contains(needle), "\(file) mentions \(needle)")
            }
        }
        let lint = root.appendingPathComponent("scripts/lint-stokd-work-dock-independence.sh")
        #expect(FileManager.default.isExecutableFile(atPath: lint.path))
    }
}
