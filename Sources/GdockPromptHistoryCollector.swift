import CMUXAgentLaunch
import Foundation

/// Reduces Feed workstream telemetry into the prompts submitted to one agent
/// session (AX-GDOCK-PROMPT-HISTORY).
///
/// The Feed store is the only place cmux already keeps every `UserPromptSubmit`
/// with a timestamp, and it persists them to JSONL, so the overlay survives a
/// relaunch instead of starting empty on every dogfood build.
///
/// Everything here is a pure function over values: the overlay renders below the
/// panel's list boundary, where holding a store reference is what reintroduces
/// the spin loop (`CLAUDE.md`; cmux issue 2586).
enum GdockPromptHistoryCollector {
    /// Longest prompt text a row keeps. Rows truncate visually anyway; the cap
    /// keeps a pasted-file-sized prompt from being measured and laid out.
    private static let maxPromptCharacters = 400

    /// Prompts submitted to `focus`, oldest first — the overlay stacks upward
    /// from the newest, so the newest entry has to be last.
    ///
    /// - Parameter resolveTarget: Maps a `<agent>-<sessionId>` workstream onto
    ///   the pane it runs in. Injected so the attribution rules stay testable
    ///   without the on-disk hook-session stores.
    static func entries(
        items: [WorkstreamItem],
        focus: GdockPromptHistoryFocus,
        resolveTarget: (String) -> GdockPromptHistoryTarget?
    ) -> [GdockPromptHistoryEntry] {
        let focusedDirectory = normalizedDirectory(focus.directory)
        // One lookup per workstream, not per prompt: the real resolver reads a
        // JSON file per call and a busy session contributes many rows.
        var resolved: [String: GdockPromptHistoryTarget?] = [:]

        func target(for workstreamId: String) -> GdockPromptHistoryTarget? {
            if let cached = resolved[workstreamId] { return cached }
            let value = resolveTarget(workstreamId)
            resolved[workstreamId] = value
            return value
        }

        func belongsToFocus(_ item: WorkstreamItem) -> Bool {
            if let target = target(for: item.workstreamId) {
                // A session that resolves to another pane is never rescued by a
                // matching directory: two panes in one checkout is the normal
                // case, and merging them misattributes prompts.
                return target.workspaceId == focus.workspaceId
                    && target.surfaceId == focus.panelId
            }
            // Agents that never registered a hook session still belong to the
            // pane when they ran in its directory; without this the overlay is
            // empty for every agent outside the hook path.
            guard let focusedDirectory else { return false }
            return normalizedDirectory(item.cwd) == focusedDirectory
        }

        let collected: [GdockPromptHistoryEntry] = items.compactMap { item in
            guard case .userPrompt(let rawText) = item.payload,
                  let text = collapsedText(rawText),
                  belongsToFocus(item) else { return nil }
            return GdockPromptHistoryEntry(
                id: item.id,
                workstreamId: item.workstreamId,
                text: text,
                submittedAt: item.createdAt
            )
        }

        return collected.sorted { lhs, rhs in
            if lhs.submittedAt != rhs.submittedAt { return lhs.submittedAt < rhs.submittedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// One display line. Prompts arrive with the composer's newlines and
    /// indentation intact, and a row is a single line.
    private static func collapsedText(_ value: String) -> String? {
        let collapsed = value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > maxPromptCharacters else { return collapsed }
        return "\(collapsed.prefix(maxPromptCharacters))…"
    }

    /// Compares directories as path text with trailing separators dropped, so
    /// `/repo/gdock` and `/repo/gdock/` are the same pane. Deliberately not
    /// `URL.standardized`, whose root handling differs across macOS majors
    /// (`CLAUDE.md`; cmux issue 4529).
    private static func normalizedDirectory(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        var path = trimmed
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}
