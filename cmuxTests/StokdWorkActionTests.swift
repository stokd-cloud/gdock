import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// VAL-ACTION-001: one shared action table drives every entrypoint.
@Suite("Stokd Work actions")
@MainActor
struct StokdWorkActionTests {
    private func freshDefaults() -> UserDefaults {
        let name = "stokdWork.actions.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func entryListsPerKindMatchTheContractAndHideInvalidVerbs() {
        #expect(StokdWorkActionTable.actions(kind: .task, status: "pending") == [
            .start, .startInWorktree, .resume, .integrate, .review,
            .addNote, .setPriority, .markCompleted, .delete, .copyHash, .openInTerminal,
        ])
        #expect(StokdWorkActionTable.actions(kind: .project, status: "active") == [
            .start, .advance, .report, .integrate,
            .addNote, .setPriority, .markCompleted, .delete, .copyHash, .openInTerminal,
        ])
        #expect(StokdWorkActionTable.actions(kind: .todo, status: "pending") == [
            .start, .addNote, .markCompleted, .delete, .copyHash, .openInTerminal,
        ])
        for status in ["completed", "cancelled", "failed"] {
            for kind in StokdWorkItemKind.allCases {
                #expect(!StokdWorkActionTable.actions(kind: kind, status: status).contains(.markCompleted), "\(kind) \(status)")
            }
        }
    }

    @Test func everyEntryProducesItsDocumentedArgumentVector() {
        let hash = "8b4b164"
        #expect(StokdWorkActionTable.arguments(for: .start, kind: .task, hash: hash, input: nil) == ["task", "start", hash])
        #expect(StokdWorkActionTable.arguments(for: .startInWorktree, kind: .task, hash: hash, input: nil) == ["task", "start", "--worktree", hash])
        #expect(StokdWorkActionTable.arguments(for: .resume, kind: .task, hash: hash, input: nil) == ["task", "resume", hash])
        #expect(StokdWorkActionTable.arguments(for: .integrate, kind: .task, hash: hash, input: nil) == ["task", "integrate", hash])
        #expect(StokdWorkActionTable.arguments(for: .review, kind: .task, hash: hash, input: nil) == ["task", "review", hash])
        #expect(StokdWorkActionTable.arguments(for: .addNote, kind: .task, hash: hash, input: "remember this") == ["task", "note", hash, "remember this"])
        #expect(StokdWorkActionTable.arguments(for: .setPriority, kind: .task, hash: hash, input: "3") == ["task", "priority", hash, "3"])
        #expect(StokdWorkActionTable.arguments(for: .markCompleted, kind: .task, hash: hash, input: nil) == ["task", "complete", hash])
        #expect(StokdWorkActionTable.arguments(for: .delete, kind: .task, hash: hash, input: nil) == ["task", "delete", hash])
        #expect(StokdWorkActionTable.arguments(for: .openInTerminal, kind: .task, hash: hash, input: nil) == ["task", "view", hash])

        #expect(StokdWorkActionTable.arguments(for: .start, kind: .project, hash: hash, input: nil) == ["project", "start", hash])
        #expect(StokdWorkActionTable.arguments(for: .advance, kind: .project, hash: hash, input: nil) == ["project", "advance", hash])
        #expect(StokdWorkActionTable.arguments(for: .report, kind: .project, hash: hash, input: nil) == ["project", "report", hash])
        #expect(StokdWorkActionTable.arguments(for: .integrate, kind: .project, hash: hash, input: nil) == ["project", "integrate", hash])
        #expect(StokdWorkActionTable.arguments(for: .addNote, kind: .project, hash: hash, input: "n") == ["project", "note", hash, "n"])
        #expect(StokdWorkActionTable.arguments(for: .setPriority, kind: .project, hash: hash, input: "none") == ["project", "priority", hash, "none"])
        #expect(StokdWorkActionTable.arguments(for: .markCompleted, kind: .project, hash: hash, input: nil) == ["project", "complete", hash])
        #expect(StokdWorkActionTable.arguments(for: .delete, kind: .project, hash: hash, input: nil) == ["project", "delete", hash])

        #expect(StokdWorkActionTable.arguments(for: .start, kind: .todo, hash: hash, input: nil) == ["todo", "start", hash])
        #expect(StokdWorkActionTable.arguments(for: .addNote, kind: .todo, hash: hash, input: "n") == ["todo", "note", hash, "n"])
        #expect(StokdWorkActionTable.arguments(for: .markCompleted, kind: .todo, hash: hash, input: nil) == ["todo", "complete", hash])
        #expect(StokdWorkActionTable.arguments(for: .delete, kind: .todo, hash: hash, input: nil) == ["todo", "delete", hash])

        #expect(StokdWorkActionTable.arguments(for: .copyHash, kind: .task, hash: hash, input: nil) == nil)
        #expect(StokdWorkActionTable.arguments(for: .addNote, kind: .task, hash: hash, input: "   ") == nil)
        #expect(StokdWorkActionTable.arguments(for: .setPriority, kind: .task, hash: hash, input: "abc") == nil)
    }

    @Test func confirmationGatesDestructiveVerbsAndInteractiveVerbsOpenATerminal() async {
        let client = FakeStokdWorkCLIClient()
        let loader = FixtureStokdWorkLoader(payload: StokdWorkPayload(
            tasks: [StokdWorkFixtures.task(id: "t1", hash: "8b4b164", title: "Repair", updatedAt: "2026-08-20T12:00:00Z")],
            projects: [], todos: [], limitPerKind: 500, error: nil
        ))
        let launched = LaunchRecorder()
        let model = StokdWorkPanelViewModel(
            loader: loader,
            actionClient: client,
            defaults: freshDefaults(),
            terminalLauncher: { command, directory in launched.record(command: command, directory: directory) }
        )
        model.refresh(repoSlug: "owner/repo", directory: "/repos/x")
        await stokdWorkWaitUntil { model.state == .populated }
        let row = model.rows[0]

        // Destructive verbs stop at a confirmation request; nothing is dispatched yet.
        model.requestAction(.markCompleted, on: row)
        #expect(model.pendingAction?.action == .markCompleted)
        #expect(model.pendingAction?.needsConfirmation == true)
        #expect(await client.recordedArguments().isEmpty)

        model.cancelPendingAction()
        #expect(model.pendingAction == nil)
        #expect(await client.recordedArguments().isEmpty)

        model.requestAction(.delete, on: row)
        #expect(model.pendingAction?.needsConfirmation == true)
        model.confirmPendingAction(input: nil)
        await stokdWorkWaitUntilAsync { await client.recordedArguments().count == 1 }
        await stokdWorkWaitUntil { model.isPerformingAction == false }
        #expect(await client.recordedArguments() == [["task", "delete", "8b4b164"]])
        #expect(model.pendingAction == nil)

        // Input verbs stop at a prompt and dispatch with the entered text.
        model.requestAction(.addNote, on: row)
        #expect(model.pendingAction?.needsInput == true)
        model.confirmPendingAction(input: "keep going")
        await stokdWorkWaitUntilAsync { await client.recordedArguments().count == 2 }
        #expect(await client.recordedArguments().last == ["task", "note", "8b4b164", "keep going"])

        // Interactive verbs never run hidden: they open a terminal running the verb.
        model.requestAction(.start, on: row)
        #expect(model.pendingAction == nil)
        #expect(launched.commands == ["stokd task start 8b4b164"])
        #expect(launched.directories == ["/repos/x"])
        model.requestAction(.openInTerminal, on: row)
        #expect(launched.commands.last == "stokd task view 8b4b164")
        #expect(await client.recordedArguments().count == 2)
    }

    @Test func nonZeroExitSurfacesStderrAndSuccessRefreshesTheList() async {
        let client = FakeStokdWorkCLIClient(fallback: StokdWorkFixtures.failure(exit: 1, stderr: "error: priority must be a slot"))
        let loader = RecordingLimitStokdWorkLoader { limit in
            StokdWorkPayload(
                tasks: [StokdWorkFixtures.task(id: "t1", hash: "8b4b164", title: "Repair", updatedAt: "2026-08-20T12:00:00Z")],
                projects: [], todos: [], limitPerKind: limit, error: nil
            )
        }
        let model = StokdWorkPanelViewModel(loader: loader, actionClient: client, defaults: freshDefaults())
        model.refresh(repoSlug: "owner/repo", directory: "/repos/x")
        await stokdWorkWaitUntil { model.state == .populated }
        #expect(await loader.recordedLimits().count == 1)

        model.requestAction(.setPriority, on: model.rows[0])
        model.confirmPendingAction(input: "9")
        await stokdWorkWaitUntil { model.actionErrorMessage != nil }
        #expect(model.actionErrorMessage?.contains("priority must be a slot") == true)
        #expect(await loader.recordedLimits().count == 1)

        model.dismissActionError()
        #expect(model.actionErrorMessage == nil)

        await client.respond(to: ["task", "complete"], with: StokdWorkFixtures.success("done"))
        model.requestAction(.markCompleted, on: model.rows[0])
        model.confirmPendingAction(input: nil)
        await stokdWorkWaitUntilAsync { await loader.recordedLimits().count == 2 }
        #expect(model.actionErrorMessage == nil)
    }
}

@MainActor
private final class LaunchRecorder {
    private(set) var commands: [String] = []
    private(set) var directories: [String] = []

    func record(command: String, directory: String) {
        commands.append(command)
        directories.append(directory)
    }
}
