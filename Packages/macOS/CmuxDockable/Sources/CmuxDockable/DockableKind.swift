import Foundation

/// Kind of content that can be docked into a canvas pane or panel host.
///
/// Raw values match app-level panel type strings exactly. Only
/// ``filePreview`` uses a lowercased explicit raw value (`"filepreview"`);
/// every other case uses the implicit case-name raw value.
///
/// Decoding is lenient: mixed-case strings such as `"FilePreview"` map to the
/// matching case by case-insensitive raw-value comparison.
public enum DockableKind: String, Codable, Sendable, CaseIterable {
    case terminal
    case browser
    case markdown
    case filePreview = "filepreview"
    case rightSidebarTool
    case customSidebar
    case agentSession
    case project
    case extensionBrowser
    case workspaceTodo
    case cloudVMLoading

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if let kind = Self(rawValue: rawValue) {
            self = kind
            return
        }
        let lowered = rawValue.lowercased()
        if let kind = Self.allCases.first(where: { $0.rawValue.lowercased() == lowered }) {
            self = kind
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unknown dockable kind: \(rawValue)"
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
