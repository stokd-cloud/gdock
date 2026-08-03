import CmuxSettings
import Foundation
import Testing

struct GhosttyDockConfigLocationTests {
    @Test func accessorsResolveUnderInjectedHome() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("gdock-config-loc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let loc = CmuxConfigLocation(home: home)
        #expect(loc.directory.path.hasSuffix("/.config/ghostty-dock"))
        #expect(loc.legacyDirectory.path.hasSuffix("/.config/cmux"))
        #expect(loc.userConfigFile.lastPathComponent == "cmux.json")
        #expect(loc.userConfigFile.path.hasPrefix(loc.directory.path))
        #expect(loc.dockFile.lastPathComponent == "dock.json")
        #expect(loc.sidebarsDirectory.lastPathComponent == "sidebars")
        #expect(loc.legacyDevWindowDisplayFile.path.hasPrefix(loc.legacyDirectory.path))
    }
}
