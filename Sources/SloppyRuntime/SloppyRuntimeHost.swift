import AgentRuntime
import AnyLanguageModel
import Foundation
import PluginSDK
import Protocols

public struct SloppyBuildResult: Sendable {
    public let ok: Bool
    public let summary: String

    public init(ok: Bool, summary: String) {
        self.ok = ok
        self.summary = summary
    }
}

public struct SloppyChatMessage: Identifiable, Sendable {
    public enum Role: Equatable, Sendable {
        case user
        case assistant
    }

    public let id: String
    public let role: Role
    public let text: String
    public let createdAt: Date
    public let artifacts: [AgentToolOutputArtifact]

    public init(id: String, role: Role, text: String, createdAt: Date, artifacts: [AgentToolOutputArtifact] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.artifacts = artifacts
    }
}

/// Activity signals from the model loop, without reasoning or tool payloads.
public enum SloppyAgentActivity: Sendable, Equatable {
    case thinking
    case toolStarted(String)
    case toolFinished(String, succeeded: Bool)
}

/// An in-process Sloppy model loop that can be hosted by a mobile app.
public actor SloppyRuntimeHost {
    static let agentID = "mobile"

    public enum HostError: Error, LocalizedError, Sendable {
        case missingCredentials
        case missingModel
        case invalidAPIURL
        case emptyPrompt
        case emptyResponse
        case reentrantSend
        case reconciliationRequired
        case runtimeFailure(String)

        public var errorDescription: String? {
            switch self {
            case .missingCredentials: "Add an OpenAI API key in Agent settings."
            case .missingModel: "Choose a model in Agent settings."
            case .invalidAPIURL: "Enter a valid API URL in Agent settings."
            case .emptyPrompt: "Describe what the agent should create."
            case .emptyResponse: "The model did not return a response. Try again."
            case .reentrantSend: "Do not await send for the same conversation from a host callback. Submit from an independent UI task."
            case .reconciliationRequired: "Reconcile the interrupted embedded tool outcome before continuing."
            case .runtimeFailure(let message): message
            }
        }
    }

    let runtime: RuntimeSystem
    var nativeEngine: AgentNativeEngine
    let additionalTools: [SloppyHostToolDefinition]
    private var imageProvider: OpenAIModelProvider?
    var modelID: String?
    var activeNativeChannels: Set<String> = []
    var nativeSessionLeases: [String: (lease: FileOwnershipLease, callers: Int)] = [:]
    struct NativeTurnWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }
    var nativeTurnWaiters: [String: [NativeTurnWaiter]] = [:]
    var nativeInputCallers: [String: Int] = [:]
    private var configuredKey: String?

    public init(additionalTools: [SloppyHostToolDefinition] = [], nativeEngine: AgentNativeEngine = .legacy) {
        self.additionalTools = additionalTools
        self.nativeEngine = nativeEngine
        runtime = SloppyRuntimeBootstrap.makeSystem(
            modelProvider: nil,
            memoryStore: InMemoryMemoryStore(),
            configuration: SloppyRuntimeConfiguration()
        )
    }

    /// An injected runtime keeps embedded-host behavior testable without network credentials.
    init(runtime: RuntimeSystem, modelID: String, nativeEngine: AgentNativeEngine) {
        self.runtime = runtime
        self.modelID = modelID
        self.nativeEngine = nativeEngine
        additionalTools = []
    }

    public func configureOpenAI(apiKey: String, model: String, apiURL: String = "https://api.openai.com/v1") async throws {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw HostError.missingCredentials }
        let rawModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawModel.isEmpty else { throw HostError.missingModel }
        guard let baseURL = URL(string: apiURL), baseURL.host != nil else { throw HostError.invalidAPIURL }
        let selectedModel = rawModel.hasPrefix("openai-api:") ? rawModel : "openai-api:\(rawModel)"
        if modelID == selectedModel, configuredKey == key { return }
        let provider = OpenAIModelProvider(
            supportedModels: [selectedModel],
            settings: .init(apiKey: { key }, baseURL: baseURL),
            tools: SloppyWorkspaceToolExecutor.modelTools + additionalTools.map { $0.modelTool }
        )
        imageProvider = provider
        await runtime.updateModelProvider(modelProvider: provider, defaultModel: selectedModel)
        modelID = selectedModel
        configuredKey = key
    }

    public func configureCodex(
        tokenProvider: @escaping @Sendable () -> String,
        accountID: String?,
        model: String,
        refreshIfNeeded: @escaping @Sendable () async throws -> Void,
        refreshAfterInvalidToken: @escaping @Sendable () async throws -> Void
    ) async throws {
        let token = tokenProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw HostError.missingCredentials }
        let rawModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawModel.isEmpty else { throw HostError.missingModel }
        let selectedModel = rawModel.hasPrefix("openai-api:") ? rawModel : "openai-api:\(rawModel)"
        if modelID == selectedModel, configuredKey == token { return }
        let provider = OpenAIModelProvider(
            supportedModels: [selectedModel],
            settings: .init(
                apiKey: tokenProvider,
                accountId: accountID,
                refreshTokenIfNeeded: refreshIfNeeded,
                refreshTokenAfterInvalidToken: refreshAfterInvalidToken,
                useOpenAICodexOAuthPath: true
            ),
            tools: SloppyWorkspaceToolExecutor.modelTools + additionalTools.map { $0.modelTool }
        )
        imageProvider = provider
        await runtime.updateModelProvider(modelProvider: provider, defaultModel: selectedModel)
        modelID = selectedModel
        configuredKey = token
    }

    /// Sends a user turn through Sloppy's native loop. `onText` receives full text snapshots.
    /// `persistedSessionID` creates or resumes that exact stored conversation. Use its ID as the channel's `sessionID`.
    /// Omitting it preserves the latest-session behavior.
    public func send(
        prompt: String,
        sessionID: String,
        workspaceURL: URL,
        build: @escaping @Sendable () async -> SloppyBuildResult,
        onText: @escaping @Sendable (String) async -> Void,
        onActivity: @escaping @Sendable (SloppyAgentActivity) async -> Void = { _ in },
        additionalToolHandler: (@Sendable (ToolInvocationRequest) async -> ToolInvocationResult)? = nil,
        maxToolRounds: Int = 80,
        images: [SloppyImageInput] = [],
        persistedSessionID: String? = nil,
        clientMessageID: String? = nil,
        deliveryIntent: AgentInputDeliveryIntent? = nil
    ) async throws -> String {
        let content = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw HostError.emptyPrompt }
        try Self.validateImages(images)
        // The legacy argument remains readable; execution always uses the canonical owner.
        nativeEngine = .unified
        return try await sendNative(prompt: content, channelID: sessionID, workspaceURL: workspaceURL,
            build: build, onText: onText, onActivity: onActivity, additionalToolHandler: additionalToolHandler,
            maxToolRounds: maxToolRounds, images: images, persistedSessionID: persistedSessionID,
            clientMessageID: clientMessageID, deliveryIntent: deliveryIntent)
    }

    /// Runs an image question on the configured vision-capable provider without invoking workspace tools.
    public func analyzeImages(_ images: [SloppyImageInput], question: String) async throws -> String {
        try Self.validateImages(images)
        guard !images.isEmpty else { throw HostError.runtimeFailure("Provide at least one image.") }
        guard let imageProvider, let modelID else { throw HostError.missingCredentials }
        let model = try await imageProvider.createLanguageModel(for: modelID)
        let session = LanguageModelSession(model: model)
        return try await session.respond(to: question, images: images.map(\.segment)).content
    }

    public static func validateImages(_ images: [SloppyImageInput]) throws {
        guard images.count <= 8, images.reduce(0, { $0 + $1.data.count }) <= 24 * 1024 * 1024,
              images.allSatisfy({ !$0.data.isEmpty && $0.data.count <= 8 * 1024 * 1024 && ["image/png", "image/jpeg", "image/webp"].contains($0.mimeType) }) else {
            throw HostError.runtimeFailure("Provide up to 8 PNG/JPEG/WebP images, at most 8 MB each and 24 MB total.")
        }
    }

    /// Reads persisted conversation turns for a mobile project without creating a new session.
    public func messages(workspaceURL: URL, persistedSessionID: String? = nil) throws -> [SloppyChatMessage] {
        let agentsRoot = try agentsRootURL(workspaceURL: workspaceURL)
        let agentDirectory = agentsRoot.appendingPathComponent(Self.agentID, isDirectory: true)
        guard FileManager.default.fileExists(atPath: agentDirectory.path) else { return [] }
        let store = AgentSessionFileStore(agentsRootURL: agentsRoot)
        let selected = try persistedSessionID ?? store.listSessions(agentID: Self.agentID, limit: 1).first?.id
        guard let selected else { return [] }
        let detail = try store.loadSession(agentID: Self.agentID, sessionID: selected)
        return detail.events.compactMap { event in
            guard event.runtimeMetadata?.auxiliaryPurpose == nil else { return nil }
            if let artifact = event.runtimeMetadata?.toolOutputArtifact,
               artifact.agentId == Self.agentID, artifact.sessionId == selected {
                return SloppyChatMessage(id: event.id, role: .assistant, text: "Tool output", createdAt: event.createdAt, artifacts: [artifact])
            }
            guard let message = event.message else { return nil }
            let role: SloppyChatMessage.Role
            switch message.role {
            case .user: role = .user
            case .assistant: role = .assistant
            case .system: return nil
            }
            let text = message.segments.compactMap(\.text).joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return SloppyChatMessage(id: event.id, role: role, text: text, createdAt: event.createdAt)
        }
    }

    func prepareSession(channelID: String, workspaceURL: URL, persistedSessionID: String? = nil) async throws -> (AgentSessionFileStore, String) {
        let (store, selected) = try prepareStoredSession(channelID: channelID, workspaceURL: workspaceURL, persistedSessionID: persistedSessionID)
        let hasLiveSession = await runtime.hasCachedChannelSession(channelId: channelID)
        if !hasLiveSession && nativeEngine == .legacy {
            let detail = try store.loadSession(agentID: Self.agentID, sessionID: selected)
            let transcript = AgentSessionTranscriptBuilder.buildRecoveryTranscript(current: detail, imageLoader: { attachment in
                try? SessionImageLoader.load(store: store, agentID: Self.agentID, attachment: attachment)
            })
            if AgentSessionTranscriptBuilder.hasRecoverableEntries(transcript) {
                await runtime.setChannelRecoveryTranscript(channelId: channelID, transcript: transcript)
            }
        }
        return (store, selected)
    }
    /// Native setup holds an OS lease and must never suspend its actor before enqueue ownership exists.
    func prepareStoredSession(channelID: String, workspaceURL: URL, persistedSessionID: String? = nil) throws -> (AgentSessionFileStore, String) {
        let agentsRoot = try agentsRootURL(workspaceURL: workspaceURL)
        try FileManager.default.createDirectory(
            at: agentsRoot.appendingPathComponent(Self.agentID, isDirectory: true),
            withIntermediateDirectories: true
        )
        let store = AgentSessionFileStore(agentsRootURL: agentsRoot)
        let summary: AgentSessionSummary
        if let persistedSessionID {
            summary = try store.createSession(
                agentID: Self.agentID,
                request: AgentSessionCreateRequest(projectId: channelID),
                importedSessionID: persistedSessionID
            )
        } else {
            let summaries = try store.listSessions(agentID: Self.agentID, limit: 1)
            let legacyID = nativeEngine == .unified && summaries.isEmpty ? try latestLegacySessionID(workspaceURL: workspaceURL) : nil
            summary = try summaries.first ?? store.createSession(
                agentID: Self.agentID,
                request: AgentSessionCreateRequest(title: "Mobile game", projectId: channelID), importedSessionID: legacyID
            )
        }
        if nativeEngine == .unified { try importLegacyHistoryIfNeeded(store: store, sessionID: summary.id, workspaceURL: workspaceURL) }
        return (store, summary.id)
    }

}
