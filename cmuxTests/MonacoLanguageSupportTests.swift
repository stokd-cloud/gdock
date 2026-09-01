import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("Monaco language support")
struct MonacoLanguageSupportTests {
    @Test("Common source extensions are Monaco-supported")
    func commonSourceExtensionsAreSupported() {
        for pathExtension in ["swift", "ts", "json", "py", "rs"] {
            #expect(
                MonacoLanguageSupport.isSupported(pathExtension: pathExtension),
                "Expected .\(pathExtension) to route to the Monaco editor."
            )
        }
    }

    @Test("Opaque and unknown extensions are not Monaco-supported")
    func opaqueExtensionsAreNotSupported() {
        for pathExtension in ["bin", "xyzzy"] {
            #expect(
                !MonacoLanguageSupport.isSupported(pathExtension: pathExtension),
                "Expected .\(pathExtension) to fall back to the native text editor."
            )
        }
    }

    @Test("Extension matching ignores case and a leading dot")
    func extensionMatchingIsLenient() {
        #expect(MonacoLanguageSupport.isSupported(pathExtension: ".Swift"))
        #expect(MonacoLanguageSupport.isSupported(pathExtension: "TSX"))
        #expect(MonacoLanguageSupport.isSupported(filePath: "/tmp/Example.YAML"))
        #expect(!MonacoLanguageSupport.isSupported(filePath: "/tmp/no-extension"))
    }

    /// Drift guard for [[AX-GDOCK-MONACO-EDITOR-ROUTING]].
    ///
    /// `MonacoLanguageSupport.supportedExtensions` is a hand-written mirror of
    /// the TypeScript `LANGUAGES` table. Adding a language on either side alone
    /// fails here, in both directions.
    @Test("Swift mirror matches the TypeScript LANGUAGES table")
    func swiftMirrorMatchesTypeScriptTable() throws {
        let typeScript = try Set(typeScriptExtensions())
        let swift = MonacoLanguageSupport.supportedExtensions

        let missingFromSwift = typeScript.subtracting(swift).sorted()
        let missingFromTypeScript = swift.subtracting(typeScript).sorted()

        #expect(
            missingFromSwift.isEmpty,
            "monacoLanguages.ts registers extensions the Swift mirror lacks: \(missingFromSwift)"
        )
        #expect(
            missingFromTypeScript.isEmpty,
            "The Swift mirror claims extensions monacoLanguages.ts does not register: \(missingFromTypeScript)"
        )
    }

    // MARK: - TypeScript table parsing

    /// Extracts every extension from the `LANGUAGES` array literal in
    /// `webviews/src/editor/monacoLanguages.ts`, normalized to the same shape
    /// as ``MonacoLanguageSupport/supportedExtensions`` (lowercased, no dot).
    private func typeScriptExtensions() throws -> [String] {
        let source = try String(contentsOf: monacoLanguagesURL(), encoding: .utf8)

        guard let tableStart = source.range(of: "const LANGUAGES: LanguageDef[] = [") else {
            Issue.record("Could not locate the LANGUAGES table in monacoLanguages.ts.")
            return []
        }
        guard let tableEnd = source.range(of: "\n];", range: tableStart.upperBound..<source.endIndex) else {
            Issue.record("Could not locate the end of the LANGUAGES table in monacoLanguages.ts.")
            return []
        }
        let table = String(source[tableStart.upperBound..<tableEnd.lowerBound])

        // Each entry looks like: extensions: [".ts", ".tsx"],
        let entryPattern = try NSRegularExpression(pattern: #"extensions:\s*\[([^\]]*)\]"#)
        let literalPattern = try NSRegularExpression(pattern: #""\.([^"]+)""#)

        var extensions: [String] = []
        let tableRange = NSRange(table.startIndex..<table.endIndex, in: table)
        for match in entryPattern.matches(in: table, range: tableRange) {
            guard let listRange = Range(match.range(at: 1), in: table) else { continue }
            let list = String(table[listRange])
            let listRangeNS = NSRange(list.startIndex..<list.endIndex, in: list)
            for literal in literalPattern.matches(in: list, range: listRangeNS) {
                guard let valueRange = Range(literal.range(at: 1), in: list) else { continue }
                extensions.append(String(list[valueRange]).lowercased())
            }
        }

        #expect(!extensions.isEmpty, "Parsed zero extensions from monacoLanguages.ts; the parser is broken.")
        return extensions
    }

    private func monacoLanguagesURL() throws -> URL {
        let fromFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("webviews/src/editor/monacoLanguages.ts")
        if FileManager.default.fileExists(atPath: fromFile.path) {
            return fromFile
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("webviews/src/editor/monacoLanguages.ts")
    }
}
