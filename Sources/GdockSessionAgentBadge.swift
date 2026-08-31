import Foundation

/// Which provider mark a cycler row shows, derived from the agent status keys a
/// workspace already tracks per panel.
///
/// The status keys (`claude_code`, `codex`, `hermes-agent`, …) are the app's
/// existing agent runtime vocabulary; `SessionAgent` is the app's existing
/// provider presentation. This is the one place they are joined, so a row's logo
/// cannot disagree with the vault's idea of the same agent.
enum GdockSessionAgentBadge: Equatable {
    /// Asset-catalog name of the provider mark, nil for an agent with no art.
    case badge(assetName: String?, displayName: String)

    var assetName: String? {
        switch self {
        case .badge(let assetName, _): return assetName
        }
    }

    var displayName: String {
        switch self {
        case .badge(_, let displayName): return displayName
        }
    }

    /// The `SessionAgent` a runtime status key denotes.
    ///
    /// Only `claude_code` needs a translation: every other key already matches a
    /// `SessionAgent` raw value or a registered vault agent id.
    static func agent(forStatusKey key: String) -> SessionAgent? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == "claude_code" { return .claude }
        return SessionAgent(rawValue: trimmed)
    }

    /// The badge for a panel's status keys.
    ///
    /// Sorted before resolving so a panel that reports two agents always shows
    /// the same one rather than whichever the set happened to yield first.
    /// An unrecognized key still produces a badge — a running agent gdock cannot
    /// name is still a session worth cycling to — with no art and the key as its
    /// name.
    static func badge(forStatusKeys keys: [String]) -> GdockSessionAgentBadge? {
        let normalized = keys
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
        guard let first = normalized.first else { return nil }

        for key in normalized {
            guard let agent = agent(forStatusKey: key) else { continue }
            return .badge(assetName: agent.assetName, displayName: agent.displayName)
        }
        return .badge(assetName: nil, displayName: first)
    }
}
