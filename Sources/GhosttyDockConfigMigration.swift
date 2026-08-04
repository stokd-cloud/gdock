import CmuxSettings
import Foundation

/// Non-destructive one-time migration from upstream cmux config/defaults into
/// gdock locations. Never deletes or moves legacy data.
enum GhosttyDockConfigMigration {
    static let configMigrationVersionKey = "ghosttyDockConfigMigrationVersion"
    static let defaultsMigrationVersionKey = "ghosttyDockDefaultsMigrationVersion"
    static let currentVersion = 1

    /// Legacy UserDefaults suite name used by cmux stable builds.
    static let legacyDefaultsSuiteName = "com.cmuxterm.app"

    /// Keys we refuse to import from the legacy suite (Apple/system frame keys).
    private static let excludedDefaultsKeyPrefixes = [
        "NSWindow",
        "Apple",
        "NSNav",
        "NSSplitView",
        "NSToolbar",
        "NSOutlineView",
        "NSTableView",
        "NSStatusItem",
        "WebKit",
    ]

    /// Copy `~/.config/cmux` → `~/.config/ghostty-dock` when the destination is absent.
    /// Leaves the legacy tree byte-identical. Idempotent via destination existence + watermark.
    @discardableResult
    static func migrateConfigDirectoryIfNeeded(
        locations: CmuxConfigLocation = CmuxConfigLocation(),
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) -> Bool {
        if defaults.integer(forKey: configMigrationVersionKey) >= currentVersion {
            // Still allow first-copy when watermark was set without a successful copy.
            if fileManager.fileExists(atPath: locations.directory.path) {
                return false
            }
        }

        var isDirectory: ObjCBool = false
        let legacyExists = fileManager.fileExists(
            atPath: locations.legacyDirectory.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue

        if fileManager.fileExists(atPath: locations.directory.path) {
            defaults.set(currentVersion, forKey: configMigrationVersionKey)
            return false
        }

        guard legacyExists else {
            // No legacy config: create empty destination directory so writers have a home.
            try? fileManager.createDirectory(
                at: locations.directory,
                withIntermediateDirectories: true
            )
            defaults.set(currentVersion, forKey: configMigrationVersionKey)
            return false
        }

        do {
            try fileManager.createDirectory(
                at: locations.directory.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: locations.legacyDirectory, to: locations.directory)
            defaults.set(currentVersion, forKey: configMigrationVersionKey)
            return true
        } catch {
            // Failed copy: leave destination absent so readers can fall back later.
            try? fileManager.removeItem(at: locations.directory)
            return false
        }
    }

    /// Copy keys from the legacy `com.cmuxterm.app` suite into the current suite
    /// without overwriting keys already present and without mutating the source suite.
    @discardableResult
    static func migrateDefaultsIfNeeded(
        destination: UserDefaults = .standard,
        sourceSuiteName: String = legacyDefaultsSuiteName,
        sourceFactory: (String) -> UserDefaults? = { UserDefaults(suiteName: $0) }
    ) -> Bool {
        if destination.integer(forKey: defaultsMigrationVersionKey) >= currentVersion {
            return false
        }
        guard let source = sourceFactory(sourceSuiteName) else {
            destination.set(currentVersion, forKey: defaultsMigrationVersionKey)
            return false
        }

        let sourceDict = source.dictionaryRepresentation()
        var copied = 0
        for (key, value) in sourceDict {
            if shouldSkipDefaultsKey(key) { continue }
            if destination.object(forKey: key) != nil { continue }
            destination.set(value, forKey: key)
            copied += 1
        }
        destination.set(currentVersion, forKey: defaultsMigrationVersionKey)
        return copied > 0
    }

    static func migrateAllIfNeeded(
        locations: CmuxConfigLocation = CmuxConfigLocation(),
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) {
        _ = migrateConfigDirectoryIfNeeded(
            locations: locations,
            fileManager: fileManager,
            defaults: defaults
        )
        _ = migrateDefaultsIfNeeded(destination: defaults)
    }

    static func shouldSkipDefaultsKey(_ key: String) -> Bool {
        if key.hasPrefix("ghosttyDock") { return true }
        for prefix in excludedDefaultsKeyPrefixes {
            if key.hasPrefix(prefix) { return true }
        }
        return false
    }
}
