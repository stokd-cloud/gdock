import Foundation

struct StokdTask: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let number: Int?
    let slug: String
    let title: String
    let description: String
    let status: String
    let repoSlug: String?
    let hashShort: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id = "task_id"
        case number = "task_number"
        case slug
        case title
        case description
        case status
        case repoSlug = "repo_slug"
        case hashShort
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct StokdProject: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let number: Int?
    let slug: String
    let title: String
    let description: String
    let status: String
    let repoSlug: String?
    let hashShort: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id = "project_id"
        case number = "project_number"
        case slug
        case title
        case description
        case status
        case repoSlug = "repo_slug"
        case hashShort
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct StokdWorkListQuery: Equatable, Sendable {
    var repoSlug: String?
    var status: String?
    var search: String?
    var limit: Int
    var offset: Int

    init(
        repoSlug: String? = nil,
        status: String? = nil,
        search: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) {
        self.repoSlug = repoSlug
        self.status = status
        self.search = search
        self.limit = max(1, limit)
        self.offset = max(0, offset)
    }
}

struct StokdPage<Item: Equatable & Sendable>: Equatable, Sendable {
    let items: [Item]
    let total: Int
    let offset: Int
    let limit: Int
    let nextOffset: Int?
}

struct StokdPageResult<Item: Equatable & Sendable>: Equatable, Sendable {
    let page: StokdPage<Item>
    let error: StokdWorkAPIError?
}

struct StokdWorkAPIError: Error, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case invalidURL
        case nonHTTPResponse
        case httpStatus(Int)
        case connection
        case timeout
        case decoding
        case cancelled
    }

    let kind: Kind
    let message: String
}
