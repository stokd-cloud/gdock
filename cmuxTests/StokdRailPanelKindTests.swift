import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Stokd rail panel kinds, stable raw values, and placement matrix.
///
/// The Worktrees kind was removed: it only ever rendered a "Coming soon"
/// placeholder, and the real design lives in the hold-to-show worktree-panel
/// PRDs (stokd projects c6142e5 / dec8b3c), which share none of this surface.
@Suite("Stokd rail panel kinds")
struct StokdRailPanelKindTests {
    @Test func threeKindsExistWithStableRawValues() {
        let kinds = StokdRailPanelKind.allCases
        #expect(kinds.count == 3)
        #expect(Set(kinds.map(\.rawValue)) == [
            "stokdWork",
            "stokdGlobalConfig",
            "stokdUsage",
        ])

        #expect(StokdRailPanelKind(rawValue: "stokdWork") == .stokdWork)
        #expect(StokdRailPanelKind(rawValue: "stokdGlobalConfig") == .stokdGlobalConfig)
        #expect(StokdRailPanelKind(rawValue: "stokdUsage") == .stokdUsage)
        #expect(StokdRailPanelKind(rawValue: "unknown-kind") == nil)
    }

    /// The removed Worktrees surface must be gone from every addressable identity.
    @Test func worktreesRailPanelIsRemovedEverywhere() {
        #expect(StokdRailPanelKind(rawValue: "stokdWorktrees") == nil)
        #expect(RightSidebarMode(rawValue: "stokdWorktrees") == nil)
        #expect(StokdRailPanelKind.leftRailKinds == [.stokdGlobalConfig, .stokdUsage])
        #expect(!StokdRailPanelKind.allCases.contains { $0.displayTitle == "Worktrees" })
        #expect(!RightSidebarMode.allCases.contains { $0.label == "Worktrees" })

        // No command palette entry may address the removed panel.
        let paletteIDs = RightSidebarMode.allCases.map(ContentView.commandPaletteRightSidebarModeCommandID)
        #expect(!paletteIDs.contains("palette.gdock.showStokdWorktrees"))
    }

    /// A snapshot written by an older build degrades to the default panel
    /// instead of restoring an empty placeholder.
    @Test func persistedWorktreesModeDegradesToDefault() throws {
        let json = Data(#"{"mode":"stokdWorktrees"}"#.utf8)
        let snapshot = try JSONDecoder().decode(SessionRightSidebarToolPanelSnapshot.self, from: json)
        #expect(snapshot.mode == nil)
        #expect((snapshot.mode ?? .files) == .files)
    }

    @Test func kindsMapToRightSidebarModesWithMatchingRawValues() {
        for kind in StokdRailPanelKind.allCases {
            #expect(kind.rightSidebarMode.rawValue == kind.rawValue)
            #expect(RightSidebarMode(rawValue: kind.rawValue) == kind.rightSidebarMode)
        }
    }

    @Test func placementMatrixAllowsWorkOnRightAndOthersOnLeft() {
        // Work → right tool-tab strip only.
        #expect(SidebarDockPlacementMatrix.allows(mode: .stokdWork, on: .right))
        #expect(!SidebarDockPlacementMatrix.allows(mode: .stokdWork, on: .left))
        #expect(SidebarDockPlacementMatrix.allows(kind: .stokdWork, on: .right))
        #expect(!SidebarDockPlacementMatrix.allows(kind: .stokdWork, on: .left))

        // Global Config / Usage → left rail sections only.
        let leftKinds: [StokdRailPanelKind] = [.stokdGlobalConfig, .stokdUsage]
        for kind in leftKinds {
            #expect(SidebarDockPlacementMatrix.allows(kind: kind, on: .left))
            #expect(!SidebarDockPlacementMatrix.allows(kind: kind, on: .right))
            #expect(SidebarDockPlacementMatrix.allows(mode: kind.rightSidebarMode, on: .left))
            #expect(!SidebarDockPlacementMatrix.allows(mode: kind.rightSidebarMode, on: .right))
        }

        // Edge-agnostic allowlist still admits stokd modes for registry addressing.
        #expect(SidebarDockPlacementMatrix.allows(mode: .stokdWork))
        #expect(SidebarDockPlacementMatrix.allows(mode: .stokdGlobalConfig))
        #expect(SidebarDockPlacementMatrix.allows(mode: .stokdUsage))

        // Legacy modes unchanged.
        #expect(SidebarDockPlacementMatrix.allows(mode: .files))
        #expect(SidebarDockPlacementMatrix.allows(mode: .find))
        #expect(SidebarDockPlacementMatrix.allows(mode: .sessions))
        #expect(!SidebarDockPlacementMatrix.allows(mode: .feed))
        #expect(!SidebarDockPlacementMatrix.allows(mode: .dock))
        #expect(!SidebarDockPlacementMatrix.allows(mode: .customSidebar))
    }

    @Test func displayTitlesAreNonEmptyLocalizedStrings() {
        for kind in StokdRailPanelKind.allCases {
            #expect(!kind.displayTitle.isEmpty)
            #expect(!kind.rightSidebarMode.label.isEmpty)
            #expect(kind.displayTitle == kind.rightSidebarMode.label)
        }
        #expect(StokdRailPanelKind.stokdWork.displayTitle == "Work")
        #expect(StokdRailPanelKind.stokdGlobalConfig.displayTitle == "Global Config")
        #expect(StokdRailPanelKind.stokdUsage.displayTitle == "Usage")
    }

    @Test func unknownModeRawValueSkipsWithoutCrash() {
        // Persistence path: unknown mode string → nil, never throws.
        #expect(RightSidebarMode(rawValue: "stokdFuturePanel") == nil)
        #expect(StokdRailPanelKind(rawValue: "stokdFuturePanel") == nil)
        let snap = SessionRightSidebarToolPanelSnapshot(mode: nil)
        #expect(snap.mode == nil)
    }

    @MainActor
    @Test func placeholderHostsMountWithoutCrashing() {
        let workspace = Workspace()
        for kind in StokdRailPanelKind.allCases {
            let panel = RightSidebarToolPanel(workspace: workspace, mode: kind.rightSidebarMode)
            #expect(panel.panelType == .rightSidebarTool)
            #expect(panel.mode == kind.rightSidebarMode)
            #expect(panel.displayTitle == kind.displayTitle)

            let placeholder = StokdRailPanelPlaceholderView(kind: kind)
            _ = placeholder.body
            #expect(StokdRailPanelKind(rightSidebarMode: panel.mode) == kind)
        }
    }
}
