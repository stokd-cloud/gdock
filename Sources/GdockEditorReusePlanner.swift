import Foundation

/// Chooses whether Files/Find should focus an already-open Monaco editor
/// instead of spawning another `cmux edit` split.
enum GdockEditorReusePlanner {
    /// Returns the open editor panel for `filePath`, or `nil` to launch a new one.
    static func panelIdToFocus(
        filePath: String,
        openEditors: [(panelId: UUID, filePath: String)]
    ) -> UUID? {
        let wanted = Self.standardizedPath(filePath)
        return openEditors.first(where: { Self.standardizedPath($0.filePath) == wanted })?.panelId
    }

    static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

/// Find routing for the focused main panel.
enum GdockEditorFindDispatch {
    enum Target: Equatable, Sendable {
        /// Monaco's own find widget, which searches the visible buffer.
        case monacoWidget
        /// WKWebView find-in-page used by ordinary browser surfaces.
        case browserFindInPage
    }

    static func target(editorPageActive: Bool) -> Target {
        editorPageActive ? .monacoWidget : .browserFindInPage
    }
}
