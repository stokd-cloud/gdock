import AppKit

final class FileExplorerSearchResultsTableView: NSTableView {
    var fileExplorerPanelPlacement: FileExplorerPanelPlacement = .rightSidebar
    var onCancel: (() -> Void)?
    var onMoveSelection: ((Int) -> Void)?
    var onCommit: (() -> Void)?
    var onFocus: (() -> Void)?
    var onModeShortcut: ((RightSidebarMode, NSWindow?) -> Bool)?
    var onCopyFiles: (() -> Void)?
    var onPasteFiles: (() -> Void)?
    var onTrashFiles: (() -> Void)?
    var canCopyFiles: (() -> Bool)?
    var canPasteFiles: (() -> Bool)?
    var canTrashFiles: (() -> Bool)?

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            onFocus?()
            redrawVisibleRows()
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            redrawVisibleRows()
        }
        return result
    }

    override func keyDown(with event: NSEvent) {
        if let mode = AppDelegate.shared?.rightSidebarModeShortcut(for: event) {
            if onModeShortcut?(mode, window) == true {
                return
            }
        }
        if handleOpenSelectionShortcut(event) { return }
        if event.keyCode == 36 || event.keyCode == 76 {
            onCommit?()
            return
        }
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        if let delta = RightSidebarKeyboardNavigation.moveDelta(for: event) {
            onMoveSelection?(delta)
            return
        }
        if FileExplorerFileTrash.isCommandDelete(event) {
            onTrashFiles?()
            return
        }
        if RightSidebarKeyboardNavigation.isPlainPrintableText(event) {
            return
        }
        super.keyDown(with: event)
    }

    @objc func copy(_ sender: Any?) {
        onCopyFiles?()
    }

    @objc func paste(_ sender: Any?) {
        onPasteFiles?()
    }

    @objc func delete(_ sender: Any?) {
        onTrashFiles?()
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)) {
            return canCopyFiles?() ?? false
        }
        if item.action == #selector(paste(_:)) {
            return canPasteFiles?() ?? false
        }
        if item.action == #selector(delete(_:)) {
            return canTrashFiles?() ?? false
        }
        return super.validateUserInterfaceItem(item)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleOpenSelectionShortcut(event) { return true }
        if let delta = RightSidebarKeyboardNavigation.moveDelta(for: event) {
            onMoveSelection?(delta)
            return true
        }
        if FileExplorerFileTrash.isCommandDelete(event) {
            onTrashFiles?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func redrawVisibleRows() {
        setNeedsDisplay(bounds)
        let visibleRows = rows(in: visibleRect)
        guard visibleRows.location != NSNotFound else { return }
        let upperBound = min(visibleRows.location + visibleRows.length, numberOfRows)
        guard visibleRows.location < upperBound else { return }
        for row in visibleRows.location..<upperBound {
            rowView(atRow: row, makeIfNecessary: false)?.needsDisplay = true
        }
    }
}
