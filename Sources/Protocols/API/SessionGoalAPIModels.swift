import Foundation

public enum AgentSessionGoalStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case active
    case paused
    case waitingInput = "waiting_input"
    case completed
    case blocked
    case exhausted
    case cleared

    public var isTerminal: Bool {
        switch self {
        case .completed, .blocked, .exhausted, .cleared:
            return true
        case .active, .paused, .waitingInput:
            return false
        }
    }
}

public struct AgentSessionGoalEvaluation: Codable, Sendable, Equatable {
    public var status: AgentSessionGoalStatus
    public var reason: String
    public var shouldContinue: Bool
    public var continuationPrompt: String?

    public init(
        status: AgentSessionGoalStatus,
        reason: String,
        shouldContinue: Bool,
        continuationPrompt: String? = nil
    ) {
        self.status = status
        self.reason = reason
        self.shouldContinue = shouldContinue
        self.continuationPrompt = continuationPrompt
    }
}

public struct AgentSessionGoalRecord: Codable, Sendable, Equatable {
    public var id: String
    public var agentId: String
    public var sessionId: String
    public var objective: String
    public var status: AgentSessionGoalStatus
    public var attemptCount: Int
    public var maxAttempts: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var lastEvaluation: AgentSessionGoalEvaluation?

    public init(
        id: String = UUID().uuidString,
        agentId: String,
        sessionId: String,
        objective: String,
        status: AgentSessionGoalStatus = .active,
        attemptCount: Int = 0,
        maxAttempts: Int = 8,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastEvaluation: AgentSessionGoalEvaluation? = nil
    ) {
        self.id = id
        self.agentId = agentId
        self.sessionId = sessionId
        self.objective = objective
        self.status = status
        self.attemptCount = attemptCount
        self.maxAttempts = maxAttempts
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastEvaluation = lastEvaluation
    }
}

public struct AgentSessionGoalStartRequest: Codable, Sendable, Equatable {
    public var objective: String
    public var maxAttempts: Int?
    public var userId: String
    public var reasoningEffort: ReasoningEffort?
    public var mode: AgentChatMode?

    public init(
        objective: String,
        maxAttempts: Int? = nil,
        userId: String = "goal",
        reasoningEffort: ReasoningEffort? = nil,
        mode: AgentChatMode? = nil
    ) {
        self.objective = objective
        self.maxAttempts = maxAttempts
        self.userId = userId
        self.reasoningEffort = reasoningEffort
        self.mode = mode
    }
}

public struct AgentSessionGoalStatusRequest: Codable, Sendable, Equatable {
    public init() {}
}

public struct AgentSessionGoalPauseRequest: Codable, Sendable, Equatable {
    public init() {}
}

public struct AgentSessionGoalResumeRequest: Codable, Sendable, Equatable {
    public init() {}
}

public struct AgentSessionGoalClearRequest: Codable, Sendable, Equatable {
    public init() {}
}

public struct AgentSessionGoalResponse: Codable, Sendable, Equatable {
    public var goal: AgentSessionGoalRecord?

    public init(goal: AgentSessionGoalRecord?) {
        self.goal = goal
    }
}

public typealias AgentSessionGoalStartResponse = AgentSessionGoalResponse

public typealias AgentSessionGoalStatusResponse = AgentSessionGoalResponse

public typealias AgentSessionGoalPauseResponse = AgentSessionGoalResponse

public typealias AgentSessionGoalResumeResponse = AgentSessionGoalResponse

public typealias AgentSessionGoalClearResponse = AgentSessionGoalResponse
