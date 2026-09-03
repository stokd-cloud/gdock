import CoreGraphics
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The overlay never scrolls: it shows the newest prompts that fit the panel it
/// was given and drops the rest (AX-GDOCK-PROMPT-HISTORY).
///
/// The fit is arithmetic on values rather than a measured SwiftUI layout so the
/// "which prompts survive" rule is provable without rendering.
@Suite struct GdockPromptHistoryLayoutTests {
    private typealias Layout = GdockPromptHistoryLayout

    private static let metrics = Layout.Metrics(
        rowHeight: 20,
        rowSpacing: 4,
        headerHeight: 22,
        verticalPadding: 8
    )

    private static func entries(_ count: Int) -> [GdockPromptHistoryEntry] {
        (0..<count).map { index in
            GdockPromptHistoryEntry(
                id: UUID(),
                workstreamId: "claude-focused",
                text: "prompt \(index)",
                submittedAt: Date(timeIntervalSince1970: 1_788_120_000 + TimeInterval(index))
            )
        }
    }

    // MARK: - Capacity

    @Test func capacityCountsRowsAndGapsInsideTheChrome() {
        // 22 header + 16 padding = 38 chrome; 4 rows = 20*4 + 4*3 gaps = 92.
        #expect(Layout.capacity(contentHeight: 130, metrics: Self.metrics) == 4)
        #expect(Layout.capacity(contentHeight: 153, metrics: Self.metrics) == 4)
        #expect(Layout.capacity(contentHeight: 154, metrics: Self.metrics) == 5)
    }

    @Test func capacityIsZeroWhenNotEvenOneRowFits() {
        #expect(Layout.capacity(contentHeight: 50, metrics: Self.metrics) == 0)
        #expect(Layout.capacity(contentHeight: 0, metrics: Self.metrics) == 0)
        #expect(Layout.capacity(contentHeight: -100, metrics: Self.metrics) == 0)
    }

    // MARK: - Selection

    @Test func keepsTheNewestEntriesInOldestFirstOrder() {
        let visible = Layout.visibleEntries(
            Self.entries(9),
            contentHeight: 130,
            metrics: Self.metrics
        )

        #expect(visible.map(\.text) == ["prompt 5", "prompt 6", "prompt 7", "prompt 8"])
    }

    @Test func showsEverythingWhenThePanelIsTallerThanTheHistory() {
        let all = Self.entries(3)
        #expect(Layout.visibleEntries(all, contentHeight: 400, metrics: Self.metrics) == all)
    }

    @Test func rendersNothingRatherThanOverflowingATinyPanel() {
        #expect(Layout.visibleEntries(Self.entries(5), contentHeight: 40, metrics: Self.metrics).isEmpty)
    }

    /// The guard the "no scrolling" rule actually needs: a newer prompt is never
    /// dropped while an older one survives.
    @Test func neverDropsANewerEntryInFavorOfAnOlderOne() {
        let all = Self.entries(12)
        for height in stride(from: 40.0, through: 400.0, by: 7.0) {
            let visible = Layout.visibleEntries(all, contentHeight: height, metrics: Self.metrics)
            guard let oldestVisible = visible.first else { continue }
            let dropped = all.prefix(while: { $0.id != oldestVisible.id })
            #expect(dropped.allSatisfy { $0.submittedAt < oldestVisible.submittedAt })
            #expect(visible == Array(all.suffix(visible.count)))
        }
    }
}
