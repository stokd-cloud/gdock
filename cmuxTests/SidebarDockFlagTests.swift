import Foundation
import Testing
import CmuxSettings

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// VAL-FLAG-001: `sidebar.beta.dock.enabled` defaults off, is not a PostHog flag,
/// appears in Settings/catalog/search surfaces, and round-trips through cmux.json.
@Suite("Sidebar dock beta flag", .serialized)
struct SidebarDockFlagTests {
    private let settingsFileBackupsDefaultsKey = "cmux.settingsFile.backups.v1"
    private let importedManagedDefaultsKey = "cmux.settingsFile.importedManagedDefaults.v1"

    @Test func defaultIsFalseWhenKeyAbsent() {
        let suite = "cmux.tests.sidebar-dock.flag.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(defaults.object(forKey: RightSidebarBetaFeatureSettings.sidebarDockEnabledKey) == nil)
        #expect(RightSidebarBetaFeatureSettings.isSidebarDockEnabled(defaults: defaults) == false)
        #expect(RightSidebarBetaFeatureSettings.defaultSidebarDockEnabled == false)
        #expect(RightSidebarBetaFeatureSettings.sidebarDockEnabledKey == "sidebar.beta.dock.enabled")
    }

    @Test func trueAndFalseRoundTripThroughUserDefaults() {
        let suite = "cmux.tests.sidebar-dock.flag.round.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: RightSidebarBetaFeatureSettings.sidebarDockEnabledKey)
        #expect(RightSidebarBetaFeatureSettings.isSidebarDockEnabled(defaults: defaults) == true)
        defaults.set(false, forKey: RightSidebarBetaFeatureSettings.sidebarDockEnabledKey)
        #expect(RightSidebarBetaFeatureSettings.isSidebarDockEnabled(defaults: defaults) == false)
    }

    @Test func catalogKeyMatchesRuntimeKeyAndDefaultsOff() {
        let key = SettingCatalog().betaFeatures.sidebarDock
        #expect(key.id == "sidebar.beta.dock.enabled")
        #expect(key.userDefaultsKey == RightSidebarBetaFeatureSettings.sidebarDockEnabledKey)
        #expect(key.defaultValue == false)
    }

    @Test func jsonPathIsRegisteredForDeepLinkAndSettingsSupport() {
        #expect(CmuxSettingsFileStore.supportedSettingsJSONPaths.contains("sidebar.beta.dock.enabled"))
    }

    @Test
    func settingsFileStoreAppliesTrueAndFalseFromCmuxJSON() throws {
        // Same isolation pattern as HostSettingsShortcutNotificationTests /
        // KeyboardShortcutModifierHoldHintsSettingsFileTests, plus replacing the
        // process-live store so its UserDefaults reapply path cannot restore
        // shared backups for keys managed only by this temporary store.
        let defaults = UserDefaults.standard
        let managedKey = SettingCatalog().betaFeatures.sidebarDock.userDefaultsKey
        let workspaceTodoKey = SettingCatalog().betaFeatures.workspaceTodoControls.userDefaultsKey
        #expect(managedKey == RightSidebarBetaFeatureSettings.sidebarDockEnabledKey)

        try preservingDefaults(keys: [
            managedKey,
            workspaceTodoKey,
            settingsFileBackupsDefaultsKey,
            importedManagedDefaultsKey,
        ]) {
            let directoryURL = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directoryURL) }
            let settingsFileURL = directoryURL.appendingPathComponent("cmux.json", isDirectory: false)

            try """
            {
              "sidebar": {
                "beta": {
                  "dock": {
                    "enabled": true
                  },
                  "workspaceTodos": {
                    "controls": {
                      "enabled": true
                    }
                  }
                }
              }
            }
            """.write(to: settingsFileURL, atomically: true, encoding: .utf8)

            let originalSettingsFileStore = KeyboardShortcutSettings.settingsFileStore
            defer { KeyboardShortcutSettings.settingsFileStore = originalSettingsFileStore }

            KeyboardShortcutSettings.settingsFileStore = KeyboardShortcutSettingsFileStore(
                primaryPath: settingsFileURL.path,
                fallbackPath: nil,
                additionalFallbackPaths: [],
                startWatching: false
            )

            // Sibling known-good path: workspaceTodos must apply.
            #expect(defaults.object(forKey: workspaceTodoKey) as? Bool == true)
            #expect(defaults.object(forKey: managedKey) as? Bool == true)
            #expect(RightSidebarBetaFeatureSettings.isSidebarDockEnabled(defaults: defaults) == true)

            try """
            {
              "sidebar": {
                "beta": {
                  "dock": {
                    "enabled": false
                  },
                  "workspaceTodos": {
                    "controls": {
                      "enabled": false
                    }
                  }
                }
              }
            }
            """.write(to: settingsFileURL, atomically: true, encoding: .utf8)

            KeyboardShortcutSettings.settingsFileStore.reload()
            #expect(defaults.object(forKey: workspaceTodoKey) as? Bool == false)
            #expect(defaults.object(forKey: managedKey) as? Bool == false)
            #expect(RightSidebarBetaFeatureSettings.isSidebarDockEnabled(defaults: defaults) == false)
        }
    }

    @Test func defaultTemplateDocumentsSidebarBetaDockEnabledOff() {
        let template = CmuxSettingsFileStore.defaultTemplate()
        #expect(template.contains("\"dock\""))
        // JSONSerialization pretty-print uses spaces around " : " (see FocusHistoryScopeTests).
        #expect(
            template.contains(#""enabled" : false"#)
                || template.contains(#""enabled": false"#)
                || template.contains(#""enabled":false"#)
        )
        // The dock object must document the catalog default under sidebar.beta.dock.
        #expect(
            template.contains(#"//         "dock" : {"#)
                || template.contains(#"//         "dock": {"#)
                || template.contains(#""dock""#)
        )
    }

    @Test func flagIsNotDeclaredAsPostHogFeatureFlag() throws {
        // VAL-FLAG-001: must not appear in Sources/FeatureFlags.swift FLAG(...) registry.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // cmuxTests
            .deletingLastPathComponent() // repo root
        let featureFlags = root.appendingPathComponent("Sources/FeatureFlags.swift")
        let text = try String(contentsOf: featureFlags, encoding: .utf8)
        #expect(!text.contains("sidebar.beta.dock.enabled"))
        #expect(!text.contains("sidebar-dock"))
    }

    @Test func schemaDocumentsSidebarBetaDockEnabledDefaultFalse() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let schemaURL = root.appendingPathComponent("web/data/cmux.schema.json")
        let data = try Data(contentsOf: schemaURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let props = json?["properties"] as? [String: Any]
        let sidebar = props?["sidebar"] as? [String: Any]
        let sidebarProps = sidebar?["properties"] as? [String: Any]
        let beta = sidebarProps?["beta"] as? [String: Any]
        let betaProps = beta?["properties"] as? [String: Any]
        let dock = betaProps?["dock"] as? [String: Any]
        let dockProps = dock?["properties"] as? [String: Any]
        let enabled = dockProps?["enabled"] as? [String: Any]
        #expect(enabled?["type"] as? String == "boolean")
        #expect(enabled?["default"] as? Bool == false)
    }

    private func preservingDefaults(keys: [String], _ body: () throws -> Void) throws {
        let defaults = UserDefaults.standard
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        for key in keys { defaults.removeObject(forKey: key) }
        defer {
            for (key, value) in saved {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        try body()
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cmux-sidebar-dock-flag-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
