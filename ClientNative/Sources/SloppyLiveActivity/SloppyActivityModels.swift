import Foundation

#if os(iOS)
import ActivityKit
#endif

public struct SloppyActivityTask: Codable, Hashable, Identifiable, Sendable {
    public enum Status: String, Codable, Hashable, Sendable {
        case inProgress = "in_progress"
        case needsReview = "needs_review"

        public var title: String {
            switch self {
            case .inProgress: "In progress"
            case .needsReview: "Needs review"
            }
        }
    }

    public var id: String
    public var title: String
    public var projectName: String
    public var status: Status

    public init(id: String, title: String, projectName: String, status: Status) {
        self.id = id
        self.title = title
        self.projectName = projectName
        self.status = status
    }
}

public struct SloppyActivityAgentRun: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var sessionTitle: String
    public var agentName: String
    public var status: String

    public init(id: String, sessionTitle: String, agentName: String, status: String) {
        self.id = id
        self.sessionTitle = sessionTitle
        self.agentName = agentName
        self.status = status
    }
}

public struct SloppyActivityApproval: Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var message: String
    public var toolName: String?

    public init(id: String, title: String, message: String, toolName: String? = nil) {
        self.id = id
        self.title = title
        self.message = message
        self.toolName = toolName
    }
}

public struct SloppyActivityError: Codable, Hashable, Sendable {
    public var title: String
    public var message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}

public struct SloppyActivityContentState: Codable, Hashable, Sendable {
    public var agentRuns: [SloppyActivityAgentRun]
    public var tasks: [SloppyActivityTask]
    public var agentRunCount: Int
    public var taskCount: Int
    public var approval: SloppyActivityApproval?
    public var error: SloppyActivityError?
    public var updatedAt: Date

    public init(
        agentRuns: [SloppyActivityAgentRun] = [],
        tasks: [SloppyActivityTask] = [],
        agentRunCount: Int? = nil,
        taskCount: Int? = nil,
        approval: SloppyActivityApproval? = nil,
        error: SloppyActivityError? = nil,
        updatedAt: Date = Date()
    ) {
        self.agentRuns = Array(agentRuns.prefix(3))
        self.tasks = Array(tasks.prefix(3))
        self.agentRunCount = max(agentRunCount ?? agentRuns.count, self.agentRuns.count)
        self.taskCount = max(taskCount ?? tasks.count, self.tasks.count)
        self.approval = approval
        self.error = error
        self.updatedAt = updatedAt
    }

    public var activityCount: Int {
        agentRunCount + taskCount
    }

    public var isEmpty: Bool {
        activityCount == 0 && approval == nil && error == nil
    }
}

#if os(iOS)
public struct SloppyActivityAttributes: ActivityAttributes {
    public typealias ContentState = SloppyActivityContentState

    public var serverURL: String

    public init(serverURL: String) {
        self.serverURL = serverURL
    }
}
#endif
