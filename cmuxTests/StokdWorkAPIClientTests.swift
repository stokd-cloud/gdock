import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("Stokd Work API client")
struct StokdWorkAPIClientTests {
    @Test func taskAndProjectArraysUseHeaderBackedOffsetPagination() async throws {
        let client = makeClient(baseURL: try #require(URL(string: "http://fixture.local:9000/root")))

        let tasks = await client.tasks(.init(repoSlug: "owner/repo", limit: 2, offset: 0))
        #expect(tasks.error == nil)
        #expect(tasks.page.items.map(\.id) == ["task-1", "task-2"])
        #expect(tasks.page.total == 3)
        #expect(tasks.page.offset == 0)
        #expect(tasks.page.limit == 2)
        #expect(tasks.page.nextOffset == 2)

        let projects = await client.projects(.init(repoSlug: "owner/repo", limit: 1, offset: 0))
        #expect(projects.error == nil)
        #expect(projects.page.items.map(\.id) == ["project-1"])
        #expect(projects.page.total == 1)
        #expect(projects.page.nextOffset == nil)
    }

    @Test func emptyArrayIsADistinctSuccessfulPage() async throws {
        let client = makeClient(baseURL: try #require(URL(string: "http://empty.local")))
        let result = await client.tasks(.init(limit: 25, offset: 50))

        #expect(result.error == nil)
        #expect(result.page.items.isEmpty)
        #expect(result.page.total == 50)
        #expect(result.page.nextOffset == nil)
    }

    @Test func nonSuccessStatusReturnsEmptyStructuredError() async throws {
        let client = makeClient(baseURL: try #require(URL(string: "http://http-error.local")))
        let result = await client.projects(.init())

        #expect(result.page.items.isEmpty)
        #expect(result.error?.kind == .httpStatus(500))
        #expect(result.error?.message.isEmpty == false)
    }

    @Test func malformedJSONReturnsEmptyDecodingError() async throws {
        let client = makeClient(baseURL: try #require(URL(string: "http://decode-error.local")))
        let result = await client.tasks(.init())

        #expect(result.page.items.isEmpty)
        #expect(result.error?.kind == .decoding)
    }

    @Test func refusedConnectionAndTimeoutAreNormalized() async throws {
        let refused = makeClient(baseURL: try #require(URL(string: "http://refused.local")))
        let refusedResult = await refused.tasks(.init())
        #expect(refusedResult.page.items.isEmpty)
        #expect(refusedResult.error?.kind == .connection)

        let timedOut = makeClient(baseURL: try #require(URL(string: "http://timeout.local")))
        let timeoutResult = await timedOut.projects(.init())
        #expect(timeoutResult.page.items.isEmpty)
        #expect(timeoutResult.error?.kind == .timeout)
    }

    @Test func baseURLDefaultsToTheLocalStokdService() {
        #expect(StokdWorkAPIClient.defaultBaseURL.absoluteString == "http://localhost:8167")
    }

    private func makeClient(baseURL: URL) -> StokdWorkAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StokdWorkFixtureURLProtocol.self]
        return StokdWorkAPIClient(
            baseURL: baseURL,
            session: URLSession(configuration: configuration),
            timeout: 0.1
        )
    }
}

private final class StokdWorkFixtureURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        switch url.host {
        case "refused.local":
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        case "timeout.local":
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        default:
            break
        }

        let statusCode = url.host == "http-error.local" ? 500 : 200
        let body: Data
        let total: String

        if url.host == "decode-error.local" {
            body = Data("not-json".utf8)
            total = "0"
        } else if url.host == "empty.local" {
            body = Data("[]".utf8)
            total = "50"
        } else if url.path.hasSuffix("/api/tasks") {
            guard validQuery(url: url, limit: "2", offset: "0") else {
                respond(statusCode: 422, body: Data("[]".utf8), total: "0")
                return
            }
            body = Data(Self.tasksJSON.utf8)
            total = "3"
        } else if url.path.hasSuffix("/api/projects") {
            guard validQuery(url: url, limit: "1", offset: "0") else {
                respond(statusCode: 422, body: Data("[]".utf8), total: "0")
                return
            }
            body = Data(Self.projectsJSON.utf8)
            total = "1"
        } else {
            respond(statusCode: 404, body: Data("[]".utf8), total: "0")
            return
        }

        respond(statusCode: statusCode, body: body, total: total)
    }

    override func stopLoading() {}

    private func validQuery(url: URL, limit: String, offset: String) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map {
            ($0.name, $0.value ?? "")
        })
        return values["repo_slug"] == "owner/repo"
            && values["limit"] == limit
            && values["offset"] == offset
            && values["includeTotal"] == "true"
    }

    private func respond(statusCode: Int, body: Data, total: String) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["X-Total-Count": total]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static let tasksJSON = #"""
    [
      {"task_id":"task-1","slug":"first","title":"First task","description":"One","status":"pending","repo_slug":"owner/repo","hashShort":"aaa1111","created_at":"2026-08-20T10:00:00Z","updated_at":"2026-08-20T11:00:00Z"},
      {"task_id":"task-2","slug":"second","title":"Second task","description":"Two","status":"in_progress","repo_slug":"owner/repo","hashShort":"bbb2222","created_at":"2026-08-20T09:00:00Z","updated_at":"2026-08-20T12:00:00Z"}
    ]
    """#

    private static let projectsJSON = #"""
    [
      {"project_id":"project-1","slug":"first-project","title":"First project","description":"Project","status":"active","repo_slug":"owner/repo","hashShort":"ccc3333","created_at":"2026-08-19T10:00:00Z","updated_at":"2026-08-20T10:00:00Z"}
    ]
    """#
}
