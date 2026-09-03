import CoreGraphics
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Geometry for the stacked right-sidebar tool sections.
@Suite struct RightSidebarSectionLayoutTests {
    private typealias Layout = RightSidebarSectionLayout

    private func layout(_ modes: [RightSidebarMode]) -> Layout {
        Layout(sections: modes.map { Layout.Section(mode: $0) })
    }

    // MARK: - Stacking

    @Test func startsEmptySoTheSidebarRendersUnchanged() {
        #expect(Layout().isEmpty)
        #expect(Layout().resolvedHeights(totalHeight: 500).isEmpty)
    }

    @Test func insertingStacksInDropOrder() {
        var subject = Layout()
        subject.insert(.files, at: 0)
        subject.insert(.sessions, at: 1)
        subject.insert(.find, at: 1)
        #expect(subject.modes == [.files, .find, .sessions])
    }

    @Test func insertingAnAlreadyStackedToolMovesItRatherThanDuplicating() {
        var subject = layout([.files, .find, .sessions])
        subject.insert(.files, at: 3)
        #expect(subject.modes == [.find, .sessions, .files])
        #expect(subject.sections.count == 3)
    }

    @Test func removingReturnsToolToTheModeBar() {
        var subject = layout([.files, .find])
        let removed = subject.remove(.files)
        #expect(removed)
        #expect(subject.modes == [.find])
        let removedAgain = subject.remove(.files)
        #expect(!removedAgain)
    }

    // MARK: - Heights

    @Test func expandedSectionsShareSpaceAndFillTheStack() {
        let subject = layout([.files, .find])
        let heights = subject.resolvedHeights(totalHeight: 400)
        #expect(heights.count == 2)
        #expect(abs(heights.reduce(0, +) - 400) < 0.001)
        #expect(abs(heights[0] - heights[1]) < 0.001)
    }

    @Test func collapsedSectionOccupiesExactlyItsHeader() {
        var subject = layout([.files, .find])
        subject.setCollapsed(true, for: .files)
        let heights = subject.resolvedHeights(totalHeight: 400)
        #expect(heights[0] == Layout.headerHeight)
        #expect(abs(heights.reduce(0, +) - 400) < 0.001)
    }

    @Test func allCollapsedLeavesOnlyHeaders() {
        var subject = layout([.files, .find, .sessions])
        for mode in subject.modes { subject.setCollapsed(true, for: mode) }
        let heights = subject.resolvedHeights(totalHeight: 400)
        #expect(heights.allSatisfy { $0 == Layout.headerHeight })
    }

    @Test func crampedStackStillFitsWithoutOverflowing() {
        // Far too little room to honour every minimum.
        let subject = layout([.files, .find, .sessions])
        let heights = subject.resolvedHeights(totalHeight: 120)
        #expect(abs(heights.reduce(0, +) - 120) < 0.001)
        #expect(heights.allSatisfy { $0 >= Layout.headerHeight })
    }

    @Test func togglingCollapseIsReversible() {
        var subject = layout([.files])
        subject.toggleCollapse(.files)
        #expect(subject.sections[0].isCollapsed)
        subject.toggleCollapse(.files)
        #expect(!subject.sections[0].isCollapsed)
    }

    // MARK: - Separator drag

    @Test func draggingSeparatorMovesSpaceBetweenNeighbours() {
        var subject = layout([.files, .find])
        let before = subject.resolvedHeights(totalHeight: 400)
        subject.resize(dividerAbove: 1, by: 50, totalHeight: 400)
        let after = subject.resolvedHeights(totalHeight: 400)

        #expect(after[0] > before[0])
        #expect(after[1] < before[1])
        #expect(abs(after.reduce(0, +) - 400) < 0.001)
    }

    @Test func separatorDragCannotStarveANeighbour() {
        var subject = layout([.files, .find])
        subject.resize(dividerAbove: 1, by: 10_000, totalHeight: 400)
        let heights = subject.resolvedHeights(totalHeight: 400)
        let smallestContent = heights.map { $0 - Layout.headerHeight }.min() ?? 0
        #expect(smallestContent >= Layout.minContentHeight - 0.001)
        #expect(abs(heights.reduce(0, +) - 400) < 0.001)
    }

    @Test func separatorDragIsANoOpAgainstACollapsedNeighbour() {
        var subject = layout([.files, .find])
        subject.setCollapsed(true, for: .find)
        let before = subject.resolvedHeights(totalHeight: 400)
        subject.resize(dividerAbove: 1, by: 50, totalHeight: 400)
        #expect(subject.resolvedHeights(totalHeight: 400) == before)
    }

    @Test func draggingTopOfCollapsedRunMovesTheRunWithTheNextExpandedSection() {
        var subject = layout([.files, .find, .sessions])
        subject.setCollapsed(true, for: .find)
        let before = subject.resolvedHeights(totalHeight: 500)

        subject.resize(dividerAbove: 1, by: 40, totalHeight: 500)
        let after = subject.resolvedHeights(totalHeight: 500)

        #expect(after[0] > before[0])
        #expect(after[1] == Layout.headerHeight)
        #expect(after[2] < before[2])
    }

    @Test func dividerInsideCollapsedRunCannotSplitTheBlock() {
        var subject = layout([.files, .find, .sessions])
        subject.setCollapsed(true, for: .find)
        let before = subject.sections

        subject.resize(dividerAbove: 2, by: 40, totalHeight: 500)

        #expect(subject.sections == before)
    }

    @Test func stackedPresentationReconcilesEveryStackableToolAndPreservesState() {
        var subject = layout([.files, .find])
        subject.setCollapsed(true, for: .files)
        subject.resize(dividerAbove: 1, by: 30, totalHeight: 400)
        let filesBefore = subject.sections[0]

        subject.reconcileStackableModes(RightSidebarMode.stackableModes)

        #expect(subject.modes == [.files, .find, .sessions, .stokdWork])
        #expect(subject.sections[0] == filesBefore)
    }

    @Test func resizingOutOfRangeIndexIsIgnored() {
        var subject = layout([.files, .find])
        let before = subject.sections
        subject.resize(dividerAbove: 0, by: 50, totalHeight: 400)
        subject.resize(dividerAbove: 9, by: 50, totalHeight: 400)
        #expect(subject.sections == before)
    }

    @Test func weightsSurviveAResizeOfTheSidebarItself() {
        var subject = layout([.files, .find])
        subject.resize(dividerAbove: 1, by: 60, totalHeight: 400)
        let tall = subject.resolvedHeights(totalHeight: 800)
        // The dragged proportion still holds at a different sidebar height.
        #expect(tall[0] > tall[1])
        #expect(abs(tall.reduce(0, +) - 800) < 0.001)
    }

    // MARK: - Drop placement

    @Test func dropNearTheTopInsertsFirst() {
        let subject = layout([.files, .find])
        #expect(subject.insertionIndex(forDropAt: 2, totalHeight: 400) == 0)
    }

    @Test func dropNearTheBottomAppends() {
        let subject = layout([.files, .find])
        #expect(subject.insertionIndex(forDropAt: 399, totalHeight: 400) == 2)
    }

    @Test func dropOnAnEmptyStackInsertsFirst() {
        #expect(Layout().insertionIndex(forDropAt: 120, totalHeight: 400) == 0)
    }
}
