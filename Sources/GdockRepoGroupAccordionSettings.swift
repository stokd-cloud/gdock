import Foundation
import CmuxSettings

/// Runtime accessors for `gdock.repoGroupAccordion`.
///
/// Mirrors ``GdockAutoWorkspaceGroupModeSettings`` so both gdock workspace-group
/// features read their setting the same way.
enum GdockRepoGroupAccordionSettings {
    static let catalogKey = SettingCatalog().gdock.repoGroupAccordion
    static let settingsKey = catalogKey.id
    static let userDefaultsKey = catalogKey.userDefaultsKey
    static let defaultEnabled = catalogKey.defaultValue
    static let commandId = "palette.toggleSetting.gdock.repoGroupAccordion"
    static let didChangeNotification = Notification.Name("gdock.repoGroupAccordion.didChange")

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: userDefaultsKey) == nil {
            return defaultEnabled
        }
        return defaults.bool(forKey: userDefaultsKey)
    }

    static func setEnabled(
        _ enabled: Bool,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        defaults.set(enabled, forKey: userDefaultsKey)
        notificationCenter.post(name: didChangeNotification, object: nil)
    }
}

/// Runtime accessors for `gdock.repoGroupQuadCommands`.
enum GdockRepoGroupQuadCommandSettings {
    static let catalogKey = SettingCatalog().gdock.repoGroupQuadCommands
    static let settingsKey = catalogKey.id
    static let userDefaultsKey = catalogKey.userDefaultsKey

    /// The configured override, or an empty list when unset — the planner
    /// treats anything that is not exactly four usable commands as "use the
    /// stokd defaults".
    static func overrideCommands(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: userDefaultsKey) ?? catalogKey.defaultValue
    }
}

/// Runtime accessors for `gdock.stokdRepoDetailURLTemplate`.
enum GdockStokdRepoDetailSettings {
    static let catalogKey = SettingCatalog().gdock.stokdRepoDetailURLTemplate
    static let settingsKey = catalogKey.id
    static let userDefaultsKey = catalogKey.userDefaultsKey

    /// The configured path template, falling back to the default when unset or
    /// blanked out.
    static func pathTemplate(defaults: UserDefaults = .standard) -> String {
        let stored = defaults.string(forKey: userDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stored, !stored.isEmpty else { return catalogKey.defaultValue }
        return stored
    }
}
