import Foundation
import Testing

struct GhosttyDockBundleIdentityTests {
    @Test func pbxprojDeclaresGdockProductIdentity() throws {
        let pbx = try String(contentsOf: pbxprojURL(), encoding: .utf8)
        // Display name is "gdock" / "gdock DEV" after the Ghostty Dock -> gdock rename.
        #expect(pbx.contains("PRODUCT_NAME = gdock;") || pbx.contains("PRODUCT_NAME = \"gdock\";"))
        #expect(pbx.contains("PRODUCT_NAME = \"gdock DEV\";"))
        #expect(!pbx.contains("PRODUCT_NAME = \"Ghostty Dock\";"))
        #expect(!pbx.contains("PRODUCT_NAME = \"Ghostty Dock DEV\";"))
    }

    /// The bundle identifier is deliberately NOT renamed alongside the display name.
    ///
    /// Every distinct bundle id gets its own UserDefaults domain, so changing it
    /// silently reverts every stored setting to its default — the failure mode that
    /// previously made the sidebar dock, the branding, and the activation policy all
    /// appear to vanish between builds. Display name may change freely; identity may not.
    @Test func bundleIdentifierIsUnchangedByTheRename() throws {
        let pbx = try String(contentsOf: pbxprojURL(), encoding: .utf8)
        #expect(pbx.contains("PRODUCT_BUNDLE_IDENTIFIER = cloud.stokd.ghostty-dock;"))
        #expect(pbx.contains("PRODUCT_BUNDLE_IDENTIFIER = cloud.stokd.ghostty-dock.debug;"))
        #expect(!pbx.contains("PRODUCT_BUNDLE_IDENTIFIER = com.cmuxterm."))
    }

    @Test func runtimeBundleIdentityWhenHostIsGdock() {
        guard let bid = Bundle.main.bundleIdentifier else { return }
        // When tests run inside the app host after rebrand, identity must match.
        if bid.hasPrefix("cloud.stokd.ghostty-dock") {
            let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            #expect(name?.hasPrefix("gdock") == true)
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
