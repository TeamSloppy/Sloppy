import Foundation
import Protocols
import PluginSDK

/// A versioned checkpoint of turn-owned counters. The event journal remains the effect authority.
public struct RunStateSnapshot: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 2
    public enum ValidationError: Error, Sendable { case unsupportedVersion(Int), invalidSnapshot }
    public var schemaVersion: Int
    public var runID: String
    public var userTurnID: String
    public var generation: Int
    public var phase: RunState.Phase
    public var requestAttempts: Int
    public var toolRoundsUsed: Int
    public var hitToolRoundLimit: Bool
    public var toolErrors: [ToolInvocationResult]
    public var recoveryCounts: [String: Int]
    public var completion: RunCompletion?
    public var verificationEvidence: [VerificationEvidence]
    public var loopConfig: NativeAgentLoopConfig?
    public var startedAt: Date
    public var savedAt: Date
    public var elapsedSeconds: Double
    public var toolStop: ToolRunStop?
    public var model: String?
    public var requestPurpose: ModelStepPurpose?
    public var requestSettings: RunRequestSettings?
    public var workScopeRevision: Int? = nil

    public init(schemaVersion: Int = 1, runID: String, userTurnID: String, generation: Int = 0,
                phase: RunState.Phase = .preparing, requestAttempts: Int = 0, toolRoundsUsed: Int = 0,
                hitToolRoundLimit: Bool = false, toolErrors: [ToolInvocationResult] = [], recoveryCounts: [String: Int] = [:],
                completion: RunCompletion? = nil, verificationEvidence: [VerificationEvidence] = [], loopConfig: NativeAgentLoopConfig? = nil,
                startedAt: Date = Date(), savedAt: Date = Date(), elapsedSeconds: Double = 0, toolStop: ToolRunStop? = nil,
                model: String? = nil, requestPurpose: ModelStepPurpose? = nil,
                requestSettings: RunRequestSettings? = nil) {
        self.schemaVersion = schemaVersion; self.runID = runID; self.userTurnID = userTurnID
        self.generation = generation; self.phase = phase; self.requestAttempts = requestAttempts
        self.toolRoundsUsed = toolRoundsUsed; self.hitToolRoundLimit = hitToolRoundLimit
        self.toolErrors = toolErrors; self.recoveryCounts = recoveryCounts; self.completion = completion
        self.verificationEvidence = verificationEvidence; self.loopConfig = loopConfig
        self.startedAt = startedAt; self.savedAt = savedAt; self.elapsedSeconds = elapsedSeconds
        self.toolStop = toolStop
        self.model = model
        self.requestPurpose = requestPurpose
        self.requestSettings = requestSettings
    }

    /// Only a provider failure from the current generation may be retried by its owner.
    public var canResumeProviderFailure: Bool {
        guard completion == nil, !hitToolRoundLimit, generation < Int.max,
              phase == .settled || phase == .stopping,
              let stop = toolStop, stop.reason == .modelFailure, stop.generation == generation,
              let failure = stop.modelFailure else { return false }
        return failure.category == .authentication || failure.category == .unavailable ||
            (failure.retryable && (failure.category == .transport || failure.category == .provider))
    }

    public func validate() throws {
        guard (1...Self.currentSchemaVersion).contains(schemaVersion) else { throw ValidationError.unsupportedVersion(schemaVersion) }
        guard (schemaVersion == 2) == (requestSettings != nil) else { throw ValidationError.invalidSnapshot }
        if let requestSettings { _ = try requestSettings.transportRetryDelays() }
        guard requestSettings?.planningPolicyVersion == nil || requestSettings?.planningPolicyVersion == 1,
              [1, 2].contains(requestSettings?.evidencePolicyVersion ?? 1),
              (workScopeRevision ?? 0) >= 0 else { throw ValidationError.invalidSnapshot }
        if let scope = requestSettings?.toolScope {
            guard Set(scope).count == scope.count,
                  scope.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw ValidationError.invalidSnapshot }
        }
        if let job = requestSettings?.proactiveJob {
            guard job.version == 1, job.sourceIDs == Array(Set(job.sourceIDs)).sorted(),
                  job.sourceIDs.allSatisfy({ !$0.isEmpty }), job.sourceDigest.utf8.count == 64, job.configDigest.utf8.count == 64,
                  loopConfig?.completionContract == .session, requestSettings?.toolScope == ["heartbeat.report"],
                  requestSettings?.delegatedAuthority != nil, requestSettings?.derivedSource == nil,
                  completion == nil else { throw ValidationError.invalidSnapshot }
        }
        if loopConfig?.completionContract == .worker || loopConfig?.completionContract == .coordinator || loopConfig?.completionContract == .background {
            guard requestSettings?.toolScope != nil, requestSettings?.delegatedAuthority != nil else {
                throw ValidationError.invalidSnapshot
            }
        }
        if loopConfig?.completionContract == .background {
            guard let source = requestSettings?.derivedSource, source.isValid,
                  source.owner.runId != runID, source.owner.userTurnId != userTurnID,
                  requestSettings?.coordinatorNotification != true else { throw ValidationError.invalidSnapshot }
        } else if requestSettings?.derivedSource != nil { throw ValidationError.invalidSnapshot }
        if requestSettings?.coordinatorNotification == true {
            guard loopConfig?.completionContract == .coordinator, requestSettings?.toolScope == [],
                  requestSettings?.notificationSourceEventID == userTurnID,
                  let fingerprint = requestSettings?.notificationFingerprint,
                  fingerprint.hasPrefix("v2:"), fingerprint.count == 67 else { throw ValidationError.invalidSnapshot }
        }
        guard !runID.isEmpty, !userTurnID.isEmpty, generation >= 0, requestAttempts >= 0, toolRoundsUsed >= 0,
              elapsedSeconds.isFinite, elapsedSeconds >= 0,
              recoveryCounts.allSatisfy({ RecoveryReason(rawValue: $0.key) != nil && $0.value >= 0 }),
              (requestAttempts == 0 && toolRoundsUsed == 0) || loopConfig != nil else { throw ValidationError.invalidSnapshot }
        if let toolStop, toolStop.generation < 0 || toolStop.generation > generation { throw ValidationError.invalidSnapshot }
        if let toolStop {
            guard (toolStop.reason == .modelFailure) == (toolStop.modelFailure != nil),
                  toolStop.modelFailure?.category != .cancelled else { throw ValidationError.invalidSnapshot }
        }
        if let model, model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw ValidationError.invalidSnapshot }
        if let config = loopConfig {
            guard config.engine == .unified, config.maxToolRounds >= 0, config.overBudgetRecoveryBatches >= 0,
                  (128...16_384).contains(config.maxOutputTokens) else { throw ValidationError.invalidSnapshot }
        }
    }
}
