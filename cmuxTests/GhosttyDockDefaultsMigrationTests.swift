import Foundation
import Testing

@testable import cmux

struct GhosttyDockDefaultsMigrationTests {
    @Test func copiesMissingKeysWithoutTouchingSourceOrOverwriting() {
        let sourceName = "gdock.defaults.src.\(UUID().uuidString)"
        let destName = "gdock.defaults.dst.\(UUID().uuidString)"
        let source = UserDefaults(suiteName: sourceName)!
        let dest = UserDefaults(suiteName: destName)!
        defer {
            source.removePersistentDomain(forName: sourceName)
            dest.removePersistentDomain(forName: destName)
        }

        source.set("from-legacy", forKey: "socketControlMode")
        source.set("keep-source", forKey: "legacyOnlyKey")
        dest.set("already", forKey: "socketControlMode")

        let copied = GhosttyDockConfigMigration.migrateDefaultsIfNeeded(
            destination: dest,
            sourceSuiteName: sourceName,
            sourceFactory: { UserDefaults(suiteName: $0) }
        )
        #expect(copied)
        #expect(dest.string(forKey: "socketControlMode") == "already")
        #expect(dest.string(forKey: "legacyOnlyKey") == "keep-source")
        #expect(source.string(forKey: "legacyOnlyKey") == "keep-source")
        #expect(source.string(forKey: "socketControlMode") == "from-legacy")
    }

    @Test func skipsAppleInternalKeys() {
        #expect(GhosttyDockConfigMigration.shouldSkipDefaultsKey("NSWindow Frame main"))
        #expect(GhosttyDockConfigMigration.shouldSkipDefaultsKey("AppleLanguages"))
        #expect(!GhosttyDockConfigMigration.shouldSkipDefaultsKey("socketControlMode"))
    }
}
