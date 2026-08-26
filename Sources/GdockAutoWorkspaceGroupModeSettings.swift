import Foundation
import CmuxSettings

/// Runtime accessors for `gdock.autoWorkspaceGroupMode`.
enum GdockAutoWorkspaceGroupModeSettings {
    static let catalogKey = SettingCatalog().gdock.autoWorkspaceGroupMode
    static let settingsKey = catalogKey.id
    static let userDefaultsKey = catalogKey.userDefaultsKey
    static let defaultEnabled = catalogKey.defaultValue
    static let commandId = "palette.toggleSetting.gdock.autoWorkspaceGroupMode"
    static let didChangeNotification = Notification.Name("gdock.autoWorkspaceGroupMode.didChange")

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

/// Runtime accessors for `gdock.rightSidebarStackedTabs`.
enum RightSidebarDockPresentationSettings {
    static let catalogKey = SettingCatalog().gdock.rightSidebarStackedTabs
    static let settingsKey = catalogKey.id
    static let userDefaultsKey = catalogKey.userDefaultsKey
    static let defaultEnabled = catalogKey.defaultValue
    static let commandId = "palette.toggleSetting.gdock.rightSidebarStackedTabs"
    static let didChangeNotification = Notification.Name("gdock.rightSidebarStackedTabs.didChange")

    static func isStackedTabsEnabled(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: userDefaultsKey) == nil {
            return defaultEnabled
        }
        return defaults.bool(forKey: userDefaultsKey)
    }

    static func setStackedTabsEnabled(
        _ enabled: Bool,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        defaults.set(enabled, forKey: userDefaultsKey)
        notificationCenter.post(name: didChangeNotification, object: nil)
    }
}
