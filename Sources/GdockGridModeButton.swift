import SwiftUI

/// Titlebar button for gdock Grid Mode: shows the enforced shape and opens
/// the grid-size picker popover. Mounted in the workspace titlebar's trailing
/// region and rendered only while `gdock.gridMode` is enabled.
///
/// Native SwiftUI `.popover` is safe here (no first-responder text field),
/// matching `ShortcutDiscoveryButton`.
struct GdockGridModeTitlebarButton: View {
    @AppStorage(GdockGridModeSettings.userDefaultsKey)
    private var gridModeEnabled = GdockGridModeSettings.defaultEnabled
    @AppStorage(GdockGridModeSettings.shapeUserDefaultsKey)
    private var shapeRaw = GdockGridModeSettings.shapeCatalogKey.defaultValue

    @State private var isPopoverPresented = false

    private var shape: GdockGridShape {
        GdockGridShape(encoded: shapeRaw) ?? .quad
    }

    private let helpText = String(
        localized: "gdock.gridMode.button.help",
        defaultValue: "Grid Mode shape"
    )

    var body: some View {
        if gridModeEnabled {
            Button {
                isPopoverPresented.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 11, weight: .medium))
                    Text(shape.displayText)
                        .cmuxFont(size: 11, weight: .semibold)
                }
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                GdockGridShapeSelectorView(initialShape: shape) { selected in
                    isPopoverPresented = false
                    GdockGridModeSettings.setShape(selected)
                }
            }
            .titlebarInteractiveControl()
            .safeHelp(helpText)
            .accessibilityLabel(helpText)
            .accessibilityIdentifier("GdockGridModeTitlebarButton")
        }
    }
}

/// The growing grid-size picker.
///
/// The tray starts at 2×2 (or one past the current shape) and grows a row and
/// a column ahead of the hovered cell, up to `GdockGridShape.maxRows/maxCols`.
/// The tray size is sticky: overshooting past the edge never shrinks it, only
/// hovering a smaller cell does. Clicking a cell commits that cell's
/// `row × column` as the enforced shape.
struct GdockGridShapeSelectorView: View {
    let initialShape: GdockGridShape
    let onSelect: (GdockGridShape) -> Void

    @State private var displayRows: Int
    @State private var displayCols: Int
    @State private var hoveredRow: Int?
    @State private var hoveredCol: Int?

    private static let baseTray = 2
    private let cellSize: CGFloat = 18
    private let cellSpacing: CGFloat = 3

    init(initialShape: GdockGridShape, onSelect: @escaping (GdockGridShape) -> Void) {
        self.initialShape = initialShape
        self.onSelect = onSelect
        _displayRows = State(initialValue: Self.trayLength(for: initialShape.rows, max: GdockGridShape.maxRows))
        _displayCols = State(initialValue: Self.trayLength(for: initialShape.cols, max: GdockGridShape.maxCols))
    }

    private static func trayLength(for committed: Int, max maxValue: Int) -> Int {
        min(maxValue, Swift.max(baseTray, committed + 1))
    }

    private var headerText: String {
        if let hoveredRow, let hoveredCol {
            return GdockGridShape(rows: hoveredRow, cols: hoveredCol).displayText
        }
        return String(
            localized: "gdock.gridMode.selector.title",
            defaultValue: "Grid shape"
        )
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(headerText)
                .cmuxFont(size: 11, weight: .semibold)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            VStack(spacing: cellSpacing) {
                ForEach(1...displayRows, id: \.self) { row in
                    HStack(spacing: cellSpacing) {
                        ForEach(1...displayCols, id: \.self) { col in
                            cell(row: row, col: col)
                        }
                    }
                }
            }
            .onHover { inside in
                if !inside {
                    // Sticky tray: clear the highlight, keep the size.
                    hoveredRow = nil
                    hoveredCol = nil
                }
            }
        }
        .padding(12)
        .accessibilityIdentifier("GdockGridShapeSelector")
    }

    private func cell(row: Int, col: Int) -> some View {
        let isHovered = hoveredRow.map { row <= $0 } == true && hoveredCol.map { col <= $0 } == true
        let isCommitted = hoveredRow == nil && row <= initialShape.rows && col <= initialShape.cols
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(
                isHovered
                    ? Color.accentColor
                    : isCommitted
                        ? Color.accentColor.opacity(0.35)
                        : Color(nsColor: .quaternaryLabelColor).opacity(0.4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(
                        isHovered
                            ? Color.accentColor
                            : Color(nsColor: .separatorColor),
                        lineWidth: 0.5
                    )
            )
            .frame(width: cellSize, height: cellSize)
            .contentShape(Rectangle())
            .onHover { inside in
                guard inside else { return }
                hoveredRow = row
                hoveredCol = col
                displayRows = Self.trayLength(for: row, max: GdockGridShape.maxRows)
                displayCols = Self.trayLength(for: col, max: GdockGridShape.maxCols)
            }
            .onTapGesture {
                onSelect(GdockGridShape(rows: row, cols: col))
            }
            .accessibilityIdentifier("GdockGridShapeCell.\(row).\(col)")
    }
}
