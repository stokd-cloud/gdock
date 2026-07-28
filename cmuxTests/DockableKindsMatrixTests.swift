import XCTest
import CmuxDockable

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Executable support matrix: count, kind set, create/restore probes, fail-closed.
@MainActor
final class DockableKindsMatrixTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DockableBootstrap.registerAllIfNeeded()
    }

    func testMatrixCoversExactlyElevenKinds() {
        XCTAssertEqual(DockableSupportMatrix.allRows.count, 11)
        XCTAssertEqual(DockableSupportMatrix.kindSet, Set(DockableKind.allCases))
        for kind in DockableKind.allCases {
            XCTAssertNotNil(DockableSupportMatrix.row(for: kind), "missing matrix row for \(kind)")
        }
    }

    func testCreateAndRestoreProbesForEveryNonEphemeralRow() throws {
        let workspace = Workspace()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dockable-matrix-\(UUID().uuidString).md")
        try "# matrix\n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let sidebarURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("matrix.cmuxsidebar")
        try "".write(to: sidebarURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: sidebarURL) }

        for row in DockableSupportMatrix.allRows {
            let context = Self.fullContext(
                for: row.kind,
                workspace: workspace,
                fileURL: fileURL,
                sidebarURL: sidebarURL
            )

            switch row.create {
            case .yes:
                let created = DockableBootstrap.make(
                    kind: row.kind,
                    context: context,
                    workspace: workspace
                )
                XCTAssertNotNil(created, "create should succeed for \(row.kind.rawValue)")
                XCTAssertEqual(created?.dockableKind, row.kind)

                // Fail-closed without required context for context-heavy kinds.
                if case .yes(let requirements) = row.create, !requirements.isEmpty {
                    let bare = DockableBootstrap.make(
                        kind: row.kind,
                        context: DockableCreateContext(),
                        workspace: nil
                    )
                    // Kinds that only need workspaceId may still succeed with a fresh UUID.
                    let needsMoreThanWorkspaceId = requirements.contains {
                        $0 != .workspaceId
                    }
                    if needsMoreThanWorkspaceId {
                        XCTAssertNil(
                            bare,
                            "create without context should fail closed for \(row.kind.rawValue)"
                        )
                    }
                }
            case .no:
                let created = DockableBootstrap.make(
                    kind: row.kind,
                    context: context,
                    workspace: workspace
                )
                XCTAssertNil(created, "create should be unsupported for \(row.kind.rawValue)")
            }

            switch row.restore {
            case .yes:
                guard let created = DockableBootstrap.make(
                    kind: row.kind,
                    context: context,
                    workspace: workspace
                ) else {
                    XCTFail("need created instance for restore probe of \(row.kind.rawValue)")
                    continue
                }
                let payload = try created.encodeDockPayload()
                let restored = DockableBootstrap.decode(
                    kind: row.kind,
                    payload: payload,
                    context: context,
                    workspace: workspace
                )
                XCTAssertNotNil(restored, "restore should succeed for \(row.kind.rawValue)")
                XCTAssertEqual(restored?.dockableKind, row.kind)
            case .emptyPayload:
                let restored = DockableBootstrap.decode(
                    kind: row.kind,
                    payload: Data(),
                    context: context,
                    workspace: workspace
                )
                XCTAssertNotNil(restored, "empty-payload restore for \(row.kind.rawValue)")
                XCTAssertEqual(restored?.dockableKind, row.kind)
            case .failClosed:
                let restored = DockableBootstrap.decode(
                    kind: row.kind,
                    payload: Data(),
                    context: context,
                    workspace: workspace
                )
                XCTAssertNil(restored, "restore should fail closed for \(row.kind.rawValue)")
            }

            // Ephemeral rows: document move support; create/restore still probed above.
            if row.move == .ephemeral {
                XCTAssertTrue(
                    row.kind == .extensionBrowser || row.kind == .cloudVMLoading,
                    "unexpected ephemeral kind \(row.kind.rawValue)"
                )
            }
        }
    }

    private static func fullContext(
        for kind: DockableKind,
        workspace: Workspace,
        fileURL: URL,
        sidebarURL: URL
    ) -> DockableCreateContext {
        var ctx = DockableCreateContext(workspaceId: workspace.id)
        ctx.filePath = fileURL.path
        ctx.projectPath = "/tmp/MatrixDemo.xcodeproj"
        ctx.rightSidebarMode = .files
        ctx.customSidebarName = "matrix"
        ctx.customSidebarFileURL = sidebarURL
        ctx.workingDirectory = FileManager.default.temporaryDirectory.path
        ctx.url = URL(string: "https://example.com/matrix")
        return ctx
    }
}
