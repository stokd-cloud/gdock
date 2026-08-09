import SwiftUI
import UniformTypeIdentifiers

/// Accepts a tool chip dragged out of the mode bar and stacks it as a section.
///
/// The payload is the raw `RightSidebarMode` value as plain text, so this
/// prototype needs no custom exported UTType in `Info.plist`.
struct RightSidebarSectionDropDelegate: DropDelegate {
    @Binding var layout: RightSidebarSectionLayout
    /// The tool still shown above the stack; dropping it would leave the
    /// sidebar with nothing selected, so it is rejected.
    let selectedMode: RightSidebarMode

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        let dropY = info.location.y

        _ = provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let raw = value as? String,
                  let mode = RightSidebarMode(rawValue: raw),
                  mode.canOpenAsPane else {
                return
            }
            Task { @MainActor in
                // Height is unknown off the geometry reader; the resolved
                // ordering only needs a monotonic hint, and insertionIndex
                // clamps, so use the live section count as the scale.
                let assumedHeight = max(
                    CGFloat(layout.sections.count) * RightSidebarSectionLayout.minContentHeight,
                    RightSidebarSectionLayout.minContentHeight
                )
                let index = layout.insertionIndex(forDropAt: dropY, totalHeight: assumedHeight)
                layout.insert(mode, at: index)
            }
        }
        return true
    }
}
