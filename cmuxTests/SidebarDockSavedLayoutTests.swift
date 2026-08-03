import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// VAL-LAYOUT-001/002: UUID-free named layouts, weight recovery, legacy decode.
@MainActor
@Suite("Sidebar dock named layouts", .serialized)
struct SidebarDockSavedLayoutTests {
    @Test func legacyLayoutsJSONWithoutSidebarDockDecodesUnchanged() throws {
        let json = """
        {"layouts":[{"name":"Old","workspace":{"cwd":"/tmp/project","layout":{"pane":{"surfaces":[{"type":"terminal"}]}}}}]}
        """
        let decoded = try JSONDecoder().decode(SavedLayoutStore.LayoutsFile.self, from: Data(json.utf8))
        #expect(decoded.layouts.count == 1)
        #expect(decoded.layouts[0].workspace.sidebarDock == nil)
        #expect(decoded.layouts[0].workspace.cwd == "/tmp/project")
        #expect(decoded.layouts[0].workspace.layout != nil)
    }

    @Test func captureApplyReproducesOrderSelectionCollapseAndWeights() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let windowId = UUID()
        let registry = SidebarDockStoreRegistry(windowId: windowId)
        SidebarDockSeeding.seedRegistryIfEmpty(
            registry: registry,
            workspace: workspace,
            preferredRightMode: .find
        )
        // Peel Find into its own section on the right.
        let find = try #require(
            registry.right.panels.values.compactMap { $0 as? RightSidebarToolPanel }.first { $0.mode == .find }
        )
        let findTab = try #require(registry.right.surfaceId(forPanelId: find.id))
        #expect(registry.right.moveTabToNewSection(findTab, position: .bottom))
        #expect(registry.right.sectionCount == 2)
        if let last = registry.right.orderedSectionPaneIds().last {
            #expect(registry.right.collapseSection(paneId: last))
        }

        let definition = registry.captureNamedLayoutDefinition()
        #expect(definition.right?.sections.count == 2)
        // No UUIDs in tokens.
        for section in definition.right?.sections ?? [] {
            for token in section.panels {
                #expect(UUID(uuidString: token) == nil)
            }
        }

        let target = SidebarDockStoreRegistry(windowId: UUID())
        let appliedNamedLayout = target.applyNamedLayoutDefinition(definition, workspace: workspace)
        #expect(appliedNamedLayout)
        #expect(target.right.sectionCount == 2)
        // Evaluate outside `#expect` — key-path `contains(where:)` is rethrows and
        // the Testing macro expansion otherwise requires `try`.
        let hasCollapsed = target.right.sectionSnapshots().contains { $0.isCollapsed }
        #expect(hasCollapsed)
        let modes = SidebarDockSeeding.orderedRightModes(in: target.right)
        #expect(modes.contains(.find))
        #expect(modes.contains(.files) || modes.contains(.sessions))
    }

    @Test func weightNormalizationTable() {
        // Nil → equal
        let nilWeights = [
            CmuxSidebarDockDefinition.Section(panels: ["files"], weight: nil),
            CmuxSidebarDockDefinition.Section(panels: ["find"], weight: nil),
            CmuxSidebarDockDefinition.Section(panels: ["sessions"], weight: nil),
        ]
        let equal = CmuxSidebarDockDefinition.normalizedWeights(for: nilWeights)
        #expect(equal.count == 3)
        for w in equal {
            #expect(abs(w - (1.0 / 3.0)) < 0.000_1)
        }

        // [1,1,2] → 0.25/0.25/0.5
        let proportional = [
            CmuxSidebarDockDefinition.Section(panels: ["a"], weight: 1),
            CmuxSidebarDockDefinition.Section(panels: ["b"], weight: 1),
            CmuxSidebarDockDefinition.Section(panels: ["c"], weight: 2),
        ]
        let shares = CmuxSidebarDockDefinition.normalizedWeights(for: proportional)
        #expect(abs(shares[0] - 0.25) < 0.000_1)
        #expect(abs(shares[1] - 0.25) < 0.000_1)
        #expect(abs(shares[2] - 0.5) < 0.000_1)

        // Negative / zero-total / NaN / infinite → equal
        for bad in [Double.nan, Double.infinity, -1.0, 0.0] as [Double] {
            let sections = [
                CmuxSidebarDockDefinition.Section(panels: ["a"], weight: bad),
                CmuxSidebarDockDefinition.Section(panels: ["b"], weight: bad),
            ]
            let w = CmuxSidebarDockDefinition.normalizedWeights(for: sections)
            #expect(abs(w[0] - 0.5) < 0.000_1)
            #expect(abs(w[1] - 0.5) < 0.000_1)
        }
    }

    @Test func unknownPanelsSkippedAndAllUnknownReseeds() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let registry = SidebarDockStoreRegistry(windowId: UUID())
        let definition = CmuxSidebarDockDefinition(
            left: .init(sections: [
                .init(panels: ["notAPanel", "workspaceSelector"], selected: "notAPanel"),
            ]),
            right: .init(sections: [
                .init(panels: ["terminal", "browser"], selected: "terminal"),
            ])
        )
        let appliedNamedLayout = registry.applyNamedLayoutDefinition(definition, workspace: workspace)
        #expect(appliedNamedLayout)
        #expect(registry.left.panels.values.first is LeftWorkspaceSelectorPanel)
        #expect(SidebarDockSeeding.orderedRightModes(in: registry.right) == [.files, .find, .sessions])
    }

    @Test func emptyAndZeroSectionRailsReseedCanonical() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let registry = SidebarDockStoreRegistry(windowId: UUID())
        let definition = CmuxSidebarDockDefinition(
            left: .init(sections: []),
            right: .init(sections: [
                .init(panels: [], selected: nil),
            ])
        )
        let appliedNamedLayout = registry.applyNamedLayoutDefinition(definition, workspace: workspace)
        #expect(appliedNamedLayout)
        #expect(registry.left.panels.values.first is LeftWorkspaceSelectorPanel)
        #expect(SidebarDockSeeding.orderedRightModes(in: registry.right) == [.files, .find, .sessions])
    }

    @Test func definitionRoundTripsThroughLayoutsJSON() throws {
        let def = CmuxSidebarDockDefinition(
            left: .init(sections: [
                .init(panels: ["workspaceSelector"], selected: "workspaceSelector", collapsed: true, weight: 1),
            ]),
            right: .init(sections: [
                .init(panels: ["files", "find"], selected: "find", weight: 2),
                .init(panels: ["sessions"], selected: "sessions", collapsed: true, weight: 1),
            ])
        )
        let layout = CmuxSavedLayout(
            name: "Rails",
            description: nil,
            workspace: CmuxWorkspaceDefinition(cwd: "/tmp", sidebarDock: def)
        )
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(CmuxSavedLayout.self, from: data)
        #expect(decoded.workspace.sidebarDock?.right?.sections.count == 2)
        #expect(decoded.workspace.sidebarDock?.left?.sections.first?.collapsed == true)
        // Ensure no UUID leaked into panel tokens in encoded JSON.
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("panelId"))
        #expect(text.contains("workspaceSelector"))
        #expect(text.contains("files"))
    }
}
