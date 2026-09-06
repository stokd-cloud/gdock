import AppKit
import Foundation

/// Finder-style file copy/paste for the Files pane. Copy Path remains a
/// separate string action; this type always writes file URLs.
struct FileExplorerFileClipboard {
    struct Item: Equatable, Sendable {
        var path: String
        var isDirectory: Bool
    }

    struct PlannedCopy: Equatable, Sendable {
        var source: URL
        var destination: URL
    }

    static func canCopy(isLocal: Bool, selectedPaths: [String]) -> Bool {
        isLocal && !selectedPaths.isEmpty
    }

    static func canPaste(isLocal: Bool, pasteboardHasFiles: Bool) -> Bool {
        isLocal && pasteboardHasFiles
    }

    static func destinationDirectory(
        rootPath: String,
        selections: [Item],
        anchor: Item?
    ) -> String {
        let focus = anchor ?? selections.first
        guard let focus else { return rootPath }
        if focus.isDirectory {
            return focus.path
        }
        let parent = (focus.path as NSString).deletingLastPathComponent
        return parent.isEmpty ? rootPath : parent
    }

    static func resolvedPasteDestination(proposed: String, sources: [Item]) -> String {
        let proposedPath = URL(fileURLWithPath: proposed).standardizedFileURL.path
        if sources.contains(where: { URL(fileURLWithPath: $0.path).standardizedFileURL.path == proposedPath }) {
            let parent = URL(fileURLWithPath: proposedPath).deletingLastPathComponent().path
            return parent.isEmpty ? proposedPath : parent
        }
        return proposedPath
    }

    static func uniqueFileName(_ original: String, occupied: inout Set<String>) -> String {
        if occupied.insert(original).inserted {
            return original
        }
        let ns = original as NSString
        let ext = ns.pathExtension
        let base = ext.isEmpty ? original : ns.deletingPathExtension
        var n = 1
        while true {
            let candidate: String
            if n == 1 {
                candidate = ext.isEmpty ? "\(base) copy" : "\(base) copy.\(ext)"
            } else {
                candidate = ext.isEmpty ? "\(base) copy \(n)" : "\(base) copy \(n).\(ext)"
            }
            if occupied.insert(candidate).inserted {
                return candidate
            }
            n += 1
        }
    }

    static func shouldSkip(source: URL, destinationDirectory: URL) -> Bool {
        let src = source.standardizedFileURL.path
        let dest = destinationDirectory.standardizedFileURL.path
        return dest == src || dest.hasPrefix(src + "/")
    }

    static func plannedCopies(
        sources: [URL],
        destinationDirectory: URL,
        occupiedNames: Set<String>
    ) -> [PlannedCopy] {
        var occupied = occupiedNames
        var copies: [PlannedCopy] = []
        for source in sources {
            if shouldSkip(source: source, destinationDirectory: destinationDirectory) {
                continue
            }
            let name = uniqueFileName(source.lastPathComponent, occupied: &occupied)
            copies.append(
                PlannedCopy(
                    source: source,
                    destination: destinationDirectory.appendingPathComponent(name)
                )
            )
        }
        return copies
    }

    static func performCopies(_ copies: [PlannedCopy], fileManager: FileManager) throws {
        for copy in copies {
            try fileManager.copyItem(at: copy.source, to: copy.destination)
        }
    }

    static func writeFileURLs(_ urls: [URL], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
    }

    static func pasteboardHasFiles(_ pasteboard: NSPasteboard) -> Bool {
        !PasteboardFileURLReader.fileURLs(from: pasteboard).isEmpty
    }

    static func items(from urls: [URL], fileManager: FileManager = .default) -> [Item] {
        urls.map { url in
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
            return Item(path: url.path, isDirectory: isDir.boolValue)
        }
    }

    @discardableResult
    static func paste(
        isLocal: Bool,
        rootPath: String,
        selections: [Item],
        anchor: Item?,
        pasteboard: NSPasteboard = .general,
        fileManager: FileManager = .default
    ) throws -> String? {
        let urls = PasteboardFileURLReader.fileURLs(from: pasteboard)
        guard canPaste(isLocal: isLocal, pasteboardHasFiles: !urls.isEmpty) else {
            return nil
        }
        let proposed = destinationDirectory(
            rootPath: rootPath,
            selections: selections,
            anchor: anchor
        )
        let destPath = resolvedPasteDestination(
            proposed: proposed,
            sources: items(from: urls, fileManager: fileManager)
        )
        let destURL = URL(fileURLWithPath: destPath, isDirectory: true)
        let occupied = Set((try? fileManager.contentsOfDirectory(atPath: destPath)) ?? [])
        let copies = plannedCopies(
            sources: urls,
            destinationDirectory: destURL,
            occupiedNames: occupied
        )
        guard !copies.isEmpty else { return nil }
        try performCopies(copies, fileManager: fileManager)
        return destPath
    }
}
