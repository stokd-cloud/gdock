import Foundation
import Testing

/// Asserts the shipped Info.plist severs the upstream manaflow Sparkle feed.
struct GhosttyDockUpdateFeedTests {
    private var infoPlistURL: URL {
        // Prefer the app bundle when tests run inside the host app; fall back to
        // the repo Resources/Info.plist so unit runs still exercise the shipped source.
        if let bundleURL = Bundle.main.url(forResource: "Info", withExtension: "plist"),
           let dict = NSDictionary(contentsOf: bundleURL) as? [String: Any],
           dict["SUFeedURL"] != nil {
            return bundleURL
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            cwd.appendingPathComponent("Resources/Info.plist"),
            cwd.appendingPathComponent("../Resources/Info.plist"),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/Info.plist"),
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return candidates[0]
    }

    @Test func suFeedURLDoesNotPointAtManaflow() throws {
        let dict = try loadPlist()
        let feed = try #require(dict["SUFeedURL"] as? String)
        #expect(!feed.contains("manaflow-ai"))
        #expect(feed.contains("stokd-cloud/ghostty-dock"))
    }

    @Test func automaticChecksDisabledUntilForkFeedPublished() throws {
        let dict = try loadPlist()
        let enabled = dict["SUEnableAutomaticChecks"] as? Bool
        #expect(enabled == false)
    }

    @Test func sparklePublicKeyIsNotManaflowKey() throws {
        // Source of truth for the resolved key is the pbxproj build setting; the
        // plist stores $(SPARKLE_PUBLIC_KEY). Assert the checked-in pbxproj value.
        let pbx = try String(contentsOf: pbxprojURL(), encoding: .utf8)
        #expect(!pbx.contains("avjcgKibf1FTvhIjLBxhd+0HSpsXU4D0IGlVk8cgqRc="))
        #expect(pbx.contains("SPARKLE_PUBLIC_KEY = \""))
    }

    private func loadPlist() throws -> [String: Any] {
        let data = try Data(contentsOf: infoPlistURL)
        let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try #require(obj as? [String: Any])
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
