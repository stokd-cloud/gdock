import AppKit
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("File explorer Finder-style file copy/paste/trash")
struct FileExplorerFileClipboardTests {
    private func item(_ path: String, isDirectory: Bool) -> FileExplorerFileClipboard.Item {
        FileExplorerFileClipboard.Item(path: path, isDirectory: isDirectory)
    }

    // MARK: - Destination

    @Test func destinationIsSelectedDirectory() {
        let dest = FileExplorerFileClipboard.destinationDirectory(
            rootPath: "/repo",
            selections: [item("/repo/src", isDirectory: true)],
            anchor: item("/repo/src", isDirectory: true)
        )
        #expect(dest == "/repo/src")
    }

    @Test func destinationIsParentOfSelectedFile() {
        let dest = FileExplorerFileClipboard.destinationDirectory(
            rootPath: "/repo",
            selections: [item("/repo/README.md", isDirectory: false)],
            anchor: item("/repo/README.md", isDirectory: false)
        )
        #expect(dest == "/repo")
    }

    @Test func destinationFallsBackToRootWhenSelectionIsEmpty() {
        let dest = FileExplorerFileClipboard.destinationDirectory(
            rootPath: "/repo",
            selections: [],
            anchor: nil
        )
        #expect(dest == "/repo")
    }

    @Test func pastingACopiedDirectoryWhileSelectedUsesSiblingDestination() {
        let source = item("/repo/src", isDirectory: true)
        let proposed = FileExplorerFileClipboard.destinationDirectory(
            rootPath: "/repo",
            selections: [source],
            anchor: source
        )
        let resolved = FileExplorerFileClipboard.resolvedPasteDestination(
            proposed: proposed,
            sources: [source]
        )
        #expect(resolved == "/repo")
    }

    // MARK: - Unique names

    @Test func uniqueNameKeepsOriginalWhenFree() {
        var occupied = Set<String>()
        #expect(FileExplorerFileClipboard.uniqueFileName("a.txt", occupied: &occupied) == "a.txt")
        #expect(occupied.contains("a.txt"))
    }

    @Test func uniqueNameUsesFinderCopySuffix() {
        var occupied: Set<String> = ["a.txt"]
        #expect(FileExplorerFileClipboard.uniqueFileName("a.txt", occupied: &occupied) == "a copy.txt")
        #expect(FileExplorerFileClipboard.uniqueFileName("a.txt", occupied: &occupied) == "a copy 2.txt")
        #expect(occupied.contains("a copy.txt"))
        #expect(occupied.contains("a copy 2.txt"))
    }

    @Test func uniqueNameForExtensionlessFile() {
        var occupied: Set<String> = ["Makefile"]
        #expect(FileExplorerFileClipboard.uniqueFileName("Makefile", occupied: &occupied) == "Makefile copy")
        #expect(FileExplorerFileClipboard.uniqueFileName("Makefile", occupied: &occupied) == "Makefile copy 2")
    }

    @Test func uniqueNameForDirectory() {
        var occupied: Set<String> = ["src"]
        #expect(FileExplorerFileClipboard.uniqueFileName("src", occupied: &occupied) == "src copy")
        #expect(FileExplorerFileClipboard.uniqueFileName("src", occupied: &occupied) == "src copy 2")
    }

    @Test func plannedCopiesOccupyNamesWithinTheSameBatch() {
        let dest = URL(fileURLWithPath: "/repo/out", isDirectory: true)
        let copies = FileExplorerFileClipboard.plannedCopies(
            sources: [
                URL(fileURLWithPath: "/a/readme.md"),
                URL(fileURLWithPath: "/b/readme.md"),
            ],
            destinationDirectory: dest,
            occupiedNames: []
        )
        #expect(copies.map(\.destination.lastPathComponent) == ["readme.md", "readme copy.md"])
    }

    // MARK: - Gating / skip

    @Test func copyAndPasteDisabledForRemoteProvider() {
        #expect(FileExplorerFileClipboard.canCopy(isLocal: false, selectedPaths: ["/repo/a.txt"]) == false)
        #expect(FileExplorerFileClipboard.canPaste(isLocal: false, pasteboardHasFiles: true) == false)
    }

    @Test func copyRequiresLocalSelection() {
        #expect(FileExplorerFileClipboard.canCopy(isLocal: true, selectedPaths: []) == false)
        #expect(FileExplorerFileClipboard.canCopy(isLocal: true, selectedPaths: ["/repo/a.txt"]) == true)
    }

    @Test func pasteRequiresLocalFileURLs() {
        #expect(FileExplorerFileClipboard.canPaste(isLocal: true, pasteboardHasFiles: false) == false)
        #expect(FileExplorerFileClipboard.canPaste(isLocal: true, pasteboardHasFiles: true) == true)
    }

    @Test func skipsPastingADirectoryIntoItselfOrADescendant() {
        let source = URL(fileURLWithPath: "/repo/src", isDirectory: true)
        #expect(
            FileExplorerFileClipboard.shouldSkip(
                source: source,
                destinationDirectory: URL(fileURLWithPath: "/repo/src", isDirectory: true)
            )
        )
        #expect(
            FileExplorerFileClipboard.shouldSkip(
                source: source,
                destinationDirectory: URL(fileURLWithPath: "/repo/src/inner", isDirectory: true)
            )
        )
        #expect(
            !FileExplorerFileClipboard.shouldSkip(
                source: source,
                destinationDirectory: URL(fileURLWithPath: "/repo/other", isDirectory: true)
            )
        )
    }

    // MARK: - FileManager copies

    @Test func copiesFileAndDirectoryWithoutOverwritingOriginal() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gdock-files-clipboard-\(UUID().uuidString)", isDirectory: true)
        let srcDir = root.appendingPathComponent("src", isDirectory: true)
        let destDir = root.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = srcDir.appendingPathComponent("note.txt")
        try Data("hello".utf8).write(to: file)
        let folder = srcDir.appendingPathComponent("pkg", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("inner".utf8).write(to: folder.appendingPathComponent("inner.txt"))

        let copies = FileExplorerFileClipboard.plannedCopies(
            sources: [file, folder],
            destinationDirectory: destDir,
            occupiedNames: []
        )
        try FileExplorerFileClipboard.performCopies(copies, fileManager: .default)

        let copiedFile = destDir.appendingPathComponent("note.txt")
        let copiedFolderFile = destDir.appendingPathComponent("pkg").appendingPathComponent("inner.txt")
        #expect(try String(contentsOf: copiedFile, encoding: .utf8) == "hello")
        #expect(try String(contentsOf: copiedFolderFile, encoding: .utf8) == "inner")
        #expect(try String(contentsOf: file, encoding: .utf8) == "hello")
        #expect(FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func sameFolderPasteGetsCopySuffixInsteadOfOverwrite() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gdock-files-clipboard-same-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("a.txt")
        try Data("orig".utf8).write(to: file)
        let occupied = Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
        let copies = FileExplorerFileClipboard.plannedCopies(
            sources: [file],
            destinationDirectory: dir,
            occupiedNames: occupied
        )
        try FileExplorerFileClipboard.performCopies(copies, fileManager: .default)

        #expect(copies.first?.destination.lastPathComponent == "a copy.txt")
        #expect(try String(contentsOf: file, encoding: .utf8) == "orig")
        #expect(try String(contentsOf: dir.appendingPathComponent("a copy.txt"), encoding: .utf8) == "orig")
    }

    // MARK: - Pasteboard

    @Test func writtenFileURLsAreReadableByPasteboardFileURLReader() {
        let pasteboard = NSPasteboard(name: .init("gdock.files.clipboard.\(UUID().uuidString)"))
        defer {
            pasteboard.clearContents()
            pasteboard.releaseGlobally()
        }
        let url = URL(fileURLWithPath: "/tmp/gdock-clipboard-sample.txt")
        FileExplorerFileClipboard.writeFileURLs([url], to: pasteboard)
        #expect(PasteboardFileURLReader.fileURLs(from: pasteboard).map(\.path) == [url.path])
    }

    // MARK: - Store refresh

    @Test @MainActor func refreshDirectoryReloadsDestinationChildren() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gdock-files-clipboard-refresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("a".utf8).write(to: root.appendingPathComponent("a.txt"))

        let store = FileExplorerStore()
        store.setProviderForTesting(LocalFileExplorerProvider())
        store.setRootPath(root.path)
        try await waitFor("root loaded") {
            store.rootNodes.map(\.name) == ["a.txt"]
        }

        try Data("b".utf8).write(to: root.appendingPathComponent("b.txt"))
        store.refreshDirectory(at: root.path)
        try await waitFor("destination listing includes pasted file") {
            Set(store.rootNodes.map(\.name)) == ["a.txt", "b.txt"]
        }
    }

    // MARK: - Trash gating

    @Test func trashDisabledForRemoteProvider() {
        #expect(
            FileExplorerFileTrash.canTrash(
                isLocal: false,
                selectedPaths: ["/repo/a.txt"],
                rootPath: "/repo"
            ) == false
        )
    }

    @Test func trashRequiresLocalSelectionInsideRoot() {
        #expect(
            FileExplorerFileTrash.canTrash(
                isLocal: true,
                selectedPaths: [],
                rootPath: "/repo"
            ) == false
        )
        #expect(
            FileExplorerFileTrash.canTrash(
                isLocal: true,
                selectedPaths: ["/repo"],
                rootPath: "/repo"
            ) == false
        )
        #expect(
            FileExplorerFileTrash.canTrash(
                isLocal: true,
                selectedPaths: ["/repo/a.txt"],
                rootPath: "/repo"
            ) == true
        )
    }

    @Test func refusesWorkspaceRootAndPathsOutsideRoot() {
        #expect(!FileExplorerFileTrash.isStrictlyInsideRoot("/repo", rootPath: "/repo"))
        #expect(!FileExplorerFileTrash.isStrictlyInsideRoot("/repo/", rootPath: "/repo"))
        #expect(!FileExplorerFileTrash.isStrictlyInsideRoot("/other/a.txt", rootPath: "/repo"))
        #expect(FileExplorerFileTrash.isStrictlyInsideRoot("/repo/a.txt", rootPath: "/repo"))
        #expect(FileExplorerFileTrash.isStrictlyInsideRoot("/repo/src/inner", rootPath: "/repo"))
        #expect(
            FileExplorerFileTrash.trashablePaths(
                selectedPaths: ["/repo", "/other/a.txt", "/repo/a.txt"],
                rootPath: "/repo"
            ) == ["/repo/a.txt"]
        )
    }

    @Test func pruneNestedKeepsAncestorOnly() {
        #expect(
            FileExplorerFileTrash.pruneNested([
                "/repo/src/a.txt",
                "/repo/src",
                "/repo/README.md",
            ]) == ["/repo/README.md", "/repo/src"]
        )
    }

    // MARK: - FileManager trash

    @Test func trashesFileAndDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gdock-files-trash-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("note.txt")
        try Data("hello".utf8).write(to: file)
        let folder = root.appendingPathComponent("pkg", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("inner".utf8).write(to: folder.appendingPathComponent("inner.txt"))

        let parents = try FileExplorerFileTrash.trash(
            isLocal: true,
            rootPath: root.path,
            selectedPaths: [file.path, folder.path]
        )

        #expect(parents.map(standardized) == [standardized(root.path)])
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(FileManager.default.fileExists(atPath: root.path))
    }

    @Test func nestedSelectionTrashesAncestorOnce() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gdock-files-trash-nested-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let child = folder.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: child)
        let sibling = root.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sibling)

        let parents = try FileExplorerFileTrash.trash(
            isLocal: true,
            rootPath: root.path,
            selectedPaths: [folder.path, child.path]
        )

        #expect(parents.map(standardized) == [standardized(root.path)])
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(!FileManager.default.fileExists(atPath: child.path))
        #expect(try String(contentsOf: sibling, encoding: .utf8) == "keep")
    }

    @Test func doesNotTrashWhenRemoteEvenIfPathsLookLocal() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gdock-files-trash-remote-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: file)

        let parents = try FileExplorerFileTrash.trash(
            isLocal: false,
            rootPath: root.path,
            selectedPaths: [file.path]
        )
        #expect(parents.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    // MARK: - Store refresh

    @Test @MainActor func refreshDirectoryRemovesTrashedChild() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gdock-files-trash-refresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let keep = root.appendingPathComponent("keep.txt")
        let gone = root.appendingPathComponent("gone.txt")
        try Data("keep".utf8).write(to: keep)
        try Data("gone".utf8).write(to: gone)

        let store = FileExplorerStore()
        store.setProviderForTesting(LocalFileExplorerProvider())
        store.setRootPath(root.path)
        try await waitFor("root loaded") {
            Set(store.rootNodes.map(\.name)) == ["gone.txt", "keep.txt"]
        }

        let parents = try FileExplorerFileTrash.trash(
            isLocal: true,
            rootPath: root.path,
            selectedPaths: [gone.path]
        )
        #expect(parents.map(standardized) == [standardized(root.path)])
        store.refreshDirectory(at: root.path)
        try await waitFor("trashed file disappears from listing") {
            store.rootNodes.map(\.name) == ["keep.txt"]
        }
    }

    private func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func waitFor(
        _ description: String,
        timeout: TimeInterval = 5.0,
        _ condition: @MainActor @escaping @Sendable () -> Bool
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                while !Task.isCancelled {
                    if await MainActor.run(body: condition) {
                        return
                    }
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw WaitTimeout(description: description)
            }
            _ = try await group.next()
            group.cancelAll()
        }
    }

    private struct WaitTimeout: Error, CustomStringConvertible {
        let description: String
    }
}
