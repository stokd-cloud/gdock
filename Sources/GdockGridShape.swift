import Foundation

/// The enforced rows × columns split shape for gdock Grid Mode.
///
/// Encoded as `"<rows>x<cols>"` (e.g. `"2x2"`, `"1x3"`) in
/// `gdock.gridModeShape`. Values are clamped to `1...maxRows` /
/// `1...maxCols`; anything unparseable decodes as the quad default so a
/// corrupt defaults value can never produce a degenerate layout.
struct GdockGridShape: Equatable, Hashable, Sendable {
    /// Upper bound for either axis. Terminal panes below roughly a sixth of
    /// a screen are unusable, so the picker and the parser share this cap.
    static let maxRows = 4
    static let maxCols = 4

    /// The default shape: a 2×2 quad.
    static let quad = GdockGridShape(rows: 2, cols: 2)

    let rows: Int
    let cols: Int

    init(rows: Int, cols: Int) {
        self.rows = min(max(rows, 1), Self.maxRows)
        self.cols = min(max(cols, 1), Self.maxCols)
    }

    var cellCount: Int { rows * cols }

    /// `"<rows>x<cols>"`, the persisted wire form.
    var encoded: String { "\(rows)x\(cols)" }

    /// Human-readable form for UI labels (multiplication sign, not "x").
    var displayText: String { "\(rows) × \(cols)" }

    /// Parses `"<rows>x<cols>"`; returns `nil` for anything else.
    init?(encoded: String) {
        let parts = encoded
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: "x")
        guard parts.count == 2,
              let rows = Int(parts[0]),
              let cols = Int(parts[1]),
              rows >= 1, cols >= 1 else {
            return nil
        }
        self.init(rows: rows, cols: cols)
    }
}
