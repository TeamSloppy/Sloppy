import Foundation

public enum InitiativePhase: String, Codable, Sendable, Equatable, CaseIterable {
    case intake
    case framing
    case researching
    case planning
    case executing
    case verifying
    case reviewing
    case needsUserDecision = "needs_user_decision"
    case blocked
    case done
    case abandoned
}

public enum InitiativeExecutionMode: String, Codable, Sendable, Equatable, CaseIterable {
    case singleAgent = "single_agent"
    case delegation
    case swarm
    case councilReview = "council_review"
}

public enum InitiativeExecutionSignal: String, Codable, Sendable, Equatable, CaseIterable {
    case needsIndependentVerification = "needs_independent_verification"
    case needsSpecialist = "needs_specialist"
    case parallelizableStreamsDetected = "parallelizable_streams_detected"
    case tradeoffDecisionRequired = "tradeoff_decision_required"
}

public struct InitiativeRecord: Codable, Sendable, Equatable {
    public var id: String
    public var projectID: String
    public var title: String
    public var goal: String
    public var phase: InitiativePhase
    public var executionMode: InitiativeExecutionMode
    public var successMetrics: [String]
    public var constraints: [String]
    public var resumePoint: String?
    public var blocker: String?
    public var metadata: [String: String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        projectID: String,
        title: String,
        goal: String,
        phase: InitiativePhase,
        executionMode: InitiativeExecutionMode,
        successMetrics: [String] = [],
        constraints: [String] = [],
        resumePoint: String? = nil,
        blocker: String? = nil,
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.goal = goal
        self.phase = phase
        self.executionMode = executionMode
        self.successMetrics = successMetrics
        self.constraints = constraints
        self.resumePoint = resumePoint
        self.blocker = blocker
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct DecisionPacketRecord: Codable, Sendable, Equatable {
    public var id: String
    public var projectID: String
    public var initiativeID: String
    public var summary: String
    public var rationale: String
    public var tradeoffs: [String]
    public var requestedAction: String
    public var resumePoint: String?
    public var status: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        projectID: String,
        initiativeID: String,
        summary: String,
        rationale: String,
        tradeoffs: [String] = [],
        requestedAction: String,
        resumePoint: String? = nil,
        status: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.initiativeID = initiativeID
        self.summary = summary
        self.rationale = rationale
        self.tradeoffs = tradeoffs
        self.requestedAction = requestedAction
        self.resumePoint = resumePoint
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct CreateInitiativeRequest: Codable, Sendable, Equatable {
    public var title: String
    public var goal: String
    public var successMetrics: [String]
    public var constraints: [String]
    public var metadata: [String: String]

    public init(
        title: String,
        goal: String,
        successMetrics: [String] = [],
        constraints: [String] = [],
        metadata: [String: String] = [:]
    ) {
        self.title = title
        self.goal = goal
        self.successMetrics = successMetrics
        self.constraints = constraints
        self.metadata = metadata
    }
}

public struct UpdateInitiativeRequest: Codable, Sendable, Equatable {
    public var title: String?
    public var goal: String?
    public var phase: InitiativePhase?
    public var executionMode: InitiativeExecutionMode?
    public var successMetrics: [String]?
    public var constraints: [String]?
    public var resumePoint: String?
    public var blocker: String?
    public var metadata: [String: String]?

    public init(
        title: String? = nil,
        goal: String? = nil,
        phase: InitiativePhase? = nil,
        executionMode: InitiativeExecutionMode? = nil,
        successMetrics: [String]? = nil,
        constraints: [String]? = nil,
        resumePoint: String? = nil,
        blocker: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.title = title
        self.goal = goal
        self.phase = phase
        self.executionMode = executionMode
        self.successMetrics = successMetrics
        self.constraints = constraints
        self.resumePoint = resumePoint
        self.blocker = blocker
        self.metadata = metadata
    }
}

public struct CreateDecisionPacketRequest: Codable, Sendable, Equatable {
    public var summary: String
    public var rationale: String
    public var tradeoffs: [String]
    public var requestedAction: String
    public var resumePoint: String?

    public init(
        summary: String,
        rationale: String,
        tradeoffs: [String] = [],
        requestedAction: String,
        resumePoint: String? = nil
    ) {
        self.summary = summary
        self.rationale = rationale
        self.tradeoffs = tradeoffs
        self.requestedAction = requestedAction
        self.resumePoint = resumePoint
    }
}

public struct UpdateDecisionPacketRequest: Codable, Sendable, Equatable {
    public var status: String
    public var resumePoint: String?

    public init(status: String, resumePoint: String? = nil) {
        self.status = status
        self.resumePoint = resumePoint
    }
}

public struct InitiativeListResponse: Codable, Sendable, Equatable {
    public var initiatives: [InitiativeRecord]

    public init(initiatives: [InitiativeRecord]) {
        self.initiatives = initiatives
    }
}

public struct InitiativeDetailResponse: Codable, Sendable, Equatable {
    public var initiative: InitiativeRecord

    public init(initiative: InitiativeRecord) {
        self.initiative = initiative
    }
}

public struct DecisionPacketListResponse: Codable, Sendable, Equatable {
    public var decisionPackets: [DecisionPacketRecord]

    public init(decisionPackets: [DecisionPacketRecord]) {
        self.decisionPackets = decisionPackets
    }
}

public struct DecisionPacketDetailResponse: Codable, Sendable, Equatable {
    public var decisionPacket: DecisionPacketRecord

    public init(decisionPacket: DecisionPacketRecord) {
        self.decisionPacket = decisionPacket
    }
}

public struct InitiativeArtifactRecord: Codable, Sendable, Equatable {
    public var path: String

    public init(path: String) {
        self.path = path
    }
}

public struct InitiativeArtifactListResponse: Codable, Sendable, Equatable {
    public var artifacts: [InitiativeArtifactRecord]

    public init(artifacts: [InitiativeArtifactRecord]) {
        self.artifacts = artifacts
    }
}

public struct InitiativeActivityRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var initiativeID: String
    public var kind: String
    public var title: String
    public var message: String?
    public var createdAt: Date

    public init(
        id: String,
        initiativeID: String,
        kind: String,
        title: String,
        message: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.initiativeID = initiativeID
        self.kind = kind
        self.title = title
        self.message = message
        self.createdAt = createdAt
    }
}

public struct InitiativeActivityListResponse: Codable, Sendable, Equatable {
    public var activities: [InitiativeActivityRecord]

    public init(activities: [InitiativeActivityRecord]) {
        self.activities = activities
    }
}
