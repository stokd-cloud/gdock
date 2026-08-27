import SwiftUI

/// One pane card under the focused workspace row.
///
/// `Equatable` and built purely from ``GdockWorkspacePanelCard`` — it holds no
/// store reference and reads no observable state, which is what keeps it legal
/// below the sidebar's lazy-list boundary (CLAUDE.md; issue 2586).
struct GdockWorkspacePanelCardView: View, Equatable {
    let card: GdockWorkspacePanelCard
    let fontScale: CGFloat
    let accentHex: String?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.card == rhs.card
            && lhs.fontScale == rhs.fontScale
            && lhs.accentHex == rhs.accentHex
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Selection reads as a filled rail rather than a whole-card tint:
            // four tinted cards at once would fight the workspace rows around
            // them for attention.
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(card.isSelected ? accentColor : Color.secondary.opacity(0.25))
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(card.title)
                        .font(.system(size: 10 * fontScale, weight: card.isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    if let sessionState = card.sessionState {
                        Text(sessionState)
                            .font(.system(size: 8 * fontScale, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9 * fontScale))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                if let workItem = card.workItem {
                    HStack(spacing: 3) {
                        Text(workItem.kind.rawValue.uppercased())
                            .font(.system(size: 7 * fontScale, weight: .bold))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(accentColor.opacity(0.18))
                            )
                        Text(workItem.title)
                            .font(.system(size: 9 * fontScale))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let hash = workItem.hashShort {
                            Text(hash)
                                .font(.system(size: 8 * fontScale, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .padding(.trailing, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Branch wins over directory when both are known: inside a repo the branch
    /// is what distinguishes one pane from its siblings, since they usually
    /// share a directory.
    private var subtitle: String? {
        if let branch = card.branch, !branch.isEmpty { return branch }
        return card.directory.isEmpty ? nil : card.directory
    }

    private var accentColor: Color {
        guard let accentHex, let nsColor = NSColor(hex: accentHex) else {
            return Color.accentColor
        }
        return Color(nsColor: nsColor)
    }

    private var accessibilityLabel: String {
        var parts = [card.title]
        if let subtitle { parts.append(subtitle) }
        if let workItem = card.workItem {
            parts.append("\(workItem.kind.rawValue) \(workItem.title)")
        }
        if card.isSelected {
            parts.append(String(
                localized: "gdock.panelCard.selected.a11y",
                defaultValue: "selected pane"
            ))
        }
        return parts.joined(separator: ", ")
    }
}
