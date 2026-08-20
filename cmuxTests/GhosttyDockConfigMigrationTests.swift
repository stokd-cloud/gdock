import CmuxSettings
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

struct GhosttyDockConfigMigrationTests {
    @Test func copiesLegacyConfigWithoutTouchingSource() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gdock-mig-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let home = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let loc = CmuxConfigLocation(home: home)
        try FileManager.default.createDirectory(at: loc.legacyDirectory, withIntermediateDirectories: true)
        let sample = "{\n  \"app\": { \"foo\": true }\n}\n"
        try sample.write(to: loc.legacyDirectory.appendingPathComponent("cmux.json"), atomically: true, encoding: .utf8)
        try "dock".write(to: loc.legacyDirectory.appendingPathComponent("dock.json"), atomically: true, encoding: .utf8)

        // UserDefaults exposes no `suiteName` accessor; keep the name we created
        // it with so the suite can be torn down.
        let suiteName = "gdock.mig.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let didMigrate = GhosttyDockConfigMigration.migrateConfigDirectoryIfNeeded(
            locations: loc,
            fileManager: .default,
            defaults: defaults
        )
        #expect(didMigrate)
        #expect(FileManager.default.fileExists(atPath: loc.directory.appendingPathComponent("cmux.json").path))
        #expect(try String(contentsOf: loc.legacyDirectory.appendingPathComponent("cmux.json")) == sample)
        #expect(defaults.integer(forKey: GhosttyDockConfigMigration.configMigrationVersionKey) == 1)

        // Idempotent second run
        let again = GhosttyDockConfigMigration.migrateConfigDirectoryIfNeeded(
            locations: loc,
            fileManager: .default,
            defaults: defaults
        )
        #expect(!again)
        // Mutate new dir; second run must not clobber
        try "mutated".write(to: loc.directory.appendingPathComponent("cmux.json"), atomically: true, encoding: .utf8)
        _ = GhosttyDockConfigMigration.migrateConfigDirectoryIfNeeded(
            locations: loc,
            fileManager: .default,
            defaults: defaults
        )
        #expect(try String(contentsOf: loc.directory.appendingPathComponent("cmux.json")) == "mutated")
        #expect(try String(contentsOf: loc.legacyDirectory.appendingPathComponent("cmux.json")) == sample)
    }

    @Test func absentLegacyCreatesEmptyDestinationWithoutThrow() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gdock-mig-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let loc = CmuxConfigLocation(home: home)
        // UserDefaults exposes no `suiteName` accessor; keep the name we created
        // it with so the suite can be torn down.
        let suiteName = "gdock.mig.empty.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let didMigrate = GhosttyDockConfigMigration.migrateConfigDirectoryIfNeeded(
            locations: loc,
            fileManager: .default,
            defaults: defaults
        )
        #expect(!didMigrate)
        #expect(FileManager.default.fileExists(atPath: loc.directory.path))
    }
}
