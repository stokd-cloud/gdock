import CoreGraphics
import Foundation

/// Fit math for the prompt-history overlay, which never scrolls.
///
/// The panel shows the newest prompts that fit and drops the rest, so the rule
/// deciding which prompts survive lives here as arithmetic over values rather
/// than inside a measured SwiftUI layout (AX-GDOCK-PROMPT-HISTORY).
enum GdockPromptHistoryLayout {
    struct Metrics: Equatable, Sendable {
        let rowHeight: CGFloat
        let rowSpacing: CGFloat
        /// Title row above the prompts.
        let headerHeight: CGFloat
        /// Inset applied at the top and again at the bottom.
        let verticalPadding: CGFloat

        /// Matches the overlay's own type sizes and padding.
        static let standard = Metrics(
            rowHeight: 20,
            rowSpacing: 4,
            headerHeight: 26,
            verticalPadding: 12
        )
    }

    /// How many rows fit in `contentHeight`, inter-row gaps included.
    static func capacity(contentHeight: CGFloat, metrics: Metrics) -> Int {
        let available = contentHeight - metrics.headerHeight - metrics.verticalPadding * 2
        let perRow = metrics.rowHeight + metrics.rowSpacing
        guard perRow > 0, available >= metrics.rowHeight else { return 0 }
        // The last row carries no trailing gap, so lend one back before dividing.
        return max(0, Int(((available + metrics.rowSpacing) / perRow).rounded(.down)))
    }

    /// The newest entries that fit, still oldest-first so the newest renders at
    /// the bottom. A shorter panel drops older prompts, never newer ones.
    static func visibleEntries(
        _ entries: [GdockPromptHistoryEntry],
        contentHeight: CGFloat,
        metrics: Metrics
    ) -> [GdockPromptHistoryEntry] {
        Array(entries.suffix(capacity(contentHeight: contentHeight, metrics: metrics)))
    }
}
