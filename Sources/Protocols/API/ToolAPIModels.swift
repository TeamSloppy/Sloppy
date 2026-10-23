import Foundation

public enum AgentPolicyDefault: String, Codable, Sendable {
    case allow
    case deny
}

public enum AgentSandboxMode: String, Codable, Sendable, Equatable {
    case workspaceWrite = "workspace_write"
    case fullAccess = "full_access"
}

public struct AgentSandboxSettings: Codable, Sendable, Equatable {
    public var mode: AgentSandboxMode

    public init(mode: AgentSandboxMode = .workspaceWrite) {
        self.mode = mode
    }
}

public struct AgentToolsGuardrails: Codable, Sendable, Equatable {
    public static let defaultExecTimeoutMs = 15_000
    public static let legacyDefaultMaxExecTimeoutMs = 120_000
    public static let defaultMaxExecTimeoutMs = 6 * 60 * 60 * 1_000

    public var maxReadBytes: Int
    public var maxWriteBytes: Int
    public var execTimeoutMs: Int
    public var maxExecTimeoutMs: Int
    public var maxExecOutputBytes: Int
    public var maxProcessesPerSession: Int
    public var maxToolCallsPerMinute: Int
    public var toolLoopWindowSeconds: Int
    public var maxConsecutiveIdenticalToolCalls: Int
    public var maxIdenticalToolCallsPerWindow: Int
    public var maxRepeatedNonRetryableFailures: Int
    public var deniedCommandPrefixes: [String]
    public var allowedWriteRoots: [String]
    public var allowedExecRoots: [String]
    public var webTimeoutMs: Int
    public var webMaxBytes: Int
    public var webBlockPrivateNetworks: Bool

    public init(
        maxReadBytes: Int = 512 * 1024,
        maxWriteBytes: Int = 512 * 1024,
        execTimeoutMs: Int = Self.defaultExecTimeoutMs,
        maxExecTimeoutMs: Int = Self.defaultMaxExecTimeoutMs,
        maxExecOutputBytes: Int = 256 * 1024,
        maxProcessesPerSession: Int = 2,
        maxToolCallsPerMinute: Int = 60,
        toolLoopWindowSeconds: Int = 60,
        maxConsecutiveIdenticalToolCalls: Int = 3,
        maxIdenticalToolCallsPerWindow: Int = 6,
        maxRepeatedNonRetryableFailures: Int = 2,
        deniedCommandPrefixes: [String] = ["rm", "shutdown", "reboot", "mkfs", "dd", "killall", "launchctl"],
        allowedWriteRoots: [String] = [],
        allowedExecRoots: [String] = [],
        webTimeoutMs: Int = 10_000,
        webMaxBytes: Int = 512 * 1024,
        webBlockPrivateNetworks: Bool = true
    ) {
        self.maxReadBytes = maxReadBytes
        self.maxWriteBytes = maxWriteBytes
        self.execTimeoutMs = execTimeoutMs
        self.maxExecTimeoutMs = maxExecTimeoutMs
        self.maxExecOutputBytes = maxExecOutputBytes
        self.maxProcessesPerSession = maxProcessesPerSession
        self.maxToolCallsPerMinute = maxToolCallsPerMinute
        self.toolLoopWindowSeconds = toolLoopWindowSeconds
        self.maxConsecutiveIdenticalToolCalls = maxConsecutiveIdenticalToolCalls
        self.maxIdenticalToolCallsPerWindow = maxIdenticalToolCallsPerWindow
        self.maxRepeatedNonRetryableFailures = maxRepeatedNonRetryableFailures
        self.deniedCommandPrefixes = deniedCommandPrefixes
        self.allowedWriteRoots = allowedWriteRoots
        self.allowedExecRoots = allowedExecRoots
        self.webTimeoutMs = webTimeoutMs
        self.webMaxBytes = webMaxBytes
        self.webBlockPrivateNetworks = webBlockPrivateNetworks
    }

    private enum CodingKeys: String, CodingKey {
        case maxReadBytes
        case maxWriteBytes
        case execTimeoutMs
        case maxExecTimeoutMs
        case maxExecOutputBytes
        case maxProcessesPerSession
        case maxToolCallsPerMinute
        case toolLoopWindowSeconds
        case maxConsecutiveIdenticalToolCalls
        case maxIdenticalToolCallsPerWindow
        case maxRepeatedNonRetryableFailures
        case deniedCommandPrefixes
        case allowedWriteRoots
        case allowedExecRoots
        case webTimeoutMs
        case webMaxBytes
        case webBlockPrivateNetworks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AgentToolsGuardrails()
        self.init(
            maxReadBytes: try container.decodeIfPresent(Int.self, forKey: .maxReadBytes) ?? defaults.maxReadBytes,
            maxWriteBytes: try container.decodeIfPresent(Int.self, forKey: .maxWriteBytes) ?? defaults.maxWriteBytes,
            execTimeoutMs: try container.decodeIfPresent(Int.self, forKey: .execTimeoutMs) ?? defaults.execTimeoutMs,
            maxExecTimeoutMs: try container.decodeIfPresent(Int.self, forKey: .maxExecTimeoutMs) ?? defaults.maxExecTimeoutMs,
            maxExecOutputBytes: try container.decodeIfPresent(Int.self, forKey: .maxExecOutputBytes) ?? defaults.maxExecOutputBytes,
            maxProcessesPerSession: try container.decodeIfPresent(Int.self, forKey: .maxProcessesPerSession) ?? defaults.maxProcessesPerSession,
            maxToolCallsPerMinute: try container.decodeIfPresent(Int.self, forKey: .maxToolCallsPerMinute) ?? defaults.maxToolCallsPerMinute,
            toolLoopWindowSeconds: try container.decodeIfPresent(Int.self, forKey: .toolLoopWindowSeconds) ?? defaults.toolLoopWindowSeconds,
            maxConsecutiveIdenticalToolCalls: try container.decodeIfPresent(Int.self, forKey: .maxConsecutiveIdenticalToolCalls) ?? defaults.maxConsecutiveIdenticalToolCalls,
            maxIdenticalToolCallsPerWindow: try container.decodeIfPresent(Int.self, forKey: .maxIdenticalToolCallsPerWindow) ?? defaults.maxIdenticalToolCallsPerWindow,
            maxRepeatedNonRetryableFailures: try container.decodeIfPresent(Int.self, forKey: .maxRepeatedNonRetryableFailures) ?? defaults.maxRepeatedNonRetryableFailures,
            deniedCommandPrefixes: try container.decodeIfPresent([String].self, forKey: .deniedCommandPrefixes) ?? defaults.deniedCommandPrefixes,
            allowedWriteRoots: try container.decodeIfPresent([String].self, forKey: .allowedWriteRoots) ?? defaults.allowedWriteRoots,
            allowedExecRoots: try container.decodeIfPresent([String].self, forKey: .allowedExecRoots) ?? defaults.allowedExecRoots,
            webTimeoutMs: try container.decodeIfPresent(Int.self, forKey: .webTimeoutMs) ?? defaults.webTimeoutMs,
            webMaxBytes: try container.decodeIfPresent(Int.self, forKey: .webMaxBytes) ?? defaults.webMaxBytes,
            webBlockPrivateNetworks: try container.decodeIfPresent(Bool.self, forKey: .webBlockPrivateNetworks) ?? defaults.webBlockPrivateNetworks
        )
    }
}

public struct AgentToolsPolicy: Codable, Sendable, Equatable {
    public var version: Int
    public var defaultPolicy: AgentPolicyDefault
    public var tools: [String: Bool]
    public var approval: AgentToolApprovalSettings
    public var sandbox: AgentSandboxSettings
    public var preToolsHook: AgentToolPreHookOverride
    /// Permanent approvals, applied only to the matching tool.
    public var approvalGrants: [ToolApprovalGrant]
    public var guardrails: AgentToolsGuardrails

    public init(
        version: Int = 1,
        defaultPolicy: AgentPolicyDefault = .allow,
        tools: [String: Bool] = [:],
        approval: AgentToolApprovalSettings = .init(),
        sandbox: AgentSandboxSettings = .init(),
        preToolsHook: AgentToolPreHookOverride = .init(),
        approvalGrants: [ToolApprovalGrant] = [],
        guardrails: AgentToolsGuardrails = .init()
    ) {
        self.version = version
        self.defaultPolicy = defaultPolicy
        self.tools = tools
        self.approval = approval
        self.sandbox = sandbox
        self.preToolsHook = preToolsHook
        self.approvalGrants = approvalGrants
        self.guardrails = guardrails
    }

    enum CodingKeys: String, CodingKey {
        case version
        case defaultPolicy
        case tools
        case approval
        case sandbox
        case preToolsHook
        case approvalGrants
        case guardrails
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.defaultPolicy = try container.decodeIfPresent(AgentPolicyDefault.self, forKey: .defaultPolicy) ?? .allow
        self.tools = try container.decodeIfPresent([String: Bool].self, forKey: .tools) ?? [:]
        self.approval = try container.decodeIfPresent(AgentToolApprovalSettings.self, forKey: .approval) ?? .init()
        self.sandbox = try container.decodeIfPresent(AgentSandboxSettings.self, forKey: .sandbox) ?? .init()
        self.preToolsHook = try container.decodeIfPresent(AgentToolPreHookOverride.self, forKey: .preToolsHook) ?? .init()
        self.approvalGrants = try container.decodeIfPresent([ToolApprovalGrant].self, forKey: .approvalGrants) ?? []
        self.guardrails = try container.decodeIfPresent(AgentToolsGuardrails.self, forKey: .guardrails) ?? .init()
    }
}

public enum AgentToolApprovalPolicy: String, Codable, Sendable, Equatable {
    case never
    case onRequest = "on_request"
    case approveForMe = "approve_for_me"
}

/// How a session that already ingested untrusted tool output (web pages, browser, MCP) treats risky tool calls.
public enum AgentUntrustedContextGuard: String, Codable, Sendable, Equatable {
    /// Risky tool calls need a fresh human approval on every invocation; session/always grants do not apply.
    case requireApproval = "require_approval"
    case off
}

public struct AgentToolApprovalSettings: Codable, Sendable, Equatable {
    public var policy: AgentToolApprovalPolicy
    public var reviewerAgentId: String?
    public var untrustedContextGuard: AgentUntrustedContextGuard

    public var enabled: Bool {
        get { policy != .never }
        set { policy = newValue ? .onRequest : .never }
    }

    public init(
        policy: AgentToolApprovalPolicy = .never,
        reviewerAgentId: String? = nil,
        untrustedContextGuard: AgentUntrustedContextGuard = .requireApproval
    ) {
        self.policy = policy
        self.reviewerAgentId = reviewerAgentId
        self.untrustedContextGuard = untrustedContextGuard
    }

    public init(enabled: Bool) {
        self.policy = enabled ? .onRequest : .never
        self.reviewerAgentId = nil
        self.untrustedContextGuard = .requireApproval
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case policy
        case reviewerAgentId
        case untrustedContextGuard
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let policy = try container.decodeIfPresent(AgentToolApprovalPolicy.self, forKey: .policy) {
            self.policy = policy
        } else {
            let enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
            self.policy = enabled ? .onRequest : .never
        }
        self.reviewerAgentId = try container.decodeIfPresent(String.self, forKey: .reviewerAgentId)
        self.untrustedContextGuard = try container.decodeIfPresent(AgentUntrustedContextGuard.self, forKey: .untrustedContextGuard) ?? .requireApproval
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(policy, forKey: .policy)
        try container.encode(enabled, forKey: .enabled)
        try container.encodeIfPresent(reviewerAgentId, forKey: .reviewerAgentId)
        try container.encode(untrustedContextGuard, forKey: .untrustedContextGuard)
    }
}

public enum ToolHookFailurePolicy: String, Codable, Sendable, Equatable {
    case allow
    case block
}

public struct AgentToolPreHookOverride: Codable, Sendable, Equatable {
    public var enabled: Bool?
    public var command: String?
    public var arguments: [String]?
    public var timeoutMs: Int?
    public var maxOutputBytes: Int?
    public var failurePolicy: ToolHookFailurePolicy?

    public init(
        enabled: Bool? = nil,
        command: String? = nil,
        arguments: [String]? = nil,
        timeoutMs: Int? = nil,
        maxOutputBytes: Int? = nil,
        failurePolicy: ToolHookFailurePolicy? = nil
    ) {
        self.enabled = enabled
        self.command = command
        self.arguments = arguments
        self.timeoutMs = timeoutMs
        self.maxOutputBytes = maxOutputBytes
        self.failurePolicy = failurePolicy
    }
}

public struct AgentToolsUpdateRequest: Codable, Sendable {
    public var version: Int?
    public var defaultPolicy: AgentPolicyDefault
    public var tools: [String: Bool]
    public var approval: AgentToolApprovalSettings
    public var sandbox: AgentSandboxSettings
    public var preToolsHook: AgentToolPreHookOverride
    /// Omit to preserve saved approvals; pass an empty array to revoke them.
    public var approvalGrants: [ToolApprovalGrant]?
    public var guardrails: AgentToolsGuardrails

    public init(
        version: Int? = nil,
        defaultPolicy: AgentPolicyDefault = .allow,
        tools: [String: Bool] = [:],
        approval: AgentToolApprovalSettings = .init(),
        sandbox: AgentSandboxSettings = .init(),
        preToolsHook: AgentToolPreHookOverride = .init(),
        approvalGrants: [ToolApprovalGrant]? = nil,
        guardrails: AgentToolsGuardrails = .init()
    ) {
        self.version = version
        self.defaultPolicy = defaultPolicy
        self.tools = tools
        self.approval = approval
        self.sandbox = sandbox
        self.preToolsHook = preToolsHook
        self.approvalGrants = approvalGrants
        self.guardrails = guardrails
    }

    enum CodingKeys: String, CodingKey {
        case version
        case defaultPolicy
        case tools
        case approval
        case sandbox
        case preToolsHook
        case approvalGrants
        case guardrails
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(Int.self, forKey: .version)
        self.defaultPolicy = try container.decodeIfPresent(AgentPolicyDefault.self, forKey: .defaultPolicy) ?? .allow
        self.tools = try container.decodeIfPresent([String: Bool].self, forKey: .tools) ?? [:]
        self.approval = try container.decodeIfPresent(AgentToolApprovalSettings.self, forKey: .approval) ?? .init()
        self.sandbox = try container.decodeIfPresent(AgentSandboxSettings.self, forKey: .sandbox) ?? .init()
        self.preToolsHook = try container.decodeIfPresent(AgentToolPreHookOverride.self, forKey: .preToolsHook) ?? .init()
        self.approvalGrants = try container.decodeIfPresent([ToolApprovalGrant].self, forKey: .approvalGrants)
        self.guardrails = try container.decodeIfPresent(AgentToolsGuardrails.self, forKey: .guardrails) ?? .init()
    }
}

public struct AgentToolCatalogEntry: Codable, Sendable, Equatable {
    public var id: String
    public var domain: String
    public var title: String
    public var status: String
    public var description: String

    public init(id: String, domain: String, title: String, status: String, description: String) {
        self.id = id
        self.domain = domain
        self.title = title
        self.status = status
        self.description = description
    }
}

public struct ToolInvocationArgumentDiagnostics: Codable, Sendable, Equatable {
    public var toolCallId: String?
    public var providerToolName: String?
    public var originalToolName: String
    public var rawArgumentKind: String
    public var rawArguments: JSONValue?
    public var decodedArgumentCount: Int
    public var usedEmptyArgumentsFallback: Bool
    public var message: String?

    public init(
        toolCallId: String? = nil,
        providerToolName: String? = nil,
        originalToolName: String,
        rawArgumentKind: String,
        rawArguments: JSONValue? = nil,
        decodedArgumentCount: Int,
        usedEmptyArgumentsFallback: Bool,
        message: String? = nil
    ) {
        self.toolCallId = toolCallId
        self.providerToolName = providerToolName
        self.originalToolName = originalToolName
        self.rawArgumentKind = rawArgumentKind
        self.rawArguments = rawArguments
        self.decodedArgumentCount = decodedArgumentCount
        self.usedEmptyArgumentsFallback = usedEmptyArgumentsFallback
        self.message = message
    }
}

public struct ToolInvocationRequest: Codable, Sendable {
    public var tool: String
    public var arguments: [String: JSONValue]
    public var reason: String?
    public var argumentDiagnostics: ToolInvocationArgumentDiagnostics?

    public init(
        tool: String,
        arguments: [String: JSONValue] = [:],
        reason: String? = nil,
        argumentDiagnostics: ToolInvocationArgumentDiagnostics? = nil
    ) {
        self.tool = tool
        self.arguments = arguments
        self.reason = reason
        self.argumentDiagnostics = argumentDiagnostics
    }
}

public enum ToolApprovalStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case pending
    case approved
    case rejected
    case timedOut = "timed_out"
}

public enum ToolApprovalKind: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case riskyTool = "risky_tool"
    case missingAccess = "missing_access"
}

public enum ToolApprovalGrantKind: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case tool
    case directory
}

public struct ToolApprovalGrant: Codable, Sendable, Equatable, Hashable {
    public var kind: ToolApprovalGrantKind
    public var tool: String
    public var operation: String?
    public var resource: String?

    public init(
        kind: ToolApprovalGrantKind,
        tool: String,
        operation: String? = nil,
        resource: String? = nil
    ) {
        self.kind = kind
        self.tool = tool
        self.operation = operation
        self.resource = resource
    }
}

public struct ToolApprovalRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var status: ToolApprovalStatus
    public var approvalKind: ToolApprovalKind?
    public var agentId: String
    public var sessionId: String?
    public var displaySessionId: String?
    public var channelId: String?
    public var topicId: String?
    public var toolCallId: String?
    public var tool: String
    public var arguments: [String: JSONValue]
    public var grants: [ToolApprovalGrant]
    public var reason: String?
    public var requestedBy: String?
    public var decidedBy: String?
    public var decisionReason: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var expiresAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case status
        case approvalKind
        case agentId
        case sessionId
        case displaySessionId
        case channelId
        case topicId
        case toolCallId
        case tool
        case arguments
        case grants
        case reason
        case requestedBy
        case decidedBy
        case decisionReason
        case createdAt
        case updatedAt
        case expiresAt
    }

    public init(
        id: String = UUID().uuidString,
        status: ToolApprovalStatus = .pending,
        approvalKind: ToolApprovalKind? = nil,
        agentId: String,
        sessionId: String? = nil,
        displaySessionId: String? = nil,
        channelId: String? = nil,
        topicId: String? = nil,
        toolCallId: String? = nil,
        tool: String,
        arguments: [String: JSONValue] = [:],
        grants: [ToolApprovalGrant] = [],
        reason: String? = nil,
        requestedBy: String? = nil,
        decidedBy: String? = nil,
        decisionReason: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        expiresAt: Date
    ) {
        self.id = id
        self.status = status
        self.approvalKind = approvalKind
        self.agentId = agentId
        self.sessionId = sessionId
        self.displaySessionId = displaySessionId
        self.channelId = channelId
        self.topicId = topicId
        self.toolCallId = toolCallId
        self.tool = tool
        self.arguments = arguments
        self.grants = grants
        self.reason = reason
        self.requestedBy = requestedBy
        self.decidedBy = decidedBy
        self.decisionReason = decisionReason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.status = try container.decode(ToolApprovalStatus.self, forKey: .status)
        self.approvalKind = try container.decodeIfPresent(ToolApprovalKind.self, forKey: .approvalKind)
        self.agentId = try container.decode(String.self, forKey: .agentId)
        self.sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        self.displaySessionId = try container.decodeIfPresent(String.self, forKey: .displaySessionId)
        self.channelId = try container.decodeIfPresent(String.self, forKey: .channelId)
        self.topicId = try container.decodeIfPresent(String.self, forKey: .topicId)
        self.toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId)
        self.tool = try container.decode(String.self, forKey: .tool)
        self.arguments = try container.decodeIfPresent([String: JSONValue].self, forKey: .arguments) ?? [:]
        self.grants = try container.decodeIfPresent([ToolApprovalGrant].self, forKey: .grants) ?? []
        self.reason = try container.decodeIfPresent(String.self, forKey: .reason)
        self.requestedBy = try container.decodeIfPresent(String.self, forKey: .requestedBy)
        self.decidedBy = try container.decodeIfPresent(String.self, forKey: .decidedBy)
        self.decisionReason = try container.decodeIfPresent(String.self, forKey: .decisionReason)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.expiresAt = try container.decode(Date.self, forKey: .expiresAt)
    }
}

public struct ToolApprovalDecisionRequest: Codable, Sendable, Equatable {
    public var decidedBy: String?
    public var scope: ToolApprovalDecisionScope

    public init(decidedBy: String? = nil, scope: ToolApprovalDecisionScope = .once) {
        self.decidedBy = decidedBy
        self.scope = scope
    }
}

public enum ToolApprovalDecisionScope: String, Codable, Sendable, Equatable, CaseIterable {
    case once
    case session
    case always
}

extension ToolApprovalDecisionRequest {
    enum CodingKeys: String, CodingKey {
        case decidedBy
        case scope
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.decidedBy = try container.decodeIfPresent(String.self, forKey: .decidedBy)
        self.scope = try container.decodeIfPresent(ToolApprovalDecisionScope.self, forKey: .scope) ?? .once
    }
}

/// Fields that must change before a deterministic tool failure can be corrected.
/// Context fields distinguish independent operations (for example, memory scopes).
public struct ToolArgumentRecovery: Codable, Sendable, Equatable {
    public var invalidFields: [String]
    public var contextFields: [String]

    public init(invalidFields: [String], contextFields: [String] = []) {
        self.invalidFields = invalidFields
        self.contextFields = contextFields
    }
}

public struct ToolErrorPayload: Codable, Sendable, Equatable {
    public var code: String
    public var message: String
    public var retryable: Bool
    /// Optional guidance for the caller (e.g. how to fix path or permissions).
    public var hint: String?
    public var argumentRecovery: ToolArgumentRecovery?

    public init(code: String, message: String, retryable: Bool, hint: String? = nil, argumentRecovery: ToolArgumentRecovery? = nil) {
        self.code = code
        self.message = message
        self.retryable = retryable
        self.hint = hint
        self.argumentRecovery = argumentRecovery
    }
}

public struct ToolInvocationResult: Codable, Sendable, Equatable {
    public var tool: String
    public var ok: Bool
    public var data: JSONValue?
    public var error: ToolErrorPayload?
    public var durationMs: Int

    public init(
        tool: String,
        ok: Bool,
        data: JSONValue? = nil,
        error: ToolErrorPayload? = nil,
        durationMs: Int = 0
    ) {
        self.tool = tool
        self.ok = ok
        self.data = data
        self.error = error
        self.durationMs = durationMs
    }
}
