import SwiftUI

struct StokdWorkPanelView: View {
    @ObservedObject var model: StokdWorkPanelViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("stokdWork.panel")
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
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
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("stokdWork.filter")

            Button(action: model.refreshCurrentRepository) {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "stokdWork.refresh", defaultValue: "Refresh work"))
            .accessibilityLabel(String(localized: "stokdWork.refresh", defaultValue: "Refresh work"))
            .accessibilityIdentifier("stokdWork.refresh")
            .disabled(model.repoSlug == nil || model.state == .loading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var content: AnyView {
        switch model.state {
        case .populated:
            return AnyView(ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.rows) { row in
                        StokdWorkRowView(row: row)
                        Divider().padding(.leading, 36)
                    }
                }
            }
            .accessibilityIdentifier("stokdWork.list"))
        case .loading:
            return AnyView(StokdWorkStateView(
                title: model.state.message,
                symbol: "arrow.trianglehead.2.clockwise.rotate.90",
                showsProgress: true,
                actionTitle: nil,
                action: nil
            )
            .accessibilityIdentifier("stokdWork.state.loading"))
        case .idle:
            return AnyView(StokdWorkStateView(
                title: model.state.message,
                symbol: "checklist",
                showsProgress: false,
                actionTitle: nil,
                action: nil
            )
            .accessibilityIdentifier("stokdWork.state.idle"))
        case .empty:
            return AnyView(StokdWorkStateView(
                title: model.state.message,
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
}

private struct StokdWorkRowView: View {
    let row: StokdWorkPanelViewModel.RowSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: row.kind == .task ? "checkmark.circle" : "folder")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(row.kind == .task ? Color.accentColor : Color.secondary)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(row.status.replacingOccurrences(of: "_", with: " "))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                }

                if !row.detail.isEmpty {
                    Text(row.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 5) {
                    Text(row.kind == .task
                         ? String(localized: "stokdWork.kind.task", defaultValue: "Task")
                         : String(localized: "stokdWork.kind.project", defaultValue: "Project"))
                    Text(row.updatedAt)
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("stokdWork.row.\(row.id)")
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
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Text(title)
                .font(.system(size: 12, weight: .medium))
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
