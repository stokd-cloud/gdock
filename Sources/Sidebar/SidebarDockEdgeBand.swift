import CoreGraphics
import Foundation

/// Rail edge-band geometry for section-create drops.
///
/// Matches Bonsplit's pane drop zones: **25% of the relevant axis with an 80pt
/// minimum**. Left/right (horizontal) bands take priority at corners so a
/// horizontal refuse can be proven without mutating the rail tree.
enum SidebarDockEdgeBand {
    static let fraction: CGFloat = 0.25
    static let minimumPoints: CGFloat = 80

    /// Drop band resolved from a point inside a section/rail frame.
    enum Zone: String, Equatable, Sendable, CaseIterable {
        case top
        case bottom
        case center
        case left
        case right

        /// Vertical section-create bands used by VAL-RAIL-003.
        var isVerticalSectionBand: Bool {
            self == .top || self == .bottom
        }

        /// Horizontal bands are always refused on rails (VAL-RAIL-004).
        var isHorizontalRefuseBand: Bool {
            self == .left || self == .right
        }

        var sectionPosition: SidebarDockSectionPosition? {
            switch self {
            case .top: return .top
            case .bottom: return .bottom
            default: return nil
            }
        }
    }

    /// Edge band thickness for one axis length (max(80, length × 0.25)).
    static func bandLength(for axisLength: CGFloat) -> CGFloat {
        max(minimumPoints, axisLength * fraction)
    }

    /// Resolve the drop zone for a location inside `size`.
    /// Left/right take priority at corners (Bonsplit parity).
    static func resolveZone(location: CGPoint, size: CGSize) -> Zone {
        let horizontalEdge = bandLength(for: size.width)
        let verticalEdge = bandLength(for: size.height)
        if location.x < horizontalEdge {
            return .left
        }
        if location.x > size.width - horizontalEdge {
            return .right
        }
        if location.y < verticalEdge {
            return .top
        }
        if location.y > size.height - verticalEdge {
            return .bottom
        }
        return .center
    }

    /// Convenience: resolve from normalized 0…1 coordinates inside the target.
    static func resolveZone(normalizedX: CGFloat, normalizedY: CGFloat, size: CGSize) -> Zone {
        let location = CGPoint(
            x: max(0, min(1, normalizedX)) * size.width,
            y: max(0, min(1, normalizedY)) * size.height
        )
        return resolveZone(location: location, size: size)
    }
}
