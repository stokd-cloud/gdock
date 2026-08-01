import CoreGraphics
import Foundation

/// RED stub: wrong band constants so geometry assertions fail until green.
enum SidebarDockEdgeBand {
    // Intentionally wrong for red commit (must be 0.25 / 80).
    static let fraction: CGFloat = 0.10
    static let minimumPoints: CGFloat = 10

    enum Zone: String, Equatable, Sendable, CaseIterable {
        case top
        case bottom
        case center
        case left
        case right

        var isVerticalSectionBand: Bool {
            self == .top || self == .bottom
        }

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

    static func bandLength(for axisLength: CGFloat) -> CGFloat {
        max(minimumPoints, axisLength * fraction)
    }

    static func resolveZone(location: CGPoint, size: CGSize) -> Zone {
        .center
    }

    static func resolveZone(normalizedX: CGFloat, normalizedY: CGFloat, size: CGSize) -> Zone {
        .center
    }
}
