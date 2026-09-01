import Foundation

/// The set of file extensions the bundled Monaco editor can syntax-highlight.
///
/// This is a hand-maintained mirror of the `LANGUAGES` table in
/// `webviews/src/editor/monacoLanguages.ts`. Swift cannot import that
/// TypeScript module, so the two lists are kept in sync by
/// `MonacoLanguageSupportTests.swiftMirrorMatchesTypeScriptTable`, which parses
/// the TS source and fails the build on any drift in either direction.
///
/// Per [[AX-GDOCK-MONACO-EDITOR-ROUTING]] this is the only authority on
/// "can Monaco handle this file"; panels ask ``FilePreviewEditorHost`` rather
/// than consulting this type or inlining their own extension checks.
enum MonacoLanguageSupport {
    /// Lowercased extensions **without** a leading dot.
    static let supportedExtensions: Set<String> = []

    /// Whether Monaco has a registered grammar for `pathExtension`.
    ///
    /// - Parameter pathExtension: An extension with or without a leading dot;
    ///   matching is case-insensitive.
    static func isSupported(pathExtension: String) -> Bool {
        supportedExtensions.contains(normalize(pathExtension))
    }

    /// Whether Monaco has a registered grammar for the file at `filePath`.
    static func isSupported(filePath: String) -> Bool {
        isSupported(pathExtension: (filePath as NSString).pathExtension)
    }

    private static func normalize(_ pathExtension: String) -> String {
        var value = pathExtension.lowercased()
        while value.hasPrefix(".") {
            value.removeFirst()
        }
        return value
    }
}
