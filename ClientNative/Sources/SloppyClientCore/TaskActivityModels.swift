import Foundation

public struct APITaskActivity: Codable, Sendable, Identifiable {
    public var id: String
    public var taskId: String
    public var field: String
    public var oldValue: String?
    public var newValue: String?
    public var actorId: String
    public var createdAt: Date
}

public struct APITaskLog: Codable, Sendable, Identifiable {
    public var id: String
    public var taskId: String
    public var kind: String
    public var title: String
    public var message: String?
    public var field: String?
    public var oldValue: String?
    public var newValue: String?
    public var actorId: String?
    public var agentId: String?
    public var channelId: String?
    public var workerId: String?
    public var tool: String?
    public var ok: Bool?
    public var durationMs: Int?
    public var createdAt: Date
}

public struct APITaskClarification: Codable, Sendable, Identifiable {
    public struct Option: Codable, Sendable, Identifiable {
        public var id: String
        public var label: String
    }
    public var id: String
    public var status: String
    public var targetType: String
    public var questionText: String
    public var options: [Option]
    public var allowNote: Bool
    public var selectedOptionIds: [String]
    public var note: String?
    public var createdAt: Date
    public var answeredAt: Date?
}

public struct APITaskDiff: Codable, Sendable {
    public var diff: String
    public var branchName: String
    public var baseBranch: String
    public var hasChanges: Bool
}

public struct APITaskReviewComment: Codable, Sendable, Identifiable {
    public var id: String
    public var filePath: String
    public var lineNumber: Int?
    public var side: String?
    public var content: String
    public var author: String
    public var resolved: Bool
    public var createdAt: Date
}

public struct APITaskCommentRequest: Encodable, Sendable {
    public var content: String
    public var authorActorId = "user"
    public var kind = "user_comment"
    public init(content: String) { self.content = content }
}

public struct APITaskClarificationAnswer: Encodable, Sendable {
    public var selectedOptionIds: [String]
    public var note: String
    public init(selectedOptionIds: [String], note: String) {
        self.selectedOptionIds = selectedOptionIds
        self.note = note
    }
}
