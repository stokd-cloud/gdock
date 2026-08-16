import Foundation

/// Where a non-drag "move tab to new section" command places the new section.
enum SidebarDockSectionPosition: String, Sendable, CaseIterable {
    case top
    case bottom
}
