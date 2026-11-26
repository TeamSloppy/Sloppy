import Foundation

public enum PullRequestEventKind: String, Codable, Sendable, Hashable, CaseIterable {
    case reviewRequested = "review_requested"
    case feedbackReceived = "feedback_received"
}

/// Identifiers use the same namespace as the provider's Pull Requests screen.
public struct PullRequestEvent: Codable, Sendable, Equatable {
    public var id: String
    public var kind: PullRequestEventKind
    public var review: CodeReviewReference
    public var title: String
    public var url: String
    public var actor: String?
    public var revision: String?
    public var comment: CodeReviewComment?

    public init(
        id: String,
        kind: PullRequestEventKind,
        review: CodeReviewReference,
        title: String,
        url: String,
        actor: String? = nil,
        revision: String? = nil,
        comment: CodeReviewComment? = nil
    ) {
        self.id = id
        self.kind = kind
        self.review = review
        self.title = title
        self.url = url
        self.actor = actor
        self.revision = revision
        self.comment = comment
    }
}

public struct PullRequestEventQuery: Codable, Sendable, Equatable {
    public var repositoryPath: String
    public var account: String
    public var reviewIDs: [String]
    public var kinds: [PullRequestEventKind]
    public var since: Date
    public var cursor: JSONValue?

    public init(
        repositoryPath: String,
        account: String,
        reviewIDs: [String],
        kinds: [PullRequestEventKind],
        since: Date,
        cursor: JSONValue? = nil
    ) {
        self.repositoryPath = repositoryPath
        self.account = account
        self.reviewIDs = reviewIDs
        self.kinds = kinds
        self.since = since
        self.cursor = cursor
    }
}

public struct PullRequestEventPage: Codable, Sendable, Equatable {
    public var events: [PullRequestEvent]
    public var nextCursor: JSONValue?
    public var hasMore: Bool

    public init(events: [PullRequestEvent], nextCursor: JSONValue?, hasMore: Bool = false) {
        self.events = events
        self.nextCursor = nextCursor
        self.hasMore = hasMore
    }
}

public struct PullRequestContextRequest: Codable, Sendable, Equatable {
    public var repositoryPath: String
    public var review: CodeReviewReference
    public var revision: String?
    public var maxDiffBytes: Int

    public init(repositoryPath: String, review: CodeReviewReference, revision: String? = nil, maxDiffBytes: Int) {
        self.repositoryPath = repositoryPath
        self.review = review
        self.revision = revision
        self.maxDiffBytes = maxDiffBytes
    }
}

public struct PullRequestCommentReply: Codable, Sendable, Equatable {
    public var repositoryPath: String
    public var review: CodeReviewReference
    public var parentCommentID: String
    public var body: String

    public init(repositoryPath: String, review: CodeReviewReference, parentCommentID: String, body: String) {
        self.repositoryPath = repositoryPath
        self.review = review
        self.parentCommentID = parentCommentID
        self.body = body
    }
}

public struct PullRequestCommentReplyReceipt: Codable, Sendable, Equatable {
    public var id: String
    public var url: String

    public init(id: String, url: String) {
        self.id = id
        self.url = url
    }
}

public struct PullRequestAutomationSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var agentId: String
    public var account: String
    public var kinds: [PullRequestEventKind]
    public var reviewIDs: [String]
    public var intervalSeconds: Int
    public var githubRepository: String?
    public var reviewNewGitHubPullRequests: Bool?

    public init(
        enabled: Bool, agentId: String, account: String,
        kinds: [PullRequestEventKind], reviewIDs: [String] = [], intervalSeconds: Int = 60,
        githubRepository: String? = nil, reviewNewGitHubPullRequests: Bool? = nil
    ) {
        self.enabled = enabled
        self.agentId = agentId
        self.account = account
        self.kinds = kinds
        self.reviewIDs = reviewIDs
        self.intervalSeconds = intervalSeconds
        self.githubRepository = githubRepository
        self.reviewNewGitHubPullRequests = reviewNewGitHubPullRequests
    }
}

public struct PullRequestAutomationStatus: Codable, Sendable, Equatable {
    public var settings: PullRequestAutomationSettings
    public var lastPollAt: Date?
    public var lastError: String?
    public var pendingEvents: Int
    public var latestSession: CodeReviewAutomationSession?

    public init(settings: PullRequestAutomationSettings, lastPollAt: Date?, lastError: String?, pendingEvents: Int, latestSession: CodeReviewAutomationSession?) {
        self.settings = settings
        self.lastPollAt = lastPollAt
        self.lastError = lastError
        self.pendingEvents = pendingEvents
        self.latestSession = latestSession
    }
}

public struct CodeReviewAutomationSession: Codable, Sendable, Equatable {
    public var agentId: String
    public var sessionId: String

    public init(agentId: String, sessionId: String) {
        self.agentId = agentId
        self.sessionId = sessionId
    }
}

public struct PullRequestAutomationReplyRequest: Codable, Sendable, Equatable {
    public var eventId: String
    public var body: String
}
