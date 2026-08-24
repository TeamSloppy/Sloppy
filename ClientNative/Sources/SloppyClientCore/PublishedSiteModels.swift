import Foundation

public enum PublishedSiteVisibility: String, Codable, Sendable, Equatable, CaseIterable {
    case `private`
    case `public`
}

public struct PublishedSiteRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var slug: String
    public var title: String
    public var visibility: PublishedSiteVisibility
    public var ownerId: String
    public var projectId: String?
    public var entryFile: String
    public var revision: Int
    public var path: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        slug: String,
        title: String,
        visibility: PublishedSiteVisibility,
        ownerId: String,
        projectId: String? = nil,
        entryFile: String = "index.html",
        revision: Int = 1,
        path: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.slug = slug
        self.title = title
        self.visibility = visibility
        self.ownerId = ownerId
        self.projectId = projectId
        self.entryFile = entryFile
        self.revision = revision
        self.path = path
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct PublishedSiteUpdateRequest: Codable, Sendable, Equatable {
    public var title: String?
    public var slug: String?
    public var visibility: PublishedSiteVisibility?

    public init(title: String? = nil, slug: String? = nil, visibility: PublishedSiteVisibility? = nil) {
        self.title = title
        self.slug = slug
        self.visibility = visibility
    }
}

public struct PublishedSiteLaunchResponse: Codable, Sendable, Equatable {
    public var url: String
    public var expiresAt: Date?
}

public actor SiteService {
    private struct ListResponse: Decodable { var sites: [PublishedSiteRecord] }
    private struct DetailResponse: Decodable { var site: PublishedSiteRecord }
    private let http: BackendHTTPClient

    public init(http: BackendHTTPClient) {
        self.http = http
    }

    public func list() async throws -> [PublishedSiteRecord] {
        let response: ListResponse = try await http.get("/v1/sites")
        return response.sites
    }

    public func update(id: String, request: PublishedSiteUpdateRequest) async throws -> PublishedSiteRecord {
        let response: DetailResponse = try await http.patch(
            "/v1/sites/\(BackendHTTPClient.encodePathSegment(id))",
            body: request
        )
        return response.site
    }

    public func delete(id: String) async throws {
        try await http.delete("/v1/sites/\(BackendHTTPClient.encodePathSegment(id))")
    }

    public func launch(id: String) async throws -> PublishedSiteLaunchResponse {
        struct Empty: Encodable {}
        return try await http.post(
            "/v1/sites/\(BackendHTTPClient.encodePathSegment(id))/launch",
            body: Empty()
        )
    }
}
