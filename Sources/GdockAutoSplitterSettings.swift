import Foundation
import CmuxSettings

/// Runtime accessors for Auto Split settings: `gdock.autoSplitRows`,
/// `gdock.autoSplitColumns`, and `gdock.forceAutoSplitter`.
enum GdockAutoSplitterSettings {
    static let rowsKey = SettingCatalog().gdock.autoSplitRows
    static let columnsKey = SettingCatalog().gdock.autoSplitColumns
    static let forceKey = SettingCatalog().gdock.forceAutoSplitter

    static let minDimension = 1
    static let maxDimension = 6
    static let defaultRows = rowsKey.defaultValue
    static let defaultColumns = columnsKey.defaultValue
    static let defaultForceEnabled = forceKey.defaultValue

    static let forceCommandId = "palette.toggleSetting.gdock.forceAutoSplitter"
    static let autoSplitCommandId = "palette.gdock.autoSplit"
    static let didChangeNotification = Notification.Name("gdock.autoSplitter.didChange")

    struct Shape: Equatable, Sendable {
        let rows: Int
        let cols: Int

        var cellCount: Int { rows * cols }
        var isNoOp: Bool { rows == 1 && cols == 1 }
        var isQuad: Bool { rows == 2 && cols == 2 }

        static func clamped(rows: Int, cols: Int) -> Shape {
            Shape(
                rows: min(max(rows, minDimension), maxDimension),
                cols: min(max(cols, minDimension), maxDimension)
            )
        }
    }

    static func rows(defaults: UserDefaults = .standard) -> Int {
        clampedDimension(defaults: defaults, key: rowsKey, fallback: defaultRows)
    }

    static func columns(defaults: UserDefaults = .standard) -> Int {
        clampedDimension(defaults: defaults, key: columnsKey, fallback: defaultColumns)
    }

    static func shape(defaults: UserDefaults = .standard) -> Shape {
        Shape.clamped(rows: rows(defaults: defaults), cols: columns(defaults: defaults))
    }

    static func isForceEnabled(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: forceKey.userDefaultsKey) == nil {
            return defaultForceEnabled
        }
        return defaults.bool(forKey: forceKey.userDefaultsKey)
    }

    static func setRows(
        _ value: Int,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        defaults.set(min(max(value, minDimension), maxDimension), forKey: rowsKey.userDefaultsKey)
        notificationCenter.post(name: didChangeNotification, object: nil)
    }

    static func setColumns(
        _ value: Int,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        defaults.set(min(max(value, minDimension), maxDimension), forKey: columnsKey.userDefaultsKey)
        notificationCenter.post(name: didChangeNotification, object: nil)
    }

    static func setForceEnabled(
        _ enabled: Bool,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        defaults.set(enabled, forKey: forceKey.userDefaultsKey)
        notificationCenter.post(name: didChangeNotification, object: nil)
    }

    static func autoSplitTooltip(shape: Shape = shape()) -> String {
        String(
            format: String(
                localized: "workspace.tooltip.autoSplit",
                defaultValue: "Auto Split (%d rows × %d columns)"
            ),
            locale: .current,
            shape.rows,
            shape.cols
        )
    }

    private static func clampedDimension(
        defaults: UserDefaults,
        key: DefaultsKey<Int>,
        fallback: Int
    ) -> Int {
        guard let stored = defaults.object(forKey: key.userDefaultsKey) else {
            return fallback
        }
        let raw: Int
        if let number = stored as? NSNumber {
            raw = number.intValue
        } else if let string = stored as? String, let parsed = Int(string) {
            raw = parsed
        } else {
            raw = defaults.integer(forKey: key.userDefaultsKey)
        }
        return min(max(raw, minDimension), maxDimension)
    }
}
