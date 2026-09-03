import CmuxSettings
import Foundation

/// Which kinds the Work panel shows.
enum StokdWorkKindFilter: String, CaseIterable, Equatable, Sendable {
    case all
    case tasks
    case projects
    case todos

    var kind: StokdWorkItemKind? {
        switch self {
        case .all: return nil
        case .tasks: return .task
        case .projects: return .project
        case .todos: return .todo
        }
    }
}

/// Field the Work panel sorts by. Sorting is client-side; no `list` verb sorts
/// across kinds.
enum StokdWorkSortField: String, CaseIterable, Equatable, Sendable {
    case updatedAt = "updated_at"
    case createdAt = "created_at"
}

/// Runtime accessors for the persisted `gdock.workPanel.*` preferences.
///
/// These are preferences, not gates: the Work panel is always available.
enum StokdWorkPanelSettings {
    static let kindFilterKey = SettingCatalog().gdock.workPanelKindFilter
    static let showCompletedKey = SettingCatalog().gdock.workPanelShowCompleted
    static let sortFieldKey = SettingCatalog().gdock.workPanelSortField
    static let sortAscendingKey = SettingCatalog().gdock.workPanelSortAscending
    static let detailPaneHeightKey = SettingCatalog().gdock.workPanelDetailHeight

    static let showCompletedCommandId = "palette.toggleSetting.gdock.workPanel.showCompleted"
    static let didChangeNotification = Notification.Name("gdock.workPanel.didChange")

    static var defaultShowCompleted: Bool { showCompletedKey.defaultValue }

    static var allUserDefaultsKeys: [String] {
        [
            kindFilterKey.userDefaultsKey,
            showCompletedKey.userDefaultsKey,
            sortFieldKey.userDefaultsKey,
            sortAscendingKey.userDefaultsKey,
        ]
    }

    static func kindFilter(defaults: UserDefaults = .standard) -> StokdWorkKindFilter {
        guard let raw = defaults.string(forKey: kindFilterKey.userDefaultsKey),
              let filter = StokdWorkKindFilter(rawValue: raw) else {
            return StokdWorkKindFilter(rawValue: kindFilterKey.defaultValue) ?? .all
        }
        return filter
    }

    static func setKindFilter(_ filter: StokdWorkKindFilter, defaults: UserDefaults = .standard) {
        defaults.set(filter.rawValue, forKey: kindFilterKey.userDefaultsKey)
    }

    static func showCompleted(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: showCompletedKey.userDefaultsKey) == nil {
            return showCompletedKey.defaultValue
        }
        return defaults.bool(forKey: showCompletedKey.userDefaultsKey)
    }

    static func setShowCompleted(
        _ show: Bool,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        defaults.set(show, forKey: showCompletedKey.userDefaultsKey)
        notificationCenter.post(name: didChangeNotification, object: nil)
    }

    static func sortField(defaults: UserDefaults = .standard) -> StokdWorkSortField {
        guard let raw = defaults.string(forKey: sortFieldKey.userDefaultsKey),
              let field = StokdWorkSortField(rawValue: raw) else {
            return StokdWorkSortField(rawValue: sortFieldKey.defaultValue) ?? .updatedAt
        }
        return field
    }

    static func setSortField(_ field: StokdWorkSortField, defaults: UserDefaults = .standard) {
        defaults.set(field.rawValue, forKey: sortFieldKey.userDefaultsKey)
    }

    static func sortAscending(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: sortAscendingKey.userDefaultsKey) == nil {
            return sortAscendingKey.defaultValue
        }
        return defaults.bool(forKey: sortAscendingKey.userDefaultsKey)
    }

    static func setSortAscending(_ ascending: Bool, defaults: UserDefaults = .standard) {
        defaults.set(ascending, forKey: sortAscendingKey.userDefaultsKey)
    }

    static var defaultDetailPaneHeight: Double { detailPaneHeightKey.defaultValue }
    static let minimumDetailPaneHeight: Double = 120

    static func detailPaneHeight(defaults: UserDefaults = .standard) -> Double {
        guard defaults.object(forKey: detailPaneHeightKey.userDefaultsKey) != nil else {
            return detailPaneHeightKey.defaultValue
        }
        let stored = defaults.double(forKey: detailPaneHeightKey.userDefaultsKey)
        return stored >= minimumDetailPaneHeight ? stored : detailPaneHeightKey.defaultValue
    }

    static func setDetailPaneHeight(_ height: Double, defaults: UserDefaults = .standard) {
        defaults.set(max(minimumDetailPaneHeight, height), forKey: detailPaneHeightKey.userDefaultsKey)
    }
}
