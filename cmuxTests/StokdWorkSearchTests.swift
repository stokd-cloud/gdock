import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// VAL-SEARCH-001 plus the operator's tier-2 body search amendment.
@Suite("Stokd Work search")
@MainActor
struct StokdWorkSearchTests {
    private func freshDefaults() -> UserDefaults {
        let name = "stokdWork.search.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private var payload: StokdWorkPayload {
        StokdWorkPayload(
            tasks: [
                StokdWorkFixtures.task(id: "t1", hash: "abc1234", title: "Café menu refresh", status: "pending", updatedAt: "2026-08-20T12:00:00Z"),
                StokdWorkFixtures.task(id: "t2", hash: "def5678", title: "Repair lander", status: "blocked", updatedAt: "2026-08-20T11:00:00Z"),
            ],
            projects: [
                StokdWorkFixtures.project(id: "p1", hash: "38f437b", title: "Work panel", updatedAt: "2026-08-20T10:00:00Z"),
            ],
            todos: [
                StokdWorkFixtures.todo(
                    id: "d1", hash: "c0ffee1", title: "Cross-repo todo", repoSlug: "elsewhere/place", updatedAt: "2026-08-20T09:00:00Z",
                    items: [StokdWorkFixtures.todoItem(id: "i", title: "item", status: "pending")]
                ),
            ],
            limitPerKind: 500,
            error: nil
        )
    }

    private func loadedModel(
        detailLoader: (any StokdWorkDetailLoading)? = nil,
        limit: Int = 500
    ) async -> StokdWorkPanelViewModel {
        let model = StokdWorkPanelViewModel(
            loader: FixtureStokdWorkLoader(payload: StokdWorkPayload(
                tasks: payload.tasks, projects: payload.projects, todos: payload.todos,
                limitPerKind: limit, error: nil
            )),
            detailLoader: detailLoader ?? FixtureStokdWorkDetailLoader(bodies: [:]),
            defaults: freshDefaults(),
            initialLimitPerKind: limit,
            searchDebounce: .zero
        )
        model.refresh(repoSlug: "owner/repo", directory: "/repos/x")
        await stokdWorkWaitUntil { model.state == .populated }
        return model
    }

    @Test func tierOneMatchesTitleHashStatusAndRepoCaseAndDiacriticInsensitively() async {
        let model = await loadedModel()

        model.setSearchQuery("cafe")
        #expect(model.rows.map(\.rawID) == ["t1"])

        model.setSearchQuery("DEF56")
        #expect(model.rows.map(\.rawID) == ["t2"])

        model.setSearchQuery("blocked")
        #expect(model.rows.map(\.rawID) == ["t2"])

        model.setSearchQuery("elsewhere/place")
        #expect(model.rows.map(\.rawID) == ["d1"])
    }

    @Test func countNoMatchesAndEscapeRestoreBehaveHonestly() async {
        let model = await loadedModel()
        #expect(model.searchCountText == nil)

        model.setSearchQuery("panel")
        #expect(model.rows.map(\.rawID) == ["p1"])
        #expect(model.searchCountText == String(
            localized: "stokdWork.search.count", defaultValue: "\(1) of \(4)"
        ))
        #expect(model.isShowingNoMatches == false)

        model.setSearchQuery("zzzz-nothing")
        #expect(model.rows.isEmpty)
        #expect(model.isShowingNoMatches == true)
        #expect(model.state == .populated)
        #expect(model.noMatchesText.contains("zzzz-nothing"))

        model.clearSearch()
        #expect(model.searchQuery.isEmpty)
        #expect(model.rows.count == 4)
        #expect(model.isShowingNoMatches == false)
    }

    @Test func truncatedSetsQualifyTheSearchCountWithAtLeast() async {
        // A limit of 2 makes the task kind come back exactly full.
        let model = await loadedModel(limit: 2)
        #expect(model.truncatedKinds == [.task])

        model.setSearchQuery("repair")
        #expect(model.searchCountText == String(
            localized: "stokdWork.search.countAtLeast", defaultValue: "\(1) of at least \(4)"
        ))
    }

    @Test func tierTwoAppendsBodyOnlyMatchesMarkedAsSuchWithBoundedConcurrency() async {
        let detailLoader = FixtureStokdWorkDetailLoader(
            bodies: [
                "abc1234": .success("Objective: rhubarb pie for the café"),
                "def5678": .success("Objective: lander repair"),
                "38f437b": .success(StokdWorkFixtures.projectGetText),
                "c0ffee1": .success("{\"title\":\"Cross-repo todo\"}"),
            ],
            delayNanoseconds: 5_000_000
        )
        let model = await loadedModel(detailLoader: detailLoader)

        model.setSearchQuery("rhubarb")
        // Tier 1 finds nothing in titles; tier 2 finds the task and the project bodies.
        await stokdWorkWaitUntil { model.rows.count == 2 && !model.isBodySearchRunning }

        #expect(Set(model.rows.map(\.rawID)) == ["t1", "p1"])
        #expect(model.rows.map(\.matchedInBody) == [true, true])
        #expect(model.isShowingNoMatches == false)
        #expect(await detailLoader.recordedMaxInFlight() <= 2)

        // A tier-1 hit is never flagged as a body match even when its body also matches.
        model.setSearchQuery("café")
        await stokdWorkWaitUntil { !model.isBodySearchRunning }
        #expect(model.rows.first?.rawID == "t1")
        #expect(model.rows.first?.matchedInBody == false)

        // Bodies are cached: the second pass must not refetch.
        let fetched = await detailLoader.recordedHashes()
        #expect(Set(fetched).count == fetched.count)
    }

    @Test func changingTheQueryCancelsTheOutstandingBodySearch() async {
        let detailLoader = FixtureStokdWorkDetailLoader(
            bodies: ["abc1234": .success("slow rhubarb"), "def5678": .success("slow rhubarb")],
            delayNanoseconds: 40_000_000
        )
        let model = await loadedModel(detailLoader: detailLoader)

        model.setSearchQuery("rhubarb")
        model.setSearchQuery("lander")
        await stokdWorkWaitUntil { !model.isBodySearchRunning }

        #expect(model.rows.map(\.rawID) == ["t2"])
        #expect(model.rows.first?.matchedInBody == false)
    }
}
