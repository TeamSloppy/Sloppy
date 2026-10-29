import Foundation

public enum CodeReviewState: String, Codable, Sendable, Equatable, CaseIterable, Identifiable {
    case open
    case closed
    case merged
    case all

    public var id: Self { self }

    public var title: String {
        switch self {
        case .open: "Open"
        case .closed: "Closed"
        case .merged: "Merged"
        case .all: "All"
        }
    }
}

public enum CodeReviewRole: String, Codable, Sendable, Equatable, CaseIterable {
    case authored
    case reviewRequested = "review_requested"
}

public struct CodeReviewProviderDescriptor: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var capabilities: [String]

    public init(id: String, displayName: String, capabilities: [String] = []) {
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
    public var sourceBranch: String? = nil
    public var targetBranch: String? = nil

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
        updatedAt: Date? = nil,
        sourceBranch: String? = nil,
        targetBranch: String? = nil
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
        self.sourceBranch = sourceBranch
        self.targetBranch = targetBranch
    }
}

public struct CodeReviewComment: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var author: String?
    public var body: String
    public var filePath: String?
    public var line: Int?
    public var originalLine: Int?
    public var side: String?
    public var diffHunk: String?
    public var inReplyToId: String?
    public var isResolved: Bool?
    public var isOutdated: Bool?
    public var status: String?
    public var createdAt: Date?
    public var updatedAt: Date?
}

public struct CodeReviewDetail: Codable, Sendable, Equatable {
    public var item: CodeReviewItem
    public var description: String?
    public var sourceBranch: String?
    public var targetBranch: String?
    public var reviewers: [String]
    public var comments: [CodeReviewComment]
    public var commentsError: String?
    public var diff: String
    public var diffTruncated: Bool
    public var diffError: String?
}

public struct CodeReviewCredentialStatus: Codable, Sendable, Equatable {
    public var providerId: String
    public var isConfigured: Bool
}

public struct CodeReviewCredentialRequest: Codable, Sendable, Equatable {
    public var token: String

    public init(token: String) {
        self.token = token
    }
}

public struct CodeReviewCommentReplyRequest: Codable, Sendable, Equatable {
    public var parentCommentID: String
    public var body: String

    public init(parentCommentID: String, body: String) {
        self.parentCommentID = parentCommentID
        self.body = body
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
