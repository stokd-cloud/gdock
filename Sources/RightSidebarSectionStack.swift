import SwiftUI

/// Vertical stack of right-sidebar tool sections with collapsible headers and
/// draggable separators.
///
/// Content is supplied by the caller per mode, so each tool keeps the exact view
/// it renders in the single-tool sidebar — sections re-parent those views rather
/// than re-hosting them.
struct RightSidebarSectionStack<Content: View>: View {
    @Binding var layout: RightSidebarSectionLayout
    /// Returns a section to the mode bar.
    let onReturnToModeBar: (RightSidebarMode) -> Void
    var showsReturnToModeBar: Bool = true
    @ViewBuilder let content: (RightSidebarMode) -> Content

    /// Live separator drag, so the layout is committed once per gesture step
    /// rather than accumulating rounding error.
    @State private var dragOriginHeights: [CGFloat]?

    var body: some View {
        GeometryReader { proxy in
            let totalHeight = proxy.size.height
            let heights = layout.resolvedHeights(totalHeight: totalHeight)

            VStack(spacing: 0) {
                ForEach(Array(layout.sections.enumerated()), id: \.element.id) { index, section in
                    if index > 0 {
                        separator(above: index, totalHeight: totalHeight)
                    }
                    sectionView(
                        section: section,
                        index: index,
                        height: heights.indices.contains(index) ? heights[index] : RightSidebarSectionLayout.headerHeight,
                        totalHeight: totalHeight
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - Section

    private func sectionView(
        section: RightSidebarSectionLayout.Section,
        index: Int,
        height: CGFloat,
        totalHeight: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            header(for: section, index: index, totalHeight: totalHeight)
            if !section.isCollapsed {
                content(section.mode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
        .frame(height: height, alignment: .top)
    }

    private func header(
        for section: RightSidebarSectionLayout.Section,
        index: Int,
        totalHeight: CGFloat
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: section.isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .frame(width: 12)
            Image(systemName: section.mode.symbolName)
                .font(.system(size: 10))
            Text(section.mode.label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            if showsReturnToModeBar {
                Button {
                    onReturnToModeBar(section.mode)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .opacity(0.6)
                .accessibilityLabel(
                    String.localizedStringWithFormat(
                        String(
                            localized: "rightSidebar.section.returnToModeBar",
                            defaultValue: "Return %@ to the tool bar"
                        ),
                        section.mode.label
                    )
                )
            }
        }
        .padding(.horizontal, 8)
        .frame(height: RightSidebarSectionLayout.headerHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            layout.toggleCollapse(section.mode)
        }
        .gesture(
            DragGesture(minimumDistance: 6)
                .onEnded { value in
                    let originY = layout.resolvedHeights(totalHeight: totalHeight)
                        .prefix(index)
                        .reduce(0, +)
                    let dropY = originY + value.location.y
                    let destination = layout.insertionIndex(forDropAt: dropY, totalHeight: totalHeight)
                    layout.moveBlock(startingAt: index, to: destination)
                }
        )
        .accessibilityIdentifier("RightSidebar.section.\(section.mode.rawValue)")
    }

    // MARK: - Separator

    private func separator(above index: Int, totalHeight: CGFloat) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle().inset(by: -3))
            .onHover { inside in
                if inside {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let origin = dragOriginHeights ?? layout.resolvedHeights(totalHeight: totalHeight)
                        if dragOriginHeights == nil { dragOriginHeights = origin }
                        layout.resize(
                            dividerAbove: index,
                            by: value.translation.height - previousTranslation,
                            totalHeight: totalHeight
                        )
                        previousTranslationStore.value = value.translation.height
                    }
                    .onEnded { _ in
                        dragOriginHeights = nil
                        previousTranslationStore.value = 0
                    }
            )
            .accessibilityIdentifier("RightSidebar.sectionDivider.\(index)")
    }

    /// Incremental drag needs the previous translation; a reference box keeps it
    /// out of `body`'s state graph so reading it never invalidates the view.
    private final class TranslationBox {
        var value: CGFloat = 0
    }
    @State private var previousTranslationStore = TranslationBox()
    private var previousTranslation: CGFloat { previousTranslationStore.value }
}
