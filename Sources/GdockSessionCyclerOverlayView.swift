import SwiftUI

/// Mutable state behind the cycler overlay.
///
/// Lives above the row views: rows receive ``GdockSessionCyclerRow`` values and
/// never see this object, which is what keeps the overlay clear of the
/// list-boundary rule in `CLAUDE.md`.
@MainActor
@Observable
final class GdockSessionCyclerViewModel {
    var sessions: [GdockCyclableSession] = []
    var scope: GdockSessionCycleScope = .currentRepo
    var query: String = ""
    var selectedPanelId: UUID?
    var currentRepoSlug: String?
    var isGroupedRepoModeEnabled: Bool = false

    var listing: GdockSessionCyclerListing {
        GdockSessionCyclerModel.listing(
            sessions: sessions,
            scope: scope,
            currentRepoSlug: currentRepoSlug,
            isGroupedRepoModeEnabled: isGroupedRepoModeEnabled,
            query: query,
            selectedPanelId: selectedPanelId
        )
    }

    /// Moves the highlight, wrapping at both ends.
    func moveSelection(by offset: Int) {
        selectedPanelId = GdockSessionCyclerModel.selection(
            movedBy: offset,
            from: selectedPanelId,
            in: listing
        )
    }

    /// Steps the scope ring and keeps the current session highlighted when it
    /// survives the new scope.
    func moveScope(by offset: Int) {
        scope = GdockCycleRing.step(from: scope, by: offset)
        selectedPanelId = listing.highlightedSession?.panelId
    }
}

/// The cycler itself: a filter field, a scope ring, and one row per session.
///
/// Deliberately shaped like the command palette — same dark rounded card, same
/// "type to filter, arrows to move, Enter to go" grammar — because it is the
/// same muscle memory.
struct GdockSessionCyclerOverlayView: View {
    @Bindable var model: GdockSessionCyclerViewModel
    let onActivate: (GdockCyclableSession) -> Void
    let onDismiss: () -> Void

    @FocusState private var isFilterFocused: Bool

    var body: some View {
        let listing = model.listing

        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.35)

            if listing.isEmpty {
                emptyState
            } else {
                rows(for: listing)
            }

            Divider().opacity(0.35)
            footer
        }
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12))
        )
        .shadow(radius: 24, y: 8)
        .onAppear { isFilterFocused = true }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up")
                .foregroundStyle(.secondary)
            TextField(
                String(
                    localized: "gdock.sessionCycler.filter.placeholder",
                    defaultValue: "Filter sessions"
                ),
                text: $model.query
            )
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .focused($isFilterFocused)
            .onSubmit {
                if let session = model.listing.highlightedSession { onActivate(session) }
            }

            scopeIndicator
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// The scope ring, drawn as its members so the operator can see there are
    /// more than two the day a third arrives.
    private var scopeIndicator: some View {
        HStack(spacing: 4) {
            ForEach(GdockSessionCycleScope.allCases, id: \.self) { scope in
                Text(Self.scopeLabel(scope))
                    .font(.system(size: 10, weight: scope == model.scope ? .semibold : .regular))
                    .foregroundStyle(scope == model.scope ? Color.primary : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(scope == model.scope ? Color.accentColor.opacity(0.22) : Color.clear)
                    )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.scopeLabel(model.scope))
    }

    // MARK: - Rows

    private func rows(for listing: GdockSessionCyclerListing) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(listing.rows) { row in
                        GdockSessionCyclerRowView(row: row)
                            .id(row.id)
                            .contentShape(Rectangle())
                            .onTapGesture { onActivate(row.session) }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 320)
            .onChange(of: listing.selectedIndex) { _, _ in
                guard let session = listing.highlightedSession else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(session.panelId, anchor: .center)
                }
            }
        }
    }

    private var emptyState: some View {
        Text(
            model.sessions.isEmpty
                ? String(
                    localized: "gdock.sessionCycler.empty.noSessions",
                    defaultValue: "No agent sessions are running"
                )
                : String(
                    localized: "gdock.sessionCycler.empty.noMatches",
                    defaultValue: "No sessions match this filter"
                )
        )
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            hint(
                "←→",
                String(localized: "gdock.sessionCycler.hint.scope", defaultValue: "Scope")
            )
            hint(
                "↑↓",
                String(localized: "gdock.sessionCycler.hint.select", defaultValue: "Select")
            )
            hint(
                "↩",
                String(localized: "gdock.sessionCycler.hint.open", defaultValue: "Open")
            )
            Spacer(minLength: 0)
            Button(String(localized: "gdock.sessionCycler.hint.close", defaultValue: "Close")) {
                onDismiss()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(keys)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    static func scopeLabel(_ scope: GdockSessionCycleScope) -> String {
        switch scope {
        case .currentRepo:
            return String(localized: "gdock.sessionCycler.scope.currentRepo", defaultValue: "This Repo")
        case .allSessions:
            return String(localized: "gdock.sessionCycler.scope.allSessions", defaultValue: "All Sessions")
        }
    }
}

/// One row: the full session summary when highlighted, logo + title otherwise.
struct GdockSessionCyclerRowView: View, Equatable {
    let row: GdockSessionCyclerRow

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.row == rhs.row }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            providerMark
            if row.isHighlighted {
                highlighted
            } else {
                compact
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, row.isHighlighted ? 8 : 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(row.isHighlighted ? Color.accentColor.opacity(0.14) : Color.clear)
                .padding(.horizontal, 8)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var providerMark: some View {
        Group {
            if let assetName = row.agentAssetName {
                Image(assetName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "terminal")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: row.isHighlighted ? 18 : 14, height: row.isHighlighted ? 18 : 14)
        .padding(.top, 1)
    }

    /// Unhighlighted: the provider mark and the title, nothing else. A wall of
    /// summaries would defeat a cycler (AX-GDOCK-SESSION-CYCLER).
    private var compact: some View {
        Text(row.title)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var highlighted: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(row.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                if let age {
                    Text(age)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            if let summary = row.summary {
                HStack(spacing: 4) {
                    Text(GdockWorkspacePanelCardView.kindLabel(for: summary.latestKindRaw))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(GdockWorkspacePanelCardView.kindColor(for: summary.latestKind))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(GdockWorkspacePanelCardView.kindColor(for: summary.latestKind).opacity(0.16))
                        )
                    Text(summary.headline)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    if let disposition = summary.disposition {
                        Text(disposition)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Text(Self.entryCountLabel(summary.entryCount))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var subtitle: String? {
        let branch = row.session.branch?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let branch, !branch.isEmpty { return branch }
        let repo = row.session.repoSlug
        return repo ?? row.session.workspaceName
    }

    private var age: String? {
        guard let updatedAt = row.summary?.updatedAt else { return nil }
        let seconds = max(0, Date().timeIntervalSince(updatedAt))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86_400))d"
    }

    private var accessibilityLabel: String {
        var parts = [row.session.agentDisplayName, row.title, row.session.workspaceName]
        if let headline = row.summary?.headline { parts.append(headline) }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    static func entryCountLabel(_ count: Int) -> String {
        String(
            localized: "gdock.sessionCycler.entryCount",
            defaultValue: "\(count) outcomes"
        )
    }
}
