import Foundation
import Testing

struct GhosttyDockBundleIdentityTests {
    @Test func pbxprojDeclaresGhosttyDockProductIdentity() throws {
        let pbx = try String(contentsOf: pbxprojURL(), encoding: .utf8)
        #expect(pbx.contains("PRODUCT_NAME = \"Ghostty Dock\";") || pbx.contains("PRODUCT_NAME = Ghostty Dock;"))
        #expect(pbx.contains("PRODUCT_NAME = \"Ghostty Dock DEV\";"))
        #expect(pbx.contains("PRODUCT_BUNDLE_IDENTIFIER = cloud.stokd.ghostty-dock;"))
        #expect(pbx.contains("PRODUCT_BUNDLE_IDENTIFIER = cloud.stokd.ghostty-dock.debug;"))
        #expect(!pbx.contains("PRODUCT_BUNDLE_IDENTIFIER = com.cmuxterm."))
        #expect(pbx.contains("PRODUCT_NAME = gdock;"))
    }

    @Test func runtimeBundleIdentityWhenHostIsGhosttyDock() {
        guard let bid = Bundle.main.bundleIdentifier else { return }
        // When tests run inside the app host after rebrand, identity must match.
        if bid.hasPrefix("cloud.stokd.ghostty-dock") {
            let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            #expect(name?.hasPrefix("Ghostty Dock") == true)
        }
    }

    private func pbxprojURL() throws -> URL {
        let fromFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("cmux.xcodeproj/project.pbxproj")
        if FileManager.default.fileExists(atPath: fromFile.path) {
            return fromFile
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("cmux.xcodeproj/project.pbxproj")
    }
}
