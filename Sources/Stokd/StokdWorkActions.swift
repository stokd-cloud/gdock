import Foundation

/// Every context action the Work panel offers. One shared table maps
/// (kind, status) to an ordered entry list and each entry to a `stokd` argument
/// vector, so the row context menu and the detail action bar never diverge.
enum StokdWorkAction: String, CaseIterable, Equatable, Sendable {
    case start
    case startInWorktree
    case resume
    case integrate
    case review
    case advance
    case report
    case addNote
    case setPriority
    case markCompleted
    case delete
    case copyHash
    case openInTerminal

    var title: String {
        switch self {
        case .start:
            return String(localized: "stokdWork.action.start", defaultValue: "Start")
        case .startInWorktree:
            return String(localized: "stokdWork.action.startInWorktree", defaultValue: "Start in Worktree")
        case .resume:
            return String(localized: "stokdWork.action.resume", defaultValue: "Resume")
        case .integrate:
            return String(localized: "stokdWork.action.integrate", defaultValue: "Integrate")
        case .review:
            return String(localized: "stokdWork.action.review", defaultValue: "Review")
        case .advance:
            return String(localized: "stokdWork.action.advance", defaultValue: "Advance")
        case .report:
            return String(localized: "stokdWork.action.report", defaultValue: "Report")
        case .addNote:
            return String(localized: "stokdWork.action.addNote", defaultValue: "Add Note…")
        case .setPriority:
            return String(localized: "stokdWork.action.setPriority", defaultValue: "Set Priority…")
        case .markCompleted:
            return String(localized: "stokdWork.action.markCompleted", defaultValue: "Mark Completed")
        case .delete:
            return String(localized: "stokdWork.action.delete", defaultValue: "Delete")
        case .copyHash:
            return String(localized: "stokdWork.action.copyHash", defaultValue: "Copy Hash")
        case .openInTerminal:
            return String(localized: "stokdWork.action.openInTerminal", defaultValue: "Open in Terminal")
        }
    }

    var systemImage: String {
        switch self {
        case .start: return "play"
        case .startInWorktree: return "arrow.triangle.branch"
        case .resume: return "playpause"
        case .integrate: return "arrow.triangle.merge"
        case .review: return "eye"
        case .advance: return "forward"
        case .report: return "doc.text"
        case .addNote: return "note.text.badge.plus"
        case .setPriority: return "list.number"
        case .markCompleted: return "checkmark.circle"
        case .delete: return "trash"
        case .copyHash: return "number"
        case .openInTerminal: return "terminal"
        }
    }

    /// Verbs that remove or finish the item ask for confirmation first.
    var needsConfirmation: Bool {
        self == .delete || self == .markCompleted
    }

    /// Verbs that take free text prompt for it first.
    var needsInput: Bool {
        self == .addNote || self == .setPriority
    }

    /// Long-running or interactive verbs open a terminal running the verb rather
    /// than blocking the panel on a hidden subprocess.
    var runsInTerminal: Bool {
        switch self {
        case .start, .startInWorktree, .resume, .integrate, .review, .advance, .report, .openInTerminal:
            return true
        case .addNote, .setPriority, .markCompleted, .delete, .copyHash:
            return false
        }
    }

    var isDestructive: Bool { self == .delete }

    var inputPrompt: String {
        switch self {
        case .addNote:
            return String(localized: "stokdWork.action.addNote.prompt", defaultValue: "Note text")
        case .setPriority:
            return String(localized: "stokdWork.action.setPriority.prompt", defaultValue: "Priority slot (1 is highest) or none")
        default:
            return ""
        }
    }
}

enum StokdWorkActionTable {
    /// Ordered entries for an item of `kind` in `status`. `Mark Completed` is
    /// absent once the item is already terminal, so it never fails at dispatch.
    static func actions(kind: StokdWorkItemKind, status: String) -> [StokdWorkAction] {
        let terminal = StokdWorkStatus.isTerminal(status)
        var entries: [StokdWorkAction]
        switch kind {
        case .task:
            entries = [.start, .startInWorktree, .resume, .integrate, .review, .addNote, .setPriority, .markCompleted, .delete]
        case .project:
            entries = [.start, .advance, .report, .integrate, .addNote, .setPriority, .markCompleted, .delete]
        case .todo:
            entries = [.start, .addNote, .markCompleted, .delete]
        }
        if terminal {
            entries.removeAll { $0 == .markCompleted }
        }
        entries.append(contentsOf: [.copyHash, .openInTerminal])
        return entries
    }

    /// The `stokd` argument vector for `action`, or `nil` when the action does
    /// not shell out (Copy Hash) or its required input is invalid.
    static func arguments(for action: StokdWorkAction, kind: StokdWorkItemKind, hash: String, input: String?) -> [String]? {
        let noun = kind.rawValue
        let text = input?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch action {
        case .start:
            return [noun, "start", hash]
        case .startInWorktree:
            return [noun, "start", "--worktree", hash]
        case .resume:
            return [noun, "resume", hash]
        case .integrate:
            return [noun, "integrate", hash]
        case .review:
            return [noun, "review", hash]
        case .advance:
            return [noun, "advance", hash]
        case .report:
            return [noun, "report", hash]
        case .addNote:
            guard !text.isEmpty else { return nil }
            return [noun, "note", hash, text]
        case .setPriority:
            guard text.lowercased() == "none" || Int(text) != nil else { return nil }
            return [noun, "priority", hash, text.lowercased() == "none" ? "none" : String(Int(text)!)]
        case .markCompleted:
            return [noun, "complete", hash]
        case .delete:
            return [noun, "delete", hash]
        case .openInTerminal:
            return [noun, "view", hash]
        case .copyHash:
            return nil
        }
    }

    /// The shell command a terminal surface runs for an interactive action.
    static func terminalCommand(for action: StokdWorkAction, kind: StokdWorkItemKind, hash: String) -> String? {
        guard action.runsInTerminal,
              let arguments = arguments(for: action, kind: kind, hash: hash, input: nil) else { return nil }
        return (["stokd"] + arguments).joined(separator: " ")
    }
}
