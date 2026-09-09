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
