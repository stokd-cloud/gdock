import Foundation

/// Opens a terminal surface born with a `stokd` verb so long-running actions
/// (start, resume, integrate, …) run where the operator can watch and answer
/// them, never as a hidden subprocess behind the panel.
///
/// Both Work hosts (the rail tool panel and the legacy right sidebar) install
/// this same launcher so interactive actions behave identically.
@MainActor
enum StokdWorkTerminalLauncher {
    static func launch(command: String, directory: String, in workspace: Workspace?) {
        guard let workspace,
              let paneId = workspace.bonsplitController.focusedPaneId else { return }
        _ = workspace.clearSplitZoom()
        _ = workspace.newTerminalSurface(
            inPane: paneId,
            focus: true,
            workingDirectory: directory.isEmpty ? nil : directory,
            initialCommand: command,
            inheritWorkingDirectoryFallback: directory.isEmpty
        )
    }
}
