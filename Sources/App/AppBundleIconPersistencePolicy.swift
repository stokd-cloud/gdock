import Foundation

enum AppIconRuntimeOverride {
    static let didChangeNotification = Notification.Name("cloud.stokd.ghostty-dock.iconDidChange")

    /// Raster override used only when the user pins Light or Dark in Settings.
    /// Automatic returns nil so macOS renders `AppIcon.icon` (Default/Dark/Clear/Tinted).
    static func rasterResourceName(modeRawValue: String?) -> String? {
        switch modeRawValue {
        case "light":
            return "AppIconLight"
        case "dark":
            return "AppIconDark"
        default:
            return nil
        }
    }
}

enum AppBundleIconPersistencePolicy {
    private static let stableReleaseBundleIdentifier = "cloud.stokd.ghostty-dock"
    private static let stableReleaseAppBundleName = "cmux.app"
    static let disablePersistenceArgument = "--cmux-disable-bundle-icon-persistence"
    static let disablePersistenceDefaultsKey = "cmuxDisableBundleIconPersistence"

    static func updateDisableDefault(defaults: UserDefaults, launchArguments: [String]) {
        defaults.set(
            launchArguments.contains(disablePersistenceArgument),
            forKey: disablePersistenceDefaultsKey
        )
    }

    static func shouldPersist(
        bundleIdentifier: String?,
        appBundleLastPathComponent: String?,
        persistenceDisabled: Bool = false
    ) -> Bool {
        guard !persistenceDisabled else {
            return false
        }

        // Channel variants own their identity through build-time bundle metadata.
        // Persisted Finder icons would override that metadata and can leak into
        // packaged artifacts after CI smoke launches the app bundle.
        return bundleIdentifier == stableReleaseBundleIdentifier
            && appBundleLastPathComponent == stableReleaseAppBundleName
    }
}
