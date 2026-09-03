import SwiftUI

/// The prompt-history overlay: what you have asked this session, newest last.
///
/// Reading order is the terminal's, not a list's — the newest prompt sits at the
/// bottom where the newest terminal output is, and older prompts stack upward
/// until the panel runs out of room. Nothing scrolls; anything that does not fit
/// is reported as a count instead.
struct GdockPromptHistoryOverlayView: View {
    let model: GdockPromptHistoryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.35)
            content
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12))
        )
        .shadow(radius: 24, y: 8)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .foregroundStyle(.secondary)
            Text(String(
                localized: "gdock.promptHistory.title",
                defaultValue: "Your prompts"
            ))
            .font(.system(size: 13, weight: .semibold))

            if !model.sessionTitle.isEmpty {
                Text(model.sessionTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if model.hiddenCount > 0 {
                Text(Self.hiddenLabel(count: model.hiddenCount))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Rows

    @ViewBuilder
    private var content: some View {
        if model.rows.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 4) {
                // Bottom-anchored: a half-full panel keeps the newest prompt on
                // the bottom edge instead of floating the list to the top.
                Spacer(minLength: 0)
                ForEach(model.rows) { row in
                    GdockPromptHistoryRowView(row: row)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }

    private var emptyState: some View {
        Text(
            model.hasLoaded
                ? String(
                    localized: "gdock.promptHistory.empty",
                    defaultValue: "No prompts recorded for this session yet"
                )
                : String(
                    localized: "gdock.promptHistory.loading",
                    defaultValue: "Reading prompt history…"
                )
        )
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private static func hiddenLabel(count: Int) -> String {
        String(
            format: String(
                localized: "gdock.promptHistory.hiddenCount",
                defaultValue: "%lld older hidden"
            ),
            count
        )
    }
}

/// One prompt line. A value-only view, per the list-boundary rule in `CLAUDE.md`.
private struct GdockPromptHistoryRowView: View, Equatable {
    let row: GdockPromptHistoryRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(row.text)
                .font(.system(size: 12, weight: row.isNewest ? .medium : .regular))
                .foregroundStyle(row.isNewest ? Color.primary : Color.primary.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Text(row.relativeTime)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(height: 20)
    }

    static func == (lhs: GdockPromptHistoryRowView, rhs: GdockPromptHistoryRowView) -> Bool {
        lhs.row == rhs.row
    }
}
