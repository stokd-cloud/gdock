import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// VAL-TODO-001 / VAL-FILTER-001 / VAL-LIST-001 at the view-model layer.
@Suite("Stokd Work filter bar")
@MainActor
struct StokdWorkFilterBarTests {
    private func freshDefaults() -> UserDefaults {
        let name = "stokdWork.filterBar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private var payload: StokdWorkPayload {
        StokdWorkPayload(
            tasks: [
                StokdWorkFixtures.task(id: "t-open", title: "Open task", status: "pending", updatedAt: "2026-08-20T12:00:00Z", createdAt: "2026-08-01T00:00:00Z"),
                StokdWorkFixtures.task(id: "t-done", title: "Done task", status: "completed", updatedAt: "2026-08-20T13:00:00Z"),
                StokdWorkFixtures.task(id: "t-cancel", title: "Cancelled task", status: "cancelled", updatedAt: "2026-08-20T14:00:00Z"),
                StokdWorkFixtures.task(id: "t-failed", title: "Failed task", status: "failed", updatedAt: "2026-08-20T15:00:00Z"),
            ],
            projects: [
                StokdWorkFixtures.project(id: "p-active", title: "Active project", updatedAt: "2026-08-20T11:00:00Z", createdAt: "2026-08-10T00:00:00Z"),
            ],
            todos: [
                StokdWorkFixtures.todo(
                    id: "d-open", title: "Open todo", status: "in_progress", updatedAt: "2026-08-20T10:00:00Z",
                    items: [
                        StokdWorkFixtures.todoItem(id: "i1", title: "one", status: "completed"),
                        StokdWorkFixtures.todoItem(id: "i2", title: "two", status: "pending"),
                        StokdWorkFixtures.todoItem(id: "i3", title: "three", status: "pending"),
                    ]
                ),
            ],
            limitPerKind: 500,
            error: nil
        )
    }

    private func loadedModel(defaults: UserDefaults? = nil) async -> StokdWorkPanelViewModel {
        let model = StokdWorkPanelViewModel(
            loader: FixtureStokdWorkLoader(payload: payload),
            defaults: defaults ?? freshDefaults()
        )
        model.refresh(repoSlug: "owner/repo", directory: "/repos/x")
        await stokdWorkWaitUntil { model.state == .populated }
        return model
    }

    @Test func todosAreAFirstClassKindWithChecklistCounts() async {
        let model = await loadedModel()

        let todo = model.rows.first { $0.kind == .todo }
        #expect(todo != nil)
        #expect(todo?.title == "Open todo")
        #expect(todo?.checklistCompleted == 1)
        #expect(todo?.checklistTotal == 3)
        #expect(todo?.status == "in_progress")

        model.setFilter(.todos)
        #expect(model.rows.map(\.kind) == [.todo])
        #expect(StokdWorkPanelViewModel.Filter.allCases == [.all, .tasks, .projects, .todos])
    }

    @Test func completedCancelledAndFailedAreHiddenByDefault() async {
        let model = await loadedModel()

        #expect(model.showCompleted == false)
        #expect(model.rows.map(\.rawID) == ["t-open", "p-active", "d-open"])

        model.setShowCompleted(true)
        #expect(model.rows.map(\.rawID) == ["t-failed", "t-cancel", "t-done", "t-open", "p-active", "d-open"])

        model.setShowCompleted(false)
        #expect(model.rows.map(\.rawID) == ["t-open", "p-active", "d-open"])
    }

    @Test func sortDirectionToggleReversesAndCreatedFallsBackToUpdated() async {
        let model = await loadedModel()

        #expect(model.sortField == .updatedAt)
        #expect(model.sortAscending == false)
        #expect(model.rows.map(\.rawID) == ["t-open", "p-active", "d-open"])

        model.toggleSortDirection()
        #expect(model.sortAscending == true)
        #expect(model.rows.map(\.rawID) == ["d-open", "p-active", "t-open"])

        model.toggleSortDirection()
        #expect(model.rows.map(\.rawID) == ["t-open", "p-active", "d-open"])

        // Created: the todo has no created_at and must fall back to updated_at
        // (2026-08-20T10:00) rather than being dropped.
        model.setSortField(.createdAt)
        #expect(model.sortField == .createdAt)
        #expect(model.rows.map(\.rawID) == ["d-open", "p-active", "t-open"])
        #expect(model.rows.count == 3)
    }

    @Test func filterSettingsPersistUnderGdockPrefixedKeys() async {
        let defaults = freshDefaults()
        let model = await loadedModel(defaults: defaults)

        model.setFilter(.projects)
        model.setShowCompleted(true)
        model.setSortField(.createdAt)
        model.toggleSortDirection()

        #expect(StokdWorkPanelSettings.kindFilter(defaults: defaults) == .projects)
        #expect(StokdWorkPanelSettings.showCompleted(defaults: defaults) == true)
        #expect(StokdWorkPanelSettings.sortField(defaults: defaults) == .createdAt)
        #expect(StokdWorkPanelSettings.sortAscending(defaults: defaults) == true)

        let restored = StokdWorkPanelViewModel(loader: FixtureStokdWorkLoader(payload: payload), defaults: defaults)
        #expect(restored.filter == .projects)
        #expect(restored.showCompleted == true)
        #expect(restored.sortField == .createdAt)
        #expect(restored.sortAscending == true)

        for key in StokdWorkPanelSettings.allUserDefaultsKeys {
            #expect(key.hasPrefix("gdock.workPanel."), "\(key) must be gdock-prefixed")
        }
        #expect(StokdWorkPanelSettings.showCompletedCommandId == "palette.toggleSetting.gdock.workPanel.showCompleted")
        #expect(StokdWorkPanelSettings.defaultShowCompleted == false)
    }

    @Test func scrollingPastTheMidpointGrowsThePageAndMergesRows() async {
        let loader = RecordingLimitStokdWorkLoader { limit in
            let tasks = (0..<min(limit, 5)).map { index in
                StokdWorkFixtures.task(id: "t\(index)", title: "T\(index)", updatedAt: "2026-08-20T1\(index):00:00Z")
            }
            return StokdWorkPayload(tasks: tasks, projects: [], todos: [], limitPerKind: limit, error: nil)
        }
        let model = StokdWorkPanelViewModel(loader: loader, defaults: freshDefaults(), initialLimitPerKind: 2)
        model.refresh(repoSlug: "owner/repo", directory: "/repos/x")
        await stokdWorkWaitUntil { model.state == .populated }

        #expect(model.rows.count == 2)
        #expect(model.hasMoreRows)
        #expect(model.isLoadingMore == false)

        // Rows above the midpoint do not page; the midpoint row does, once.
        model.rowDidAppear(id: model.rows[0].id)
        #expect(await loader.recordedLimits() == [2])
        model.rowDidAppear(id: model.rows[1].id)
        #expect(model.isLoadingMore)
        #expect(model.state == .populated, "paging never replaces the list with a spinner")
        model.rowDidAppear(id: model.rows[1].id)
        await stokdWorkWaitUntil { model.rows.count == 4 }

        #expect(await loader.recordedLimits() == [2, 4])
        #expect(model.isLoadingMore == false)
        #expect(Set(model.rows.map(\.rawID)).count == 4)
        #expect(model.hasMoreRows)

        model.rowDidAppear(id: model.rows[3].id)
        await stokdWorkWaitUntil { model.rows.count == 5 }
        #expect(await loader.recordedLimits() == [2, 4, 6])
        #expect(model.hasMoreRows == false)

        // A short page is the end: no further requests.
        model.rowDidAppear(id: model.rows[4].id)
        await Task.yield()
        #expect(await loader.recordedLimits() == [2, 4, 6])
    }

    @Test func changingTheSortRefetchesTheTopPageWithoutBlankingTheList() async {
        let loader = RecordingLimitStokdWorkLoader { limit in
            StokdWorkPayload(
                tasks: [StokdWorkFixtures.task(id: "t0", title: "T0", updatedAt: "2026-08-20T10:00:00Z")],
                projects: [], todos: [], limitPerKind: limit, error: nil
            )
        }
        let model = StokdWorkPanelViewModel(loader: loader, defaults: freshDefaults(), initialLimitPerKind: 2)
        model.refresh(repoSlug: "owner/repo", directory: "/repos/x")
        await stokdWorkWaitUntil { model.state == .populated }
        #expect(await loader.recordedLimits() == [2])

        model.toggleSortDirection()
        #expect(model.state == .populated)
        #expect(model.rows.count == 1)
        await stokdWorkWaitUntilAsync { await loader.recordedLimits().count == 2 }
        #expect(await loader.recordedQueries().last?.sortAscending == true)

        model.setSortField(.createdAt)
        await stokdWorkWaitUntilAsync { await loader.recordedLimits().count == 3 }
        #expect(await loader.recordedQueries().last?.sortField == .createdAt)
        #expect(model.rows.count == 1)
    }
}
