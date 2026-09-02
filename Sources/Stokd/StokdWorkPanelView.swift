import CmuxFoundation
import Foundation
import SwiftUI

@MainActor
enum StokdWorkPresentation {
    private static let iso8601Formatter = ISO8601DateFormatter()
    private static let fractionalISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func statusText(_ rawValue: String, locale: Locale = .current) -> String {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pending":
            return String(localized: "stokdWork.status.pending", defaultValue: "Pending", locale: locale)
        case "in_progress":
            return String(localized: "stokdWork.status.inProgress", defaultValue: "In progress", locale: locale)
        case "completed":
            return String(localized: "stokdWork.status.completed", defaultValue: "Completed", locale: locale)
        case "failed":
            return String(localized: "stokdWork.status.failed", defaultValue: "Failed", locale: locale)
        case "blocked":
            return String(localized: "stokdWork.status.blocked", defaultValue: "Blocked", locale: locale)
        case "cancelled":
            return String(localized: "stokdWork.status.cancelled", defaultValue: "Cancelled", locale: locale)
        case "creating":
            return String(localized: "stokdWork.status.creating", defaultValue: "Creating", locale: locale)
        case "active":
            return String(localized: "stokdWork.status.active", defaultValue: "Active", locale: locale)
        case "executing":
            return String(localized: "stokdWork.status.executing", defaultValue: "Executing", locale: locale)
        default:
            return rawValue.replacingOccurrences(of: "_", with: " ")
        }
    }

    static func updatedAtText(_ rawValue: String, locale: Locale = .current) -> String {
        guard let date = fractionalISO8601Formatter.date(from: rawValue)
            ?? iso8601Formatter.date(from: rawValue)
        else { return rawValue }
        return date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)
        )
    }

    static func kindText(_ kind: StokdWorkItemKind, locale: Locale = .current) -> String {
        switch kind {
        case .task:
            return String(localized: "stokdWork.kind.task", defaultValue: "Task", locale: locale)
        case .project:
            return String(localized: "stokdWork.kind.project", defaultValue: "Project", locale: locale)
        case .todo:
            return String(localized: "stokdWork.kind.todo", defaultValue: "Todo", locale: locale)
        }
    }

    static func kindSymbol(_ kind: StokdWorkItemKind) -> String {
        switch kind {
        case .task: return "checkmark.circle"
        case .project: return "folder"
        case .todo: return "checklist"
        }
    }

    static func kindColor(_ kind: StokdWorkItemKind) -> Color {
        switch kind {
        case .task: return Color.accentColor
        case .project: return Color.secondary
        case .todo: return Color.purple
        }
    }

    static func statusColor(_ rawValue: String) -> Color {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "in_progress", "executing", "active":
            return Color.blue
        case "completed", "done":
            return Color.green
        case "blocked", "failed":
            return Color.red
        case "cancelled":
            return Color.gray
        default:
            return Color.secondary
        }
    }
}

struct StokdWorkPanelView: View {
    @ObservedObject var model: StokdWorkPanelViewModel
    @State private var actionInput: String = ""
    @State private var detailHeight: Double = StokdWorkPanelSettings.defaultDetailPaneHeight
    @State private var dragStartHeight: Double?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                filterBar
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let selectedRow = model.selectedRow {
                    detailSplitHandle(totalHeight: proxy.size.height)
                    detailHeader(for: selectedRow)
                    detailContent(for: selectedRow)
                        .frame(height: clampedDetailHeight(totalHeight: proxy.size.height))
                }
            }
        }
        .onAppear { detailHeight = model.detailPaneHeight }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cmuxFontMagnificationEnvironment()
        .accessibilityIdentifier("stokdWork.panel")
        .alert(
            model.pendingAction?.action.title ?? "",
            isPresented: Binding(
                get: { model.pendingAction != nil },
                set: { presented in if !presented { model.cancelPendingAction() } }
            ),
            presenting: model.pendingAction
        ) { pending in
            if pending.needsInput {
                TextField(pending.action.inputPrompt, text: $actionInput)
                Button(String(localized: "stokdWork.action.run", defaultValue: "Run")) {
                    let input = actionInput
                    actionInput = ""
                    model.confirmPendingAction(input: input)
                }
                Button(String(localized: "stokdWork.action.cancel", defaultValue: "Cancel"), role: .cancel) {
                    actionInput = ""
                    model.cancelPendingAction()
                }
            } else {
                Button(pending.action.title, role: pending.action.isDestructive ? ButtonRole.destructive : nil) {
                    model.confirmPendingAction(input: nil)
                }
                Button(String(localized: "stokdWork.action.cancel", defaultValue: "Cancel"), role: .cancel) {
                    model.cancelPendingAction()
                }
            }
        } message: { pending in
            if pending.needsInput {
                Text(pending.row.title)
            } else {
                Text(String(
                    localized: "stokdWork.action.confirm",
                    defaultValue: "\(pending.action.title) “\(pending.row.title)” (\(pending.row.hash))?"
                ))
            }
        }
        .alert(
            String(localized: "stokdWork.action.failed", defaultValue: "stokd command failed"),
            isPresented: Binding(
                get: { model.actionErrorMessage != nil },
                set: { presented in if !presented { model.dismissActionError() } }
            )
        ) {
            Button(String(localized: "stokdWork.action.ok", defaultValue: "OK"), role: .cancel) {
                model.dismissActionError()
            }
        } message: {
            Text(model.actionErrorMessage ?? "")
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .cmuxFont(size: 11)
                    TextField(
                        String(localized: "stokdWork.search.placeholder", defaultValue: "Search work"),
                        text: Binding(
                            get: { model.searchQuery },
                            set: { model.setSearchQuery($0) }
                        )
                    )
                    .textFieldStyle(.plain)
                    .cmuxFont(size: 11)
                    .focused($isSearchFocused)
                    .onExitCommand { model.clearSearch() }
                    .accessibilityIdentifier("stokdWork.search")
                    if model.isBodySearchRunning {
                        ProgressView()
                            .controlSize(.mini)
                            .help(String(localized: "stokdWork.search.bodies", defaultValue: "Searching item bodies"))
                    } else if !model.searchQuery.isEmpty {
                        Button(action: model.clearSearch) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "stokdWork.search.clear", defaultValue: "Clear search"))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                Button(action: model.refreshCurrentRepository) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "stokdWork.refresh", defaultValue: "Refresh work"))
                .accessibilityLabel(String(localized: "stokdWork.refresh", defaultValue: "Refresh work"))
                .accessibilityIdentifier("stokdWork.refresh")
                .disabled(model.repoSlug == nil || model.state == .loading || model.isRefreshing)
            }

            HStack(spacing: 6) {
                Picker(
                    String(localized: "stokdWork.filter.label", defaultValue: "Work type"),
                    selection: Binding(
                        get: { model.filter },
                        set: model.setFilter
                    )
                ) {
                    Text(String(localized: "stokdWork.filter.all", defaultValue: "All"))
                        .tag(StokdWorkPanelViewModel.Filter.all)
                    Text(String(localized: "stokdWork.filter.tasks", defaultValue: "Tasks"))
                        .tag(StokdWorkPanelViewModel.Filter.tasks)
                    Text(String(localized: "stokdWork.filter.projects", defaultValue: "Projects"))
                        .tag(StokdWorkPanelViewModel.Filter.projects)
                    Text(String(localized: "stokdWork.filter.todos", defaultValue: "Todos"))
                        .tag(StokdWorkPanelViewModel.Filter.todos)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("stokdWork.filter")

                Button(action: model.toggleShowCompleted) {
                    Image(systemName: model.showCompleted ? "eye" : "eye.slash")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(model.showCompleted ? Color.secondary : Color.accentColor)
                .help(model.showCompleted
                      ? String(localized: "stokdWork.filter.hideCompleted", defaultValue: "Hide completed")
                      : String(localized: "stokdWork.filter.showCompleted", defaultValue: "Show completed"))
                .accessibilityLabel(String(localized: "stokdWork.filter.completedToggle", defaultValue: "Toggle completed items"))
                .accessibilityValue(model.showCompleted
                                    ? String(localized: "stokdWork.filter.completed.shown", defaultValue: "Shown")
                                    : String(localized: "stokdWork.filter.completed.hidden", defaultValue: "Hidden"))
                .accessibilityIdentifier("stokdWork.filter.completed")

                Button(action: model.toggleSortDirection) {
                    Image(systemName: model.sortAscending ? "arrow.up" : "arrow.down")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .help(sortHelpText)
                .accessibilityLabel(String(localized: "stokdWork.sort.direction", defaultValue: "Sort direction"))
                .accessibilityValue(sortHelpText)
                .accessibilityIdentifier("stokdWork.sort")
                .contextMenu {
                    Picker(
                        String(localized: "stokdWork.sort.field", defaultValue: "Sort by"),
                        selection: Binding(
                            get: { model.sortField },
                            set: model.setSortField
                        )
                    ) {
                        Text(String(localized: "stokdWork.sort.updatedAt", defaultValue: "Last Updated"))
                            .tag(StokdWorkSortField.updatedAt)
                        Text(String(localized: "stokdWork.sort.createdAt", defaultValue: "Created"))
                            .tag(StokdWorkSortField.createdAt)
                    }
                    .pickerStyle(.inline)
                }
            }

            if let count = model.searchCountText {
                HStack {
                    Text(count)
                        .cmuxFont(size: 10)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("stokdWork.search.count")
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .rightSidebarChromeBottomBorder()
    }

    private var sortHelpText: String {
        switch (model.sortField, model.sortAscending) {
        case (.updatedAt, false):
            return String(localized: "stokdWork.sort.updatedNewest", defaultValue: "Last updated, newest first")
        case (.updatedAt, true):
            return String(localized: "stokdWork.sort.updatedOldest", defaultValue: "Last updated, oldest first")
        case (.createdAt, false):
            return String(localized: "stokdWork.sort.createdNewest", defaultValue: "Created, newest first")
        case (.createdAt, true):
            return String(localized: "stokdWork.sort.createdOldest", defaultValue: "Created, oldest first")
        }
    }

    // MARK: - Split handle

    private func clampedDetailHeight(totalHeight: Double) -> Double {
        let upper = max(StokdWorkPanelSettings.minimumDetailPaneHeight, totalHeight - 160)
        return min(max(detailHeight, StokdWorkPanelSettings.minimumDetailPaneHeight), upper)
    }

    private func detailSplitHandle(totalHeight: Double) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.18))
                .frame(height: 1)
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 36, height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 9)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragStartHeight == nil { dragStartHeight = detailHeight }
                    let start = dragStartHeight ?? detailHeight
                    detailHeight = start - value.translation.height
                }
                .onEnded { _ in
                    dragStartHeight = nil
                    detailHeight = clampedDetailHeight(totalHeight: totalHeight)
                    model.setDetailPaneHeight(detailHeight)
                }
        )
        .accessibilityLabel(String(localized: "stokdWork.detail.resize", defaultValue: "Resize details"))
        .accessibilityIdentifier("stokdWork.detail.splitHandle")
    }

    // MARK: - List

    private var content: AnyView {
        switch model.state {
        case .populated:
            if model.isShowingNoMatches {
                return AnyView(StokdWorkStateView(
                    title: model.noMatchesText,
                    symbol: "magnifyingglass",
                    showsProgress: model.isBodySearchRunning,
                    actionTitle: String(localized: "stokdWork.search.clear", defaultValue: "Clear search"),
                    action: { model.clearSearch() }
                )
                .accessibilityIdentifier("stokdWork.state.noMatches"))
            }
            return AnyView(ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.rows) { row in
                        StokdWorkRowView(
                            row: row,
                            isSelected: model.isRowSelected(row.id),
                            actions: model.actions(for: row),
                            onSelect: { model.select(rowID: row.id) },
                            onAction: { model.requestAction($0, on: row) }
                        )
                        .onAppear { model.rowDidAppear(id: row.id) }
                        Divider().padding(.leading, 36)
                    }
                    if model.isLoadingMore {
                        StokdWorkLoadingMoreFooter()
                    }
                }
            }
            .accessibilityIdentifier("stokdWork.list"))
        case .loading:
            return AnyView(StokdWorkStateView(
                title: model.stateMessage,
                symbol: "arrow.trianglehead.2.clockwise.rotate.90",
                showsProgress: true,
                actionTitle: nil,
                action: nil
            )
            .accessibilityIdentifier("stokdWork.state.loading"))
        case .idle:
            return AnyView(StokdWorkStateView(
                title: model.stateMessage,
                symbol: "checklist",
                showsProgress: false,
                actionTitle: nil,
                action: nil
            )
            .accessibilityIdentifier("stokdWork.state.idle"))
        case .empty:
            return AnyView(StokdWorkStateView(
                title: model.stateMessage,
                symbol: "tray",
                showsProgress: false,
                actionTitle: nil,
                action: nil
            )
            .accessibilityIdentifier("stokdWork.state.empty"))
        case let .failure(message):
            let canRetry = model.repoSlug != nil
            return AnyView(StokdWorkStateView(
                title: message,
                symbol: "exclamationmark.triangle",
                showsProgress: false,
                actionTitle: canRetry
                    ? String(localized: "stokdWork.retry", defaultValue: "Retry")
                    : nil,
                action: canRetry ? { model.refreshCurrentRepository() } : nil
            )
            .accessibilityIdentifier("stokdWork.state.error"))
        }
    }

    // MARK: - Detail

    private func detailHeader(for row: StokdWorkPanelViewModel.RowSnapshot) -> some View {
        HStack(spacing: 8) {
            Text(String(localized: "stokdWork.detail.title", defaultValue: "Details"))
                .cmuxFont(size: 10, weight: .semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Spacer()

            Text(StokdWorkPresentation.kindText(row.kind))
                .cmuxFont(size: 9, weight: .semibold)
                .foregroundStyle(.secondary)
            Text(row.hash)
                .cmuxFont(size: 10, design: .monospaced)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Menu {
                ForEach(model.actions(for: row), id: \.self) { action in
                    Button(role: action.isDestructive ? ButtonRole.destructive : nil) {
                        model.requestAction(action, on: row)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 16, height: 16)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20)
            .help(String(localized: "stokdWork.detail.actions", defaultValue: "Actions"))
            .accessibilityLabel(String(localized: "stokdWork.detail.actions", defaultValue: "Actions"))
            .accessibilityIdentifier("stokdWork.detail.actions")

            Button(action: model.closeDetail) {
                Image(systemName: "xmark")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "stokdWork.detail.close", defaultValue: "Close details"))
            .accessibilityLabel(String(localized: "stokdWork.detail.close", defaultValue: "Close details"))
            .accessibilityIdentifier("stokdWork.detail.close")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .rightSidebarChromeBottomBorder()
    }

    @ViewBuilder
    private func detailContent(for row: StokdWorkPanelViewModel.RowSnapshot) -> some View {
        if let state = model.detailState {
            if state.isLoading {
                StokdWorkStateView(
                    title: String(localized: "stokdWork.detail.loading", defaultValue: "Loading details"),
                    symbol: "doc.text",
                    showsProgress: true,
                    actionTitle: nil,
                    action: nil
                )
                .accessibilityIdentifier("stokdWork.detail.loading")
            } else if let detail = state.detail {
                StokdWorkDetailView(row: row, detail: detail, isPerformingAction: model.isPerformingAction)
            } else {
                StokdWorkStateView(
                    title: state.errorMessage ?? "",
                    symbol: "exclamationmark.triangle",
                    showsProgress: false,
                    actionTitle: String(localized: "stokdWork.retry", defaultValue: "Retry"),
                    action: { model.retryDetail() }
                )
                .accessibilityIdentifier("stokdWork.detail.error")
            }
        } else {
            EmptyView()
        }
    }
}

private struct StokdWorkRowView: View {
    let row: StokdWorkPanelViewModel.RowSnapshot
    let isSelected: Bool
    let actions: [StokdWorkAction]
    let onSelect: () -> Void
    let onAction: (StokdWorkAction) -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: StokdWorkPresentation.kindSymbol(row.kind))
                    .cmuxFont(size: 13, weight: .medium)
                    .foregroundStyle(StokdWorkPresentation.kindColor(row.kind))
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(row.title)
                            .cmuxFont(size: 12, weight: .medium)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(StokdWorkPresentation.statusText(row.status))
                            .cmuxFont(size: 9, weight: .semibold)
                            .foregroundStyle(StokdWorkPresentation.statusColor(row.status))
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                StokdWorkPresentation.statusColor(row.status).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 4)
                            )
                    }

                    if !row.detail.isEmpty {
                        Text(row.detail)
                            .cmuxFont(size: 11)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 5) {
                        Text(StokdWorkPresentation.kindText(row.kind))
                        Text(row.hash)
                        if let completed = row.checklistCompleted, let total = row.checklistTotal {
                            Text(String(
                                localized: "stokdWork.todo.checklist",
                                defaultValue: "\(completed)/\(total) done"
                            ))
                        }
                        Text(StokdWorkPresentation.updatedAtText(row.updatedAt))
                        if row.matchedInBody {
                            Text(String(localized: "stokdWork.search.matchedInBody", defaultValue: "matched in body"))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .cmuxFont(size: 9, design: .monospaced)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            ForEach(actions, id: \.self) { action in
                Button(role: action.isDestructive ? ButtonRole.destructive : nil) {
                    onAction(action)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("stokdWork.row.\(row.id)")
    }
}

private struct StokdWorkLoadingMoreFooter: View {
    var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text(String(localized: "stokdWork.list.loadingMore", defaultValue: "Loading more…"))
                .cmuxFont(size: 10)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("stokdWork.list.loadingMore")
    }
}

private struct StokdWorkDetailView: View {
    let row: StokdWorkPanelViewModel.RowSnapshot
    let detail: StokdWorkDetail
    let isPerformingAction: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                identityHeader

                if !detail.isParsed {
                    rawBlock(detail.rawText)
                } else {
                    if !detail.fields.isEmpty {
                        fieldsBlock
                    }
                    if !detail.checklist.isEmpty {
                        section(String(localized: "stokdWork.detail.checklist", defaultValue: "Checklist")) {
                            ForEach(detail.checklist) { item in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(item.isCompleted ? Color.green : Color.secondary)
                                        .cmuxFont(size: 11)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.title)
                                            .cmuxFont(size: 11)
                                            .strikethrough(item.isCompleted)
                                        if let repo = item.repoSlug {
                                            Text(repo)
                                                .cmuxFont(size: 9, design: .monospaced)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if let description = detail.description, !description.isEmpty {
                        section(String(localized: "stokdWork.detail.description", defaultValue: "Description")) {
                            Text(description)
                                .cmuxFont(size: 11)
                                .textSelection(.enabled)
                        }
                    }
                    if !detail.acceptanceCriteria.isEmpty {
                        section(String(localized: "stokdWork.detail.acceptanceCriteria", defaultValue: "Acceptance Criteria")) {
                            ForEach(Array(detail.acceptanceCriteria.enumerated()), id: \.offset) { _, criterion in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "checkmark.square")
                                        .foregroundStyle(.secondary)
                                        .cmuxFont(size: 11)
                                    Text(criterion)
                                        .cmuxFont(size: 11)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    ForEach(Array(detail.sections.enumerated()), id: \.offset) { _, extra in
                        section(extra.title) {
                            Text(extra.body)
                                .cmuxFont(size: 11, design: .monospaced)
                                .textSelection(.enabled)
                        }
                    }
                    if !detail.notes.isEmpty {
                        section(String(localized: "stokdWork.detail.notes", defaultValue: "Notes")) {
                            ForEach(Array(detail.notes.enumerated()), id: \.offset) { _, note in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                        .cmuxFont(size: 11)
                                        .foregroundStyle(.secondary)
                                    Text(note)
                                        .cmuxFont(size: 11)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }

                if isPerformingAction {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(String(localized: "stokdWork.action.running", defaultValue: "Running stokd…"))
                            .cmuxFont(size: 10)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("stokdWork.detail")
    }

    private var identityHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: StokdWorkPresentation.kindSymbol(row.kind))
                    .cmuxFont(size: 14, weight: .medium)
                    .foregroundStyle(StokdWorkPresentation.kindColor(row.kind))
                Text(detail.title ?? row.title)
                    .cmuxFont(size: 13, weight: .semibold)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 6) {
                let status = detail.status ?? row.status
                Text(StokdWorkPresentation.statusText(status))
                    .cmuxFont(size: 9, weight: .semibold)
                    .foregroundStyle(StokdWorkPresentation.statusColor(status))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(StokdWorkPresentation.statusColor(status).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                if let number = detail.number ?? row.number {
                    Text("#\(number)")
                        .cmuxFont(size: 9, design: .monospaced)
                        .foregroundStyle(.secondary)
                }
                if let repo = detail.repoSlug ?? row.repoSlug {
                    Text(repo)
                        .cmuxFont(size: 9, design: .monospaced)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Text(String(
                localized: "stokdWork.detail.updated",
                defaultValue: "Updated \(StokdWorkPresentation.updatedAtText(row.updatedAt))"
            ))
            .cmuxFont(size: 9, design: .monospaced)
            .foregroundStyle(.tertiary)
        }
    }

    private var fieldsBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(detail.fields.keys.sorted(), id: \.self) { key in
                if key.lowercased() != "status" {
                    HStack(alignment: .top, spacing: 6) {
                        Text(key)
                            .cmuxFont(size: 10, weight: .medium)
                            .foregroundStyle(.secondary)
                            .frame(width: 84, alignment: .trailing)
                        Text(detail.fields[key] ?? "")
                            .cmuxFont(size: 10, design: .monospaced)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .cmuxFont(size: 9, weight: .semibold)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func rawBlock(_ text: String) -> some View {
        Text(text.isEmpty
             ? String(localized: "stokdWork.detail.emptyOutput", defaultValue: "stokd returned no output for this item")
             : text)
            .cmuxFont(size: 10, design: .monospaced)
            .textSelection(.enabled)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityIdentifier("stokdWork.detail.raw")
    }
}

private struct StokdWorkStateView: View {
    let title: String
    let symbol: String
    let showsProgress: Bool
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: symbol)
                    .cmuxFont(size: 24)
                    .foregroundStyle(.secondary)
            }

            Text(title)
                .cmuxFont(size: 12, weight: .medium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
