import Foundation

/// A titled block of CLI output that the parser did not map to a named field.
struct StokdWorkDetailSection: Equatable, Sendable {
    let title: String
    let body: String
}

/// Everything the detail view renders for one work item.
///
/// `rawText` is always present so the view can fall back to the CLI's own
/// output when `isParsed` is false; an unparseable item never renders empty.
struct StokdWorkDetail: Equatable, Sendable {
    let kind: StokdWorkItemKind
    var title: String?
    var number: Int?
    var hash: String?
    var repoSlug: String?
    var status: String?
    var fields: [String: String] = [:]
    var description: String?
    var acceptanceCriteria: [String] = []
    var notes: [String] = []
    var sections: [StokdWorkDetailSection] = []
    var checklist: [StokdTodoItem] = []
    let rawText: String
    let isParsed: Bool

    static func unparsed(kind: StokdWorkItemKind, rawText: String) -> StokdWorkDetail {
        StokdWorkDetail(kind: kind, rawText: rawText, isParsed: false)
    }
}

/// Parses `stokd task get` / `stokd project get` text and `stokd todo view --json`.
///
/// The text format is section-delimited: a `Task #hash  Title` header line over
/// a rule, `Key: value` lines, then blocks whose title line sits directly above
/// (or between) rule lines. It is not a stable contract, so every branch
/// degrades to the raw text rather than dropping content.
enum StokdWorkDetailParser {
    static func parse(kind: StokdWorkItemKind, output: String) -> StokdWorkDetail {
        switch kind {
        case .task, .project:
            return parseText(kind: kind, output: output)
        case .todo:
            return parseTodoJSON(output: output)
        }
    }

    // MARK: - Text (task / project)

    private static let headerPattern = try! NSRegularExpression(
        pattern: #"^\s*(Task|Project)\s+#(\S+)\s{1,}(.*?)\s*$"#
    )
    private static let fieldPattern = try! NSRegularExpression(
        pattern: #"^([A-Za-z][A-Za-z /_-]{0,30}):\s+(.*?)\s*$"#
    )

    private static func parseText(kind: StokdWorkItemKind, output: String) -> StokdWorkDetail {
        let lines = output.components(separatedBy: .newlines)
        guard let headerIndex = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
              let header = firstMatch(headerPattern, in: lines[headerIndex]),
              header.count >= 4
        else {
            return .unparsed(kind: kind, rawText: output)
        }

        var detail = StokdWorkDetail(kind: kind, rawText: output, isParsed: true)
        detail.hash = header[2]
        detail.title = header[3].isEmpty ? nil : header[3]
        if let number = Int(header[2]) { detail.number = number }

        // Split the remainder into titled sections. A non-rule line that sits
        // directly above a rule line starts a new section.
        var sections: [(title: String, lines: [String])] = [(title: "", lines: [])]
        var index = headerIndex + 1
        while index < lines.count {
            let line = lines[index]
            if isRule(line) {
                index += 1
                continue
            }
            if index + 1 < lines.count, isRule(lines[index + 1]),
               !line.trimmingCharacters(in: .whitespaces).isEmpty {
                sections.append((title: line.trimmingCharacters(in: .whitespaces), lines: []))
                index += 2
                continue
            }
            sections[sections.count - 1].lines.append(line)
            index += 1
        }

        for (title, body) in sections {
            let text = trimmedBlock(body)
            switch title.lowercased() {
            case "":
                for line in body {
                    guard let match = firstMatch(fieldPattern, in: line), match.count >= 3 else { continue }
                    let key = match[1].trimmingCharacters(in: .whitespaces)
                    let value = match[2]
                    detail.fields[key] = value
                    switch key.lowercased() {
                    case "status":
                        detail.status = value
                    case "workspace", "repo", "repository":
                        detail.repoSlug = value
                    default:
                        break
                    }
                }
            case "description", "prd":
                if !text.isEmpty {
                    detail.description = detail.description.map { $0 + "\n\n" + text } ?? text
                }
            case "acceptance criteria":
                detail.acceptanceCriteria = bullets(in: body)
            case "notes":
                detail.notes = bullets(in: body)
            default:
                if !text.isEmpty {
                    detail.sections.append(StokdWorkDetailSection(title: title, body: text))
                }
            }
        }
        return detail
    }

    private static func isRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 4 else { return false }
        return trimmed.allSatisfy { "─═-=━".contains($0) }
    }

    private static func firstMatch(_ regex: NSRegularExpression, in line: String) -> [String]? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let groupRange = Range(match.range(at: index), in: line) else { return "" }
            return String(line[groupRange])
        }
    }

    private static func trimmedBlock(_ lines: [String]) -> String {
        var slice = lines[...]
        while let first = slice.first, first.trimmingCharacters(in: .whitespaces).isEmpty { slice = slice.dropFirst() }
        while let last = slice.last, last.trimmingCharacters(in: .whitespaces).isEmpty { slice = slice.dropLast() }
        return slice.joined(separator: "\n")
    }

    /// Bullet lines (`- `, `• `, `* `) with continuation lines folded into the
    /// preceding bullet; a block without bullets yields its non-empty lines.
    private static func bullets(in lines: [String]) -> [String] {
        var result: [String] = []
        var sawBullet = false
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let marker = ["- ", "• ", "* ", "· "].first(where: { line.hasPrefix($0) }) {
                sawBullet = true
                result.append(String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces))
            } else if sawBullet, !result.isEmpty {
                result[result.count - 1] += " " + line
            } else {
                result.append(line)
            }
        }
        return result
    }

    // MARK: - JSON (todo)

    private struct TodoDetailJSON: Decodable {
        let hash: String?
        let todoID: String?
        let title: String?
        let status: String?
        let repoSlug: String?
        let ordered: Bool?
        let priority: Int?
        let items: [StokdTodoItem]?

        enum CodingKeys: String, CodingKey {
            case hash, title, status, ordered, priority, items
            case todoID = "todo_id"
            case repoSlug = "repo_slug"
        }
    }

    private static func parseTodoJSON(output: String) -> StokdWorkDetail {
        guard let json = try? JSONDecoder().decode(TodoDetailJSON.self, from: Data(output.utf8)) else {
            return .unparsed(kind: .todo, rawText: output)
        }
        var detail = StokdWorkDetail(kind: .todo, rawText: output, isParsed: true)
        detail.hash = json.hash
        detail.title = json.title
        detail.status = json.status
        detail.repoSlug = json.repoSlug
        detail.checklist = (json.items ?? []).sorted { $0.order < $1.order }
        if let ordered = json.ordered { detail.fields["Ordered"] = ordered ? "true" : "false" }
        if let priority = json.priority { detail.fields["Priority"] = String(priority) }
        if let id = json.todoID { detail.fields["ID"] = id }
        return detail
    }
}
