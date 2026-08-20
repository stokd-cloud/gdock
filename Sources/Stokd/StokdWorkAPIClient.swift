import Foundation

enum StokdWorkAPIErrorMessage {
    static var invalidURL: String {
        String(localized: "stokdWork.error.invalidURL", defaultValue: "The Stokd API URL is invalid")
    }

    static var nonHTTPResponse: String {
        String(
            localized: "stokdWork.error.nonHTTPResponse",
            defaultValue: "The Stokd API returned a non-HTTP response"
        )
    }

    static func httpStatus(_ statusCode: Int) -> String {
        String(
            localized: "stokdWork.error.httpStatus",
            defaultValue: "The Stokd API returned HTTP \(statusCode)"
        )
    }

    static func decoding(_ detail: String) -> String {
        String(
            localized: "stokdWork.error.decoding",
            defaultValue: "Unable to read the Stokd API response: \(detail)"
        )
    }

    static var cancelled: String {
        String(localized: "stokdWork.error.cancelled", defaultValue: "The Stokd API request was cancelled")
    }

    static var timeout: String {
        String(localized: "stokdWork.error.timeout", defaultValue: "The Stokd API request timed out")
    }

    static var connection: String {
        String(localized: "stokdWork.error.connection", defaultValue: "Unable to connect to the Stokd API")
    }

    static func connection(_ detail: String) -> String {
        String(
            localized: "stokdWork.error.connectionDetail",
            defaultValue: "Unable to connect to the Stokd API: \(detail)"
        )
    }
}

actor StokdWorkAPIClient {
    static let defaultBaseURL: URL = {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "localhost"
        components.port = 8167
        return components.url ?? URL(fileURLWithPath: "/")
    }()

    private let baseURL: URL
    private let session: URLSession
    private let timeout: TimeInterval
    private let decoder: JSONDecoder

    init(
        baseURL: URL = StokdWorkAPIClient.defaultBaseURL,
        session: URLSession = URLSession(configuration: .ephemeral),
        timeout: TimeInterval = 5,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
        self.decoder = decoder
    }

    func tasks(_ query: StokdWorkListQuery) async -> StokdPageResult<StokdTask> {
        await fetch(path: "api/tasks", query: query, as: StokdTask.self)
    }

    func projects(_ query: StokdWorkListQuery) async -> StokdPageResult<StokdProject> {
        await fetch(path: "api/projects", query: query, as: StokdProject.self)
    }

    private func fetch<Item: Decodable & Equatable & Sendable>(
        path: String,
        query: StokdWorkListQuery,
        as itemType: Item.Type
    ) async -> StokdPageResult<Item> {
        _ = itemType
        guard let url = requestURL(path: path, query: query) else {
            return failure(query: query, kind: .invalidURL, message: StokdWorkAPIErrorMessage.invalidURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                return failure(
                    query: query,
                    kind: .nonHTTPResponse,
                    message: StokdWorkAPIErrorMessage.nonHTTPResponse
                )
            }
            guard (200..<300).contains(response.statusCode) else {
                return failure(
                    query: query,
                    kind: .httpStatus(response.statusCode),
                    message: StokdWorkAPIErrorMessage.httpStatus(response.statusCode)
                )
            }

            do {
                let items = try decoder.decode([Item].self, from: data)
                let headerTotal = response.value(forHTTPHeaderField: "X-Total-Count")
                    .flatMap(Int.init)
                let total = max(query.offset + items.count, headerTotal ?? 0)
                let candidateNextOffset = query.offset + items.count
                let nextOffset = !items.isEmpty && candidateNextOffset < total
                    ? candidateNextOffset
                    : nil
                return StokdPageResult(
                    page: StokdPage(
                        items: items,
                        total: total,
                        offset: query.offset,
                        limit: query.limit,
                        nextOffset: nextOffset
                    ),
                    error: nil
                )
            } catch {
                return failure(
                    query: query,
                    kind: .decoding,
                    message: StokdWorkAPIErrorMessage.decoding(error.localizedDescription)
                )
            }
        } catch is CancellationError {
            return failure(query: query, kind: .cancelled, message: StokdWorkAPIErrorMessage.cancelled)
        } catch let error as URLError {
            let kind: StokdWorkAPIError.Kind = error.code == .timedOut ? .timeout : .connection
            let message = kind == .timeout
                ? StokdWorkAPIErrorMessage.timeout
                : StokdWorkAPIErrorMessage.connection
            return failure(query: query, kind: kind, message: message)
        } catch {
            return failure(
                query: query,
                kind: .connection,
                message: StokdWorkAPIErrorMessage.connection(error.localizedDescription)
            )
        }
    }

    private func requestURL(path: String, query: StokdWorkListQuery) -> URL? {
        let endpoint = baseURL.appendingPathComponent(path)
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(query.limit)),
            URLQueryItem(name: "offset", value: String(query.offset)),
            URLQueryItem(name: "includeTotal", value: "true"),
            URLQueryItem(name: "sort_by", value: "updated_at"),
            URLQueryItem(name: "sort_order", value: "desc"),
        ]
        if let repoSlug = trimmed(query.repoSlug) {
            queryItems.append(URLQueryItem(name: "repo_slug", value: repoSlug))
        }
        if let status = trimmed(query.status) {
            queryItems.append(URLQueryItem(name: "status", value: status))
        }
        if let search = trimmed(query.search) {
            queryItems.append(URLQueryItem(name: "search", value: search))
        }
        components.queryItems = queryItems
        return components.url
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func failure<Item: Equatable & Sendable>(
        query: StokdWorkListQuery,
        kind: StokdWorkAPIError.Kind,
        message: String
    ) -> StokdPageResult<Item> {
        StokdPageResult(
            page: StokdPage(
                items: [],
                total: query.offset,
                offset: query.offset,
                limit: query.limit,
                nextOffset: nil
            ),
            error: StokdWorkAPIError(kind: kind, message: message)
        )
    }
}
