import Foundation
import CmuxDockable

// MARK: - Stateful panel payload codecs (Session* fidelity)

extension MarkdownPanel {
    func encodeDockPayload() throws -> Data {
        try JSONEncoder().encode(SessionMarkdownPanelSnapshot(filePath: filePath))
    }
}

extension FilePreviewPanel {
    func encodeDockPayload() throws -> Data {
        try JSONEncoder().encode(SessionFilePreviewPanelSnapshot(filePath: filePath))
    }
}

extension RightSidebarToolPanel {
    func encodeDockPayload() throws -> Data {
        try JSONEncoder().encode(SessionRightSidebarToolPanelSnapshot(mode: mode))
    }
}

extension CustomSidebarPanel {
    func encodeDockPayload() throws -> Data {
        try JSONEncoder().encode(SessionCustomSidebarPanelSnapshot(name: name))
    }
}

extension AgentSessionPanel {
    func encodeDockPayload() throws -> Data {
        try JSONEncoder().encode(
            SessionAgentSessionPanelSnapshot(
                rendererKind: rendererKind,
                providerID: currentProviderID,
                workingDirectory: workingDirectory
            )
        )
    }
}

extension ProjectPanel {
    public func encodeDockPayload() throws -> Data {
        try JSONEncoder().encode(
            SessionProjectPanelSnapshot(
                projectPath: projectURL.path,
                selectedNodePath: selectedFilePath,
                activeTab: activeTab.rawValue,
                selectedSchemeName: selectedSchemeName,
                selectedConfigurationName: selectedConfigurationName
            )
        )
    }
}

extension WorkspaceTodoPanel {
    func encodeDockPayload() throws -> Data {
        try JSONEncoder().encode(SessionWorkspaceTodoPanelSnapshot())
    }
}

// Content-less kinds use Dockable's default empty Data encode.
