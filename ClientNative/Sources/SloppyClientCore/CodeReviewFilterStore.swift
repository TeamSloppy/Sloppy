import Foundation

public enum CodeReviewInboxRoleFilter: String, Codable, Sendable, Equatable, CaseIterable, Identifiable {
    case all
    case reviewRequested
    case authored

    public var id: Self { self }

    public var title: String {
        switch self {
        case .all: "All"
        case .reviewRequested: "Reviewing"
        case .authored: "Authored"
        }
    }

    public var roles: [CodeReviewRole] {
        switch self {
        case .all: CodeReviewRole.allCases
        case .reviewRequested: [.reviewRequested]
        case .authored: [.authored]
        }
    }
}

public struct CodeReviewInboxFilters: Codable, Sendable, Equatable {
    public var state: CodeReviewState
    public var role: CodeReviewInboxRoleFilter
    public var providerID: String?

    public init(
        state: CodeReviewState = .open,
        role: CodeReviewInboxRoleFilter = .all,
        providerID: String? = nil
    ) {
        self.state = state
        self.role = role
        self.providerID = providerID
    }
}

public final class CodeReviewFilterStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load(endpoint: SloppyInstanceEndpoint) -> CodeReviewInboxFilters {
        guard let data = defaults.data(forKey: key(endpoint)),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.version == 1 else {
            return CodeReviewInboxFilters()
        }
        return snapshot.filters
    }

    public func save(_ filters: CodeReviewInboxFilters, endpoint: SloppyInstanceEndpoint) {
        let storageKey = key(endpoint)
        guard filters != CodeReviewInboxFilters() else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        guard let data = try? JSONEncoder().encode(Snapshot(filters: filters)) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func key(_ endpoint: SloppyInstanceEndpoint) -> String {
        let scope = Data(endpoint.cacheNamespace.utf8).base64EncodedString()
        return "client_code_review_filters_v1." + scope
    }

    private struct Snapshot: Codable {
        var version = 1
        var filters: CodeReviewInboxFilters
    }
}
