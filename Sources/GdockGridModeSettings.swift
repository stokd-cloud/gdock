import Foundation
import CmuxSettings

/// Runtime accessors for `gdock.gridMode` and `gdock.gridModeShape`.
///
/// Grid Mode enforces one split shape on every workspace: cells that were
/// never activated hold unspawned terminals, Cmd+T fills the next free cell
/// (or creates a new workspace when the grid is full), and the shape chosen
/// in the titlebar grid picker is remembered across restarts.
enum GdockGridModeSettings {
    static let catalogKey = SettingCatalog().gdock.gridMode
    static let settingsKey = catalogKey.id
    static let userDefaultsKey = catalogKey.userDefaultsKey
    static let defaultEnabled = catalogKey.defaultValue
    static let commandId = "palette.toggleSetting.gdock.gridMode"

    static let shapeCatalogKey = SettingCatalog().gdock.gridModeShape
    static let shapeSettingsKey = shapeCatalogKey.id
    static let shapeUserDefaultsKey = shapeCatalogKey.userDefaultsKey

    /// Posted after either the mode flag or the shape changes.
    static let didChangeNotification = Notification.Name("gdock.gridMode.didChange")

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

    static func shape(defaults: UserDefaults = .standard) -> GdockGridShape {
        guard let raw = defaults.string(forKey: shapeUserDefaultsKey),
              let shape = GdockGridShape(encoded: raw) else {
            return GdockGridShape(encoded: shapeCatalogKey.defaultValue) ?? .quad
        }
        return shape
    }

    static func setShape(
        _ shape: GdockGridShape,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        defaults.set(shape.encoded, forKey: shapeUserDefaultsKey)
        notificationCenter.post(name: didChangeNotification, object: nil)
    }
}
