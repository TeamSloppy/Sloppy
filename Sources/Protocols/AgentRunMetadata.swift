import Foundation

public enum AgentToolExecutionPhase: String, Codable, Sendable, Equatable {
    case requested, started, settled
}

/// Hidden upstream generations still own durable usage and cannot masquerade as UI delivery.
public enum AgentAuxiliaryRequestPurpose: String, Codable, Sendable, Equatable {
    case planning
    case compaction
    case reportReview = "report_review"
}

/// A complete observation, stored before its compact model-visible reference is committed.
public struct AgentToolOutputArtifact: Codable, Sendable, Equatable {
    public var schemaVersion: Int = 1
    public var format = "tool_invocation_result_v1"
    public var agentId: String
    public var sessionId: String
    public var callEventId: String
    public var attachment: AgentAttachment
    public var sha256: String
    public var downloadPath: String {
        "/v1/agents/\(agentId)/sessions/\(sessionId)/attachments/\(attachment.id)"
    }
    public init(agentId: String, sessionId: String, callEventId: String, attachment: AgentAttachment, sha256: String) {
        self.agentId = agentId; self.sessionId = sessionId; self.callEventId = callEventId
        self.attachment = attachment; self.sha256 = sha256
    }
}

/// Optional journal envelope. Session creation metadata remains in AgentSessionEvent.metadata.
/// Readers ship before writers; these identifiers never authorize an effect by themselves.
public struct AgentRunMetadata: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 2
    public var schemaVersion: Int
    public var runId: String
    public var userTurnId: String
    public var stepId: String?
    public var attemptId: String?
    public var generation: Int
    public var sourceOrder: Int?
    public var providerCallId: String?
    public var callEventId: String?
    public var executionPhase: AgentToolExecutionPhase?
    public var engineVersion: Int
    public var completionPolicyVersion: Int
    public var checkpoint: SessionProjectionCheckpoint?
    /// Opaque, versioned SDK response envelope. Protocols does not depend on PluginSDK.
    public var modelResponse: JSONValue?
    public var runState: JSONValue?
    public var instruction: AgentRunInstruction?
    /// Initial context committed atomically with the first accepted input and run snapshot.
    public var admissionInstructions: [AgentRunInstruction]?
    /// UI-only delivery; the canonical response is stored separately.
    public var presentationOnly: Bool?
    /// Product-policy authority; scalar tool observations never populate this envelope.
    public var completionCandidate: JSONValue?
    public var observationOnly: Bool?
    public var inputMessageId: String?
    /// Versioned digest of the original client submission, excluding its identity key.
    public var requestFingerprint: String?
    /// Verified product observations; scalar or late tool payloads cannot populate this slot.
    public var verificationEvidence: [JSONValue]?
    /// Canonical provider-reported fallback accounting, committed with its response.
    public var usageRequest: UsageRequestRecord? = nil
    public var auxiliaryPurpose: AgentAuxiliaryRequestPurpose? = nil
    public var derivedSource: AgentDerivedWorkSource? = nil
    public var toolOutputArtifact: AgentToolOutputArtifact? = nil
    public var workScopeRevision: Int? = nil

    public init(
        schemaVersion: Int = 1,
        runId: String,
        userTurnId: String,
        stepId: String? = nil,
        attemptId: String? = nil,
        generation: Int = 0,
        sourceOrder: Int? = nil,
        providerCallId: String? = nil,
        callEventId: String? = nil,
        executionPhase: AgentToolExecutionPhase? = nil,
        engineVersion: Int = 1,
        completionPolicyVersion: Int = 1,
        checkpoint: SessionProjectionCheckpoint? = nil,
        modelResponse: JSONValue? = nil,
        runState: JSONValue? = nil,
        instruction: AgentRunInstruction? = nil,
        admissionInstructions: [AgentRunInstruction]? = nil,
        presentationOnly: Bool? = nil,
        completionCandidate: JSONValue? = nil,
        observationOnly: Bool? = nil,
        inputMessageId: String? = nil,
        requestFingerprint: String? = nil,
        verificationEvidence: [JSONValue]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.runId = runId
        self.userTurnId = userTurnId
        self.stepId = stepId
        self.attemptId = attemptId
        self.generation = generation
        self.sourceOrder = sourceOrder
        self.providerCallId = providerCallId
        self.callEventId = callEventId
        self.executionPhase = executionPhase
        self.engineVersion = engineVersion
        self.completionPolicyVersion = completionPolicyVersion
        self.checkpoint = checkpoint
        self.modelResponse = modelResponse
        self.runState = runState
        self.instruction = instruction
        self.admissionInstructions = admissionInstructions
        self.presentationOnly = presentationOnly
        self.completionCandidate = completionCandidate
        self.observationOnly = observationOnly
        self.inputMessageId = inputMessageId
        self.requestFingerprint = requestFingerprint
        self.verificationEvidence = verificationEvidence
    }
}
