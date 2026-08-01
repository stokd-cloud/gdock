import AppKit
import Bonsplit
import SwiftUI

/// Renders one rail's ``SidebarDockStore`` Bonsplit tree.
///
/// Holds the store as a plain `let` (not `@ObservedObject` / `@EnvironmentObject`)
/// so list/row subtrees never re-evaluate from orthogonal store publishes.
/// Size-driven re-imposition runs from the size observer, never from `body`.
struct SidebarDockPanelView: View {
    let store: SidebarDockStore
    let isRailVisible: Bool
    /// Host-provided panel content for a tab. The view does not resolve
    /// workspace-specific tool chrome itself so snapshot boundaries stay clean.
    let contentForTab: (TabID, PaneID) -> AnyView

    @State private var visibilityHostId = UUID()
    @State private var lastReportedHeight: CGFloat = 0

    var body: some View {
        Group {
            if store.isSoleSectionCollapsed {
                soleSectionSurrogate
            } else {
                bonsplitTree
            }
        }
        .frame(maxWidth: .infinity, maxHeight: store.isSoleSectionCollapsed ? store.collapsedSectionHeight : .infinity)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: SidebarDockRailHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(SidebarDockRailHeightKey.self) { height in
            // Size observer — never mutate from pure body projection beyond this.
            guard abs(height - lastReportedHeight) > 0.5 else { return }
            lastReportedHeight = height
            store.updateRailContentHeight(height)
        }
        .accessibilityIdentifier(store.edge == .left ? "SidebarDock.left" : "SidebarDock.right")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(store.edge == .left
            ? String(localized: "sidebarDock.rail.left", defaultValue: "Left sidebar rail")
            : String(localized: "sidebarDock.rail.right", defaultValue: "Right sidebar rail"))
    }

    @ViewBuilder
    private var bonsplitTree: some View {
        BonsplitView(controller: store.bonsplitController) { tab, paneId in
            contentForTab(tab.id, paneId)
        } emptyPane: { paneId in
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onTapGesture { store.bonsplitController.focusPane(paneId) }
        }
        .contextMenu {
            // Section-level commands surface through the store API; tab context
            // menu items for move-to-new-section are registered on the controller
            // when mounts wire them. Keep this view free of store mutation loops.
        }
    }

    @ViewBuilder
    private var soleSectionSurrogate: some View {
        HStack(spacing: 8) {
            Text(String(localized: "sidebarDock.section.collapsed", defaultValue: "Collapsed"))
                .cmuxFont(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button {
                _ = store.expandSoleSection()
            } label: {
                Text(String(localized: "sidebarDock.section.expand", defaultValue: "Expand"))
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("SidebarDock.soleSection.expand")
            .accessibilityLabel(String(localized: "sidebarDock.section.expand", defaultValue: "Expand"))
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: store.collapsedSectionHeight, maxHeight: store.collapsedSectionHeight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SidebarDock.soleSection.surrogate")
    }
}

/// Preference key for rail content height (size observer path).
private struct SidebarDockRailHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
