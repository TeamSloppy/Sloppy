import Foundation
import Protocols

/// Resolved request settings belong to the turn, including absence of an effort override.
public struct RunRequestSettings: Codable, Sendable, Equatable {
    public struct RetryDelay: Codable, Sendable, Equatable {
        public var seconds: Int64
        // JSONValue carries numbers as Double; keep subsecond components lossless.
        public var attoseconds: String

        public init(_ delay: Duration) {
            let components = delay.components
            seconds = components.seconds
            attoseconds = String(components.attoseconds)
        }

        public func duration() throws -> Duration {
            guard seconds >= 0, let value = Int64(attoseconds), String(value) == attoseconds,
                  value >= 0, value < 1_000_000_000_000_000_000 else {
                throw RunStateSnapshot.ValidationError.invalidSnapshot
            }
            return Duration(secondsComponent: seconds, attosecondsComponent: value)
        }
    }

    /// Delegation binds resource context as well as tool names. Current policy is still rechecked.
    public struct ToolAuthority: Codable, Sendable, Equatable {
        public var policy: AgentToolsPolicy
        public var workingDirectory: String?
        public var extraRoots: [String]
        public init(policy: AgentToolsPolicy, workingDirectory: String?, extraRoots: [String]) {
            self.policy = policy; self.workingDirectory = workingDirectory; self.extraRoots = extraRoots
        }
    }

    public var delegatedAuthority: ToolAuthority? = nil
    public var derivedSource: AgentDerivedWorkSource? = nil
    public var retryDelays: [RetryDelay]
    public var reasoningEffort: ReasoningEffort?
    public var planningPolicy: AgentPlanningPolicy? = nil
    public var plannerModel: String? = nil
    public var planningPolicyVersion: Int? = nil
    /// 1 preserves turn-local evidence; 2 requires the current conservative work revision.
    public var evidencePolicyVersion: Int? = nil
    public var coordinatorNotification: Bool? = nil
    public var notificationSourceEventID: String? = nil
    public var notificationFingerprint: String? = nil
    /// Nil inherits ordinary policy. An explicit empty scope authorizes no tools.
    public var toolScope: [String]? = nil
    public var proposalFailureReview: Bool? = nil
    /// Independent read-only background work; no fabricated foreground completion is needed.
    public struct ProactiveJob: Codable, Sendable, Equatable {
        public var version = 1
        public var sourceIDs: [String]
        public var sourceDigest: String
        public var configDigest: String
        public init(sourceIDs: [String], sourceDigest: String, configDigest: String) {
            self.sourceIDs = sourceIDs; self.sourceDigest = sourceDigest; self.configDigest = configDigest
        }
    }
    public var proactiveJob: ProactiveJob? = nil

    public init(retryDelays: [Duration], reasoningEffort: ReasoningEffort?) {
        self.retryDelays = retryDelays.map { RetryDelay(max(.zero, $0)) }
        self.reasoningEffort = reasoningEffort
    }

    public func transportRetryDelays() throws -> [Duration] {
        try retryDelays.map { try $0.duration() }
    }
}
