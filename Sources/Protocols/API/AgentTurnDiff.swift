import Foundation

public struct AgentTurnDiff: Codable, Sendable, Equatable {
    public struct File: Codable, Sendable, Equatable {
        public enum Attribution: String, Codable, Sendable {
            case verified
            case interleaved
            case limited
        }

        public let path: String
        public let attribution: Attribution
        public let patch: String?
        public let additions: Int
        public let deletions: Int

        public init(path: String, attribution: Attribution, patch: String? = nil, additions: Int = 0, deletions: Int = 0) {
            self.path = path
            self.attribution = attribution
            self.patch = patch
            self.additions = additions
            self.deletions = deletions
        }
    }

    public let files: [File]
    public let truncated: Bool

    public init(files: [File], truncated: Bool) {
        self.files = files
        self.truncated = truncated
    }
}
