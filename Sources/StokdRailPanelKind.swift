import Foundation
import SwiftUI

/// Identity surface for stokd rail panels (fork-only).
///
/// Raw values are stable for persistence and match ``RightSidebarMode`` cases of
/// the same name so snapshots / tool tabs address the same strings.
///
/// Placement (§0 layout):
/// - ``stokdWork`` → right rail tool-tab strip
/// - ``stokdGlobalConfig``, ``stokdUsage`` → left rail sections
enum StokdRailPanelKind: String, CaseIterable, Codable, Sendable, Hashable {
    case stokdWork
    case stokdGlobalConfig
    case stokdUsage

    /// Preferred rail edge for seed and placement checks.
    var preferredEdge: SidebarDockEdge {
        switch self {
        case .stokdWork:
            return .right
        case .stokdGlobalConfig, .stokdUsage:
            return .left
        }
    }

    /// Backing right-sidebar mode (tool panel host).
    var rightSidebarMode: RightSidebarMode {
        switch self {
        case .stokdWork: return .stokdWork
        case .stokdGlobalConfig: return .stokdGlobalConfig
        case .stokdUsage: return .stokdUsage
        }
    }

    init?(rightSidebarMode mode: RightSidebarMode) {
        switch mode {
        case .stokdWork: self = .stokdWork
        case .stokdGlobalConfig: self = .stokdGlobalConfig
        case .stokdUsage: self = .stokdUsage
        case .files, .find, .sessions, .feed, .dock, .customSidebar:
            return nil
        }
    }

    var displayTitle: String {
        switch self {
        case .stokdWork:
            return String(localized: "stokdRail.panel.work", defaultValue: "Work")
        case .stokdGlobalConfig:
            return String(localized: "stokdRail.panel.globalConfig", defaultValue: "Global Config")
        case .stokdUsage:
            return String(localized: "stokdRail.panel.usage", defaultValue: "Usage")
        }
    }

    var symbolName: String {
        switch self {
        case .stokdWork: return "checklist"
        case .stokdGlobalConfig: return "gearshape.2"
        case .stokdUsage: return "chart.bar"
        }
    }

    /// Kinds allowed as right-rail tool tabs.
    static var rightRailKinds: [StokdRailPanelKind] { [.stokdWork] }

    /// Kinds allowed as left-rail sections (seed order: Global Config → Usage).
    static var leftRailKinds: [StokdRailPanelKind] {
        [.stokdGlobalConfig, .stokdUsage]
    }
}

// MARK: - Feature gate (Option A — Phase 1.2)

/// Enablement for stokd rail panels (Work / Global Config / Usage).
///
/// **Phase 1.2 decision — Option A:** Reuse `sidebar.beta.dock.enabled` rather than a
/// dedicated `sidebar.beta.stokdPanels.enabled` key. Stokd kinds only appear when the
/// shared rails beta gate is on; flag-off means no stokd kinds in seed, palette, or
/// tab strip. Missing UserDefaults key → false; never throws on read.
///
/// Option B (dedicated stokdPanels key still requiring rails) was not chosen for the
/// first slice: rails already own the host surface, and a second toggle would add
/// settings/catalog surface without changing the cold-start experience.
enum StokdRailPanelFeatureSettings {
    /// Shared rails dock beta key (`sidebar.beta.dock.enabled`). Not a dedicated
    /// stokdPanels UserDefaults key under Option A.
    static let enabledKey = RightSidebarBetaFeatureSettings.sidebarDockEnabledKey

    /// Product default: off until rails are explicitly enabled.
    static let defaultEnabled = false

    /// Option A marker for tests/callers: we did not ship `sidebar.beta.stokdPanels.enabled`.
    static let usesDedicatedStokdPanelsKey = false

    /// Whether stokd panel kinds may appear in seed, palette, or tab strip.
    ///
    /// Under Option A this matches ``RightSidebarBetaFeatureSettings/isSidebarDockEnabled(defaults:)``.
    /// Missing key → `false`; never throws.
    nonisolated static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        RightSidebarBetaFeatureSettings.isSidebarDockEnabled(defaults: defaults)
    }
}

// MARK: - Placeholder host (Phase 4 fills real UI)

/// Empty-but-stable host for stokd rail panels until Phase 4 implementations land.
struct StokdRailPanelPlaceholderView: View {
    let kind: StokdRailPanelKind

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: kind.symbolName)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(kind.displayTitle)
                .font(.headline)
            Text(
                String(
                    localized: "stokdRail.panel.placeholder.message",
                    defaultValue: "Coming soon"
                )
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("StokdRail.placeholder.\(kind.rawValue)")
        .accessibilityLabel(kind.displayTitle)
    }
}
