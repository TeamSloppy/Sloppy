import Foundation

public enum CodeReviewState: String, Codable, Sendable, Equatable, CaseIterable {
    case open
    case closed
    case merged
    case all
}

public enum CodeReviewRole: String, Codable, Sendable, Equatable, CaseIterable {
    case authored
    case reviewRequested = "review_requested"
}

public struct CodeReviewQuery: Codable, Sendable, Equatable {
    public var state: CodeReviewState
    public var roles: [CodeReviewRole]
    public var limit: Int

    public init(
        state: CodeReviewState = .open,
        roles: [CodeReviewRole] = CodeReviewRole.allCases,
        limit: Int = 100
    ) {
        self.state = state
        self.roles = roles
        self.limit = max(1, min(limit, 200))
    }
}

public struct CodeReviewProviderDescriptor: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var capabilities: [String]

    public init(id: String, displayName: String, capabilities: [String] = ["list_pull_requests"]) {
        self.id = id
        self.displayName = displayName
        self.capabilities = capabilities
    }
}

public struct CodeReviewItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var providerId: String
    public var providerName: String
    public var repository: String
    public var number: Int?
    public var title: String
    public var url: String
    public var author: String?
    public var state: CodeReviewState
    public var isDraft: Bool
    public var roles: [CodeReviewRole]
    public var reviewDecision: String?
    public var checksStatus: String?
    public var labels: [String]
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: String,
        providerId: String,
        providerName: String,
        repository: String,
        number: Int? = nil,
        title: String,
        url: String,
        author: String? = nil,
        state: CodeReviewState = .open,
        isDraft: Bool = false,
        roles: [CodeReviewRole] = [],
        reviewDecision: String? = nil,
        checksStatus: String? = nil,
        labels: [String] = [],
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.providerId = providerId
        self.providerName = providerName
        self.repository = repository
        self.number = number
        self.title = title
        self.url = url
        self.author = author
        self.state = state
        self.isDraft = isDraft
        self.roles = roles
        self.reviewDecision = reviewDecision
        self.checksStatus = checksStatus
        self.labels = labels
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct CodeReviewInboxResponse: Codable, Sendable, Equatable {
    public var items: [CodeReviewItem]
    public var providers: [CodeReviewProviderDescriptor]
    public var failures: [String: String]

    public init(
        items: [CodeReviewItem],
        providers: [CodeReviewProviderDescriptor],
        failures: [String: String] = [:]
    ) {
        self.items = items
        self.providers = providers
        self.failures = failures
    }
}
