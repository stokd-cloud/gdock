import AppKit
import Bonsplit
import SwiftUI

/// Renders one rail's ``SidebarDockStore`` Bonsplit tree.
///
/// Holds the store as a plain `let` (not `@ObservedObject` / `@EnvironmentObject`)
/// so list/row subtrees never re-evaluate from orthogonal store publishes.
/// Size-driven re-imposition runs from the size observer, never from `body`.
///
/// Hidden right rails short-circuit tool content (VAL-RAIL-010). Relocated
/// open-as-pane / close controls keep legacy accessibility ids.
struct SidebarDockPanelView: View {
    let store: SidebarDockStore
    let isRailVisible: Bool
    /// Host-provided panel content for a tab. The view does not resolve
    /// workspace-specific tool chrome itself so snapshot boundaries stay clean.
    let contentForTab: (TabID, PaneID) -> AnyView
    /// Relocated chrome (right rail only). Nil for left.
    var openAsPaneMode: RightSidebarMode? = nil
    var onOpenAsPane: ((RightSidebarMode) -> Void)? = nil
    var onClose: (() -> Void)? = nil
    /// When true, a hidden rail still mounts no tool content (VAL-RAIL-010).
    var shortCircuitHiddenContent: Bool = true

    @State private var lastReportedHeight: CGFloat = 0
    @State private var didTrackMount = false

    private var shouldMountToolContent: Bool {
        if shortCircuitHiddenContent, !isRailVisible {
            return false
        }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.edge == .right, onClose != nil || onOpenAsPane != nil {
                relocatedHeader
            }
            Group {
                if !shouldMountToolContent {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityHidden(true)
                } else if store.isSoleSectionCollapsed {
                    soleSectionSurrogate
                } else {
                    bonsplitTree
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: store.isSoleSectionCollapsed && shouldMountToolContent ? store.collapsedSectionHeight : .infinity)
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
        .onAppear { syncMountState() }
        .onChange(of: isRailVisible) { _, _ in syncMountState() }
        .onChange(of: shouldMountToolContent) { _, _ in syncMountState() }
        .accessibilityIdentifier(store.edge == .left ? "SidebarDock.left" : "SidebarDock.right")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(store.edge == .left
            ? String(localized: "sidebarDock.rail.left", defaultValue: "Left sidebar rail")
            : String(localized: "sidebarDock.rail.right", defaultValue: "Right sidebar rail"))
    }

    private func syncMountState() {
        store.setToolContentMounted(shouldMountToolContent)
        didTrackMount = true
    }

    @ViewBuilder
    private var relocatedHeader: some View {
        HStack(spacing: RightSidebarChromeMetrics.headerControlSpacing) {
            Spacer(minLength: 0)
            if let mode = openAsPaneMode, mode.canOpenAsPane, let onOpenAsPane {
                Button {
                    onOpenAsPane(mode)
                } label: {
                    HeaderChromeIconStyle.symbol("rectangle.split.2x1")
                }
                .buttonStyle(RightSidebarHeaderIconButtonStyle(iconGeometryKeyPrefix: "rightSidebarHeaderOpenAsPaneIcon"))
                .frame(
                    width: RightSidebarChromeMetrics.headerControlSize,
                    height: RightSidebarChromeMetrics.headerControlSize
                )
                .safeHelp(String(localized: "rightSidebar.openAsPane.tooltip", defaultValue: "Open as pane"))
                .accessibilityLabel(
                    String.localizedStringWithFormat(
                        String(localized: "rightSidebar.openAsPane.accessibilityLabel", defaultValue: "Open %@ as Pane"),
                        mode.label
                    )
                )
                .accessibilityIdentifier("RightSidebar.openAsPaneButton")
                .titlebarInteractiveControl()
            }
            if let onClose {
                Button(action: onClose) {
                    HeaderChromeIconStyle.symbol("xmark")
                }
                .buttonStyle(RightSidebarHeaderIconButtonStyle(iconGeometryKeyPrefix: "rightSidebarHeaderCloseIcon"))
                .frame(
                    width: RightSidebarChromeMetrics.headerControlSize,
                    height: RightSidebarChromeMetrics.headerControlSize
                )
                .safeHelp(
                    KeyboardShortcutSettings.Action.toggleRightSidebar.tooltip(
                        String(localized: "rightSidebar.toggle.tooltip", defaultValue: "Toggle right sidebar")
                    )
                )
                .accessibilityLabel(String(localized: "rightSidebar.close.accessibilityLabel", defaultValue: "Close Right Sidebar"))
                .accessibilityIdentifier("RightSidebar.closeButton")
                .titlebarInteractiveControl()
            }
        }
        .rightSidebarChromeBar(leadingPadding: 4, trailingPadding: 6, height: store.collapsedSectionHeight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("RightSidebarModeBar")
    }

    @ViewBuilder
    private var bonsplitTree: some View {
        // Header chrome uses an immutable snapshot; menu items are resolved when opened.
        let headerSnapshot = store.focusedSectionHeaderControlsSnapshot()
        VStack(spacing: 0) {
            if let headerSnapshot, headerSnapshot.sectionCount >= 2 {
                focusedSectionHeaderControls(snapshot: headerSnapshot)
            }
            BonsplitView(controller: store.bonsplitController) { tab, paneId in
                contentForTab(tab.id, paneId)
            } emptyPane: { paneId in
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onTapGesture { store.bonsplitController.focusPane(paneId) }
            }
            .contextMenu {
                sectionContextMenuButtons(
                    items: store.sectionContextMenuItems(for: store.bonsplitController.focusedPaneId)
                )
            }
        }
    }

    /// Focused-section chrome: collapse/expand/reorder via shared invoker path.
    /// Built from an immutable snapshot so this strip never holds orthogonal store state.
    @ViewBuilder
    private func focusedSectionHeaderControls(
        snapshot: SidebarDockSectionHeaderControlsSnapshot
    ) -> some View {
        let paneId = PaneID(id: snapshot.paneId)
        HStack(spacing: 4) {
            if snapshot.showsHeaderDragAffordance {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                    .help(String(localized: "sidebarDock.section.dragAffordance", defaultValue: "Drag section header to reorder"))
                    .accessibilityIdentifier("SidebarDock.section.headerDragAffordance")
                    // Whole-section header drag: vertical translation reorders via the
                    // same command/mutation path as palette/context reorder buttons.
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onEnded { value in
                                Self.handleSectionHeaderDragEnded(
                                    store: store,
                                    snapshot: snapshot,
                                    translationY: value.translation.height
                                )
                            }
                    )
            }
            Spacer(minLength: 0)
            if snapshot.canReorderUp {
                Button {
                    _ = store.performSectionContextMenuCommand(
                        SidebarDockCommand.reorderSectionUp,
                        paneId: paneId
                    )
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("SidebarDock.section.reorderUp")
                .accessibilityLabel(SidebarDockCommand.title(for: SidebarDockCommand.reorderSectionUp))
            }
            if snapshot.canReorderDown {
                Button {
                    _ = store.performSectionContextMenuCommand(
                        SidebarDockCommand.reorderSectionDown,
                        paneId: paneId
                    )
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("SidebarDock.section.reorderDown")
                .accessibilityLabel(SidebarDockCommand.title(for: SidebarDockCommand.reorderSectionDown))
            }
            if snapshot.canCollapse {
                Button {
                    _ = store.performSectionContextMenuCommand(
                        SidebarDockCommand.collapseSection,
                        paneId: paneId
                    )
                } label: {
                    Image(systemName: "rectangle.bottomhalf.inset.filled")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("SidebarDock.section.collapse")
                .accessibilityLabel(SidebarDockCommand.title(for: SidebarDockCommand.collapseSection))
            }
            if snapshot.canExpand {
                Button {
                    _ = store.performSectionContextMenuCommand(
                        SidebarDockCommand.expandSection,
                        paneId: paneId
                    )
                } label: {
                    Image(systemName: "rectangle.tophalf.inset.filled")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("SidebarDock.section.expand")
                .accessibilityLabel(SidebarDockCommand.title(for: SidebarDockCommand.expandSection))
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SidebarDock.section.headerControls")
        // Full-header drag target (not only the affordance icon).
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    Self.handleSectionHeaderDragEnded(
                        store: store,
                        snapshot: snapshot,
                        translationY: value.translation.height
                    )
                }
        )
    }

    /// Header-drag completion: reorder by one step via the shared invoker path.
    fileprivate static func handleSectionHeaderDragEnded(
        store: SidebarDockStore,
        snapshot: SidebarDockSectionHeaderControlsSnapshot,
        translationY: CGFloat
    ) {
        let paneId = PaneID(id: snapshot.paneId)
        let threshold: CGFloat = 12
        if translationY < -threshold, snapshot.canReorderUp {
            _ = store.performSectionContextMenuCommand(
                SidebarDockCommand.reorderSectionUp,
                paneId: paneId
            )
        } else if translationY > threshold, snapshot.canReorderDown {
            _ = store.performSectionContextMenuCommand(
                SidebarDockCommand.reorderSectionDown,
                paneId: paneId
            )
        }
    }

    @ViewBuilder
    private func sectionContextMenuButtons(items: [SidebarDockCommand.MenuItem]) -> some View {
        ForEach(items) { item in
            Button(item.title) {
                _ = store.performSectionContextMenuCommand(item.id, paneId: store.bonsplitController.focusedPaneId)
            }
            .disabled(!item.isEnabled)
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
                // Sole-left Expand must share the invoker/command path (VAL-RAIL-001).
                _ = store.performSectionContextMenuCommand(
                    SidebarDockCommand.expandSection,
                    paneId: store.orderedSectionPaneIds().first
                )
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
