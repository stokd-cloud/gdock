import SwiftUI

/// One agent-session card inside the focused workspace's stack.
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
            glyph
                .frame(width: 16 * fontScale, height: 16 * fontScale)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    kindBadge
                    Text(headline)
                        .font(.system(size: 11 * fontScale, weight: .semibold))
                        .foregroundStyle(primaryTextStyle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    if let trailingId {
                        Text(trailingId)
                            .font(.system(size: 9 * fontScale, design: .monospaced))
                            .foregroundStyle(secondaryTextStyle)
                            .lineLimit(1)
                    }
                }

                if let metadata {
                    Text(metadata)
                        .font(.system(size: 9 * fontScale))
                        .foregroundStyle(secondaryTextStyle)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(cardStroke, lineWidth: card.isSelected ? 1 : 0.5)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Pieces

    @ViewBuilder
    private var glyph: some View {
        if let assetName = GdockAgentSessionGlyph.assetName(forAgentKindRaw: card.agentKindRaw),
           let image = NSImage(named: assetName) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: GdockAgentSessionGlyph.fallbackSymbolName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(secondaryTextStyle)
        }
    }

    /// The mockup's blue chip. Carries the latest outcome kind, or the pane's
    /// agent when the session has not recorded an outcome yet — the chip is
    /// never blank.
    @ViewBuilder
    private var kindBadge: some View {
        Text(badgeText)
            .font(.system(size: 8 * fontScale, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(badgeColor)
            )
            .fixedSize()
    }

    private var badgeText: String {
        if let kind = card.sessionSummary?.latestKindRaw, !kind.isEmpty {
            return Self.kindLabel(for: kind)
        }
        return card.agentKindRaw.uppercased()
    }

    private var badgeColor: Color {
        guard let summary = card.sessionSummary else { return accentColor }
        return Self.kindColor(for: summary.latestKind)
    }

    /// Unknown kinds keep their raw text: the CLI may add a kind before gdock
    /// learns about it, and a blank chip is worse than an unstyled one.
    ///
    /// Shared with the session cycler overlay, which badges the same outcome
    /// kinds — one mapping, so the two surfaces cannot drift apart.
    static func kindLabel(for rawKind: String) -> String {
        rawKind.uppercased()
    }

    static func kindColor(for kind: StokdSessionOutcomeRecord.Kind?) -> Color {
        switch kind {
        case .blocked: return .red
        case .needsYou: return .orange
        case .shipped: return .green
        case .fixed: return .blue
        case .decided: return .purple
        case nil: return .secondary
        }
    }

    /// The headline is the session's derived one-liner. With no outcome recorded
    /// yet the pane's own title stands in, so a fresh agent still reads as
    /// something rather than an empty row.
    private var headline: String {
        if let headline = card.sessionSummary?.headline, !headline.isEmpty {
            return headline
        }
        let title = card.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        return String(
            localized: "gdock.panelCard.noOutcomesYet",
            defaultValue: "No outcomes recorded yet"
        )
    }

    /// The mockup's `#a83b30aa` slot: the work item's hash when the pane has
    /// one, otherwise the session's short id.
    private var trailingId: String? {
        if let hash = card.workItem?.hashShort, !hash.isEmpty { return "#\(hash)" }
        guard let sessionID = card.sessionSummary?.sessionID, !sessionID.isEmpty else { return nil }
        return "#\(String(sessionID.suffix(8)))"
    }

    private var metadata: String? {
        if let summary = card.sessionSummary {
            let line = GdockAgentSessionCardMetadata.line(summary: summary)
            if !line.isEmpty { return line }
        }
        // No summary: fall back to the pane's location, which is still useful.
        if let branch = card.branch, !branch.isEmpty { return branch }
        return card.directory.isEmpty ? nil : card.directory
    }

    // MARK: - Styling

    /// Selected reads as a filled light card against muted siblings, matching
    /// the mockup's one white card above three grey ones.
    private var cardFill: Color {
        card.isSelected
            ? Color.primary.opacity(0.14)
            : Color.primary.opacity(0.05)
    }

    private var cardStroke: Color {
        card.isSelected
            ? accentColor.opacity(0.7)
            : Color.primary.opacity(0.08)
    }

    private var primaryTextStyle: Color {
        card.isSelected ? Color.primary : Color.primary.opacity(0.75)
    }

    private var secondaryTextStyle: Color {
        Color.secondary.opacity(card.isSelected ? 1.0 : 0.75)
    }

    private var accentColor: Color {
        guard let accentHex, let nsColor = NSColor(hex: accentHex) else {
            return Color.accentColor
        }
        return Color(nsColor: nsColor)
    }

    private var accessibilityLabel: String {
        var parts = [badgeText, headline]
        if let workItem = card.workItem {
            parts.append("\(workItem.kind.rawValue) \(workItem.title)")
        }
        if let summary = card.sessionSummary {
            parts.append(String(
                localized: "gdock.panelCard.summary.entries.a11y",
                defaultValue: "\(summary.entryCount) outcome entries"
            ))
            if summary.isRunning {
                parts.append(String(
                    localized: "gdock.panelCard.summary.running.a11y",
                    defaultValue: "session running"
                ))
            }
            if let disposition = summary.disposition {
                parts.append(String(
                    localized: "gdock.panelCard.summary.disposition.a11y",
                    defaultValue: "disposition \(disposition)"
                ))
            }
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

/// The focused workspace's agent-session cards, as one selection-ringed stack.
///
/// This view *is* the workspace's sidebar row (the row itself is not drawn), so
/// the ring belongs to the container and the cards sit inside it — the shape the
/// mockup specifies.
struct GdockWorkspacePanelCardStackView: View, Equatable {
    let cards: [GdockWorkspacePanelCard]
    let fontScale: CGFloat
    let accentHex: String?
    /// Whether the workspace owning this stack is the selected one. It always
    /// is today, but the ring is driven by data rather than by that assumption.
    let isWorkspaceSelected: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.cards == rhs.cards
            && lhs.fontScale == rhs.fontScale
            && lhs.accentHex == rhs.accentHex
            && lhs.isWorkspaceSelected == rhs.isWorkspaceSelected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(cards) { card in
                GdockWorkspacePanelCardView(
                    card: card,
                    fontScale: fontScale,
                    accentHex: accentHex
                )
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    isWorkspaceSelected ? ringColor : Color.primary.opacity(0.10),
                    lineWidth: isWorkspaceSelected ? 1.5 : 0.5
                )
        )
        .contentShape(Rectangle())
    }

    private var ringColor: Color {
        guard let accentHex, let nsColor = NSColor(hex: accentHex) else {
            return Color.accentColor
        }
        return Color(nsColor: nsColor)
    }
}
