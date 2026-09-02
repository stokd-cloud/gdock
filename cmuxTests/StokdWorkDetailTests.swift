import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// VAL-DETAIL-001: selecting a row opens an in-panel detail parsed from the CLI.
@Suite("Stokd Work detail")
@MainActor
struct StokdWorkDetailTests {
    private func freshDefaults() -> UserDefaults {
        let name = "stokdWork.detail.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func taskTextParsesIdentityDescriptionCriteriaAndNotes() {
        let detail = StokdWorkDetailParser.parse(kind: .task, output: StokdWorkFixtures.taskGetText)

        #expect(detail.isParsed)
        #expect(detail.kind == .task)
        #expect(detail.hash == "8b4b164")
        #expect(detail.title == "Repair: Distinct gdock tags that differ")
        #expect(detail.status == "pending")
        #expect(detail.fields["Components"] == "scripts/gdock-run")
        #expect(detail.description?.hasPrefix("Objective:") == true)
        #expect(detail.description?.contains("Both --path results") == true)
        #expect(detail.acceptanceCriteria.count == 2)
        #expect(detail.acceptanceCriteria.first?.hasPrefix("`a=$(gdock-build") == true)
        #expect(detail.notes == ["2026-09-02 first attempt reproduced the alias."])
        #expect(detail.rawText == StokdWorkFixtures.taskGetText)
    }

    @Test func projectTextParsesHeaderPRDStatusAndNotes() {
        let detail = StokdWorkDetailParser.parse(kind: .project, output: StokdWorkFixtures.projectGetText)

        #expect(detail.isParsed)
        #expect(detail.kind == .project)
        #expect(detail.hash == "38f437b")
        #expect(detail.title == "Stokd Work Panel")
        #expect(detail.status == "active")
        #expect(detail.repoSlug == "owner/repo")
        #expect(detail.fields["Slug"] == "stokd-work-panel")
        #expect(detail.description?.hasPrefix("# Stokd Work Panel") == true)
        #expect(detail.description?.contains("rhubarb") == true)
        #expect(detail.sections.map(\.title) == ["Status"])
        #expect(detail.sections.first?.body.contains("[Phase 1]") == true)
        #expect(detail.notes == ["Session 2026-09-02 executing Phase 1."])
    }

    @Test func todoJSONParsesEveryChecklistItemWithStatus() {
        let detail = StokdWorkDetailParser.parse(kind: .todo, output: StokdWorkFixtures.todoViewJSON)

        #expect(detail.isParsed)
        #expect(detail.kind == .todo)
        #expect(detail.hash == "3572f77")
        #expect(detail.title == "CLI data-structure optimization")
        #expect(detail.status == "in_progress")
        #expect(detail.repoSlug == "other/mono")
        #expect(detail.checklist.map(\.title) == ["Shared contracts", "Daemon types"])
        #expect(detail.checklist.map(\.status) == ["completed", "pending"])
        #expect(detail.fields["Ordered"] == "true")
    }

    @Test func unparseableOutputDegradesToRawTextNeverEmpty() {
        let garbage = "totally unexpected\noutput shape"
        let task = StokdWorkDetailParser.parse(kind: .task, output: garbage)
        #expect(task.isParsed == false)
        #expect(task.rawText == garbage)
        #expect(task.title == nil)

        let todo = StokdWorkDetailParser.parse(kind: .todo, output: "{ not json")
        #expect(todo.isParsed == false)
        #expect(todo.rawText == "{ not json")

        let empty = StokdWorkDetailParser.parse(kind: .project, output: "")
        #expect(empty.isParsed == false)
        #expect(empty.rawText == "")
    }

    @Test func detailIsASplitPaneSoOtherRowsStaySelectable() async {
        let loader = FixtureStokdWorkLoader(payload: StokdWorkPayload(
            tasks: [
                StokdWorkFixtures.task(id: "t1", hash: "8b4b164", title: "Repair", updatedAt: "2026-08-20T12:00:00Z"),
                StokdWorkFixtures.task(id: "t2", hash: "adb3051", title: "Fast path", updatedAt: "2026-08-20T11:00:00Z"),
            ],
            projects: [], todos: [], limitPerKind: 100, error: nil
        ))
        let detailLoader = FixtureStokdWorkDetailLoader(bodies: [
            "8b4b164": .success(StokdWorkFixtures.taskGetText),
            "adb3051": .success("Task #adb3051  Fast path\n────────\nStatus:  in_progress\n"),
        ])
        let defaults = freshDefaults()
        let model = StokdWorkPanelViewModel(loader: loader, detailLoader: detailLoader, defaults: defaults)
        model.refresh(repoSlug: "owner/repo", directory: "/repos/x")
        await stokdWorkWaitUntil { model.state == .populated }

        model.select(rowID: "task:t1")
        await stokdWorkWaitUntil { model.detailState?.isLoaded == true }
        #expect(model.rows.count == 2, "the list stays in place next to the detail")
        #expect(model.isRowSelected("task:t1"))
        #expect(!model.isRowSelected("task:t2"))

        model.select(rowID: "task:t2")
        await stokdWorkWaitUntil { model.detailState?.detail?.hash == "adb3051" }
        #expect(model.isRowSelected("task:t2"))
        #expect(model.rows.count == 2)

        // Re-selecting the open row toggles the pane closed; the split height persists.
        model.select(rowID: "task:t2")
        #expect(model.selectedRow == nil)
        model.setDetailPaneHeight(333)
        #expect(StokdWorkPanelSettings.detailPaneHeight(defaults: defaults) == 333)
        #expect(StokdWorkPanelSettings.detailPaneHeightKey.userDefaultsKey == "gdock.workPanel.detailHeight")
        #expect(StokdWorkPanelSettings.detailPaneHeight(defaults: freshDefaults()) == StokdWorkPanelSettings.defaultDetailPaneHeight)
    }

    @Test func selectingARowLoadsDetailAndFailuresOfferRetry() async {
        let loader = FixtureStokdWorkLoader(payload: StokdWorkPayload(
            tasks: [StokdWorkFixtures.task(id: "t1", hash: "8b4b164", title: "Repair", updatedAt: "2026-08-20T12:00:00Z")],
            projects: [], todos: [], limitPerKind: 500, error: nil
        ))
        let detailLoader = FixtureStokdWorkDetailLoader(bodies: [
            "8b4b164": .success(StokdWorkFixtures.taskGetText),
        ])
        let model = StokdWorkPanelViewModel(loader: loader, detailLoader: detailLoader, defaults: freshDefaults())
        model.refresh(repoSlug: "owner/repo", directory: "/repos/x")
        await stokdWorkWaitUntil { model.state == .populated }

        #expect(model.selectedRow == nil)
        model.select(rowID: model.rows[0].id)
        #expect(model.selectedRow?.rawID == "t1")
        await stokdWorkWaitUntil { model.detailState?.isLoaded == true }
        #expect(model.detailState?.detail?.title == "Repair: Distinct gdock tags that differ")
        #expect(model.detailState?.detail?.acceptanceCriteria.count == 2)

        // Cached: reopening does not refetch.
        model.closeDetail()
        #expect(model.selectedRow == nil)
        model.select(rowID: model.rows[0].id)
        #expect(model.detailState?.isLoaded == true)
        #expect(await detailLoader.recordedHashes() == ["8b4b164"])

        // Failure path: stderr is shown and Retry re-invokes the loader.
        let failing = FixtureStokdWorkDetailLoader(bodies: [
            "8b4b164": .failure(StokdWorkLoadError(kind: .exit(1), message: "error: task not found")),
        ])
        let failingModel = StokdWorkPanelViewModel(loader: loader, detailLoader: failing, defaults: freshDefaults())
        failingModel.refresh(repoSlug: "owner/repo", directory: "/repos/x")
        await stokdWorkWaitUntil { failingModel.state == .populated }
        failingModel.select(rowID: failingModel.rows[0].id)
        await stokdWorkWaitUntil { failingModel.detailState?.errorMessage != nil }
        #expect(failingModel.detailState?.errorMessage?.contains("task not found") == true)
        #expect(failingModel.detailState?.detail == nil)

        failingModel.retryDetail()
        await stokdWorkWaitUntilAsync { await failing.recordedHashes().count == 2 }
        #expect(await failing.recordedHashes() == ["8b4b164", "8b4b164"])
    }
}
