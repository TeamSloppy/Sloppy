import Foundation
import AnyLanguageModel
import PluginSDK
import AgentRuntime
import Protocols

extension CoreService {
    func modelStepCatalog() -> [ProviderModelOption] {
        listAvailableProviderModels().map { option in
            var result = option
            if !option.id.hasPrefix("sloppy:"),
               (modelProvider as? any ModelStepProviderFactory)?.supportsModelSteps(for: option.id) == true,
               !result.capabilities.contains("model_step_v1") { result.capabilities.append("model_step_v1") }
            return result
        }
    }

    func remoteModelStep(_ input: SloppyModelStepRequest, scope: String) async throws -> SloppyModelStepResponse {
        let request = input.request
        guard input.schemaVersion == 1 else {
            throw ModelStepFailure(category: .unavailable, code: "remote_step_version_unavailable", message: "Unsupported remote step version.")
        }
        guard !request.model.hasPrefix("sloppy:"), !request.runId.isEmpty, !request.userTurnId.isEmpty,
              !request.stepId.isEmpty, !request.attemptId.isEmpty, request.generation >= 0,
              (1...16_384).contains(request.maximumOutputTokens),
              listAvailableProviderModels().contains(where: { $0.id == request.model }),
              let provider = modelProvider, let factory = provider as? any ModelStepProviderFactory,
              factory.supportsModelSteps(for: request.model) else { throw SloppyRemoteError.unknownModel }
        let channel = "remote-step:" + ContentDigest.sha256(Data((scope + "\n" + request.cacheScope).utf8))
        var provenance = UsageProvenance()
        provenance.toolNameMap = Dictionary(request.tools.map { ($0.name, $0.toolId) }, uniquingKeysWith: { _, last in last })
        let observed = provider.supportsUsageObservation(for: request.model)
        let usageContext: ModelUsageContext? = observed ? .init(channelId: channel,
            provider: request.model.split(separator: ":").first.map(String.init) ?? provider.id,
            model: request.model, provenance: provenance, onRequest: { [weak self] record in
                var record = record; record.runId = request.runId; record.userTurnId = request.userTurnId
                await self?.persistMeasuredUsage(record)
            }) : nil
        guard let adapter = try await factory.createModelStepProvider(for: request.model, usageContext: usageContext) else { throw SloppyRemoteError.unknownModel }
        let state = try RunState(snapshot: .init(runID: request.runId, userTurnID: request.userTurnId, generation: request.generation))
        // This boundary never constructs an executor or schedules a returned call.
        let response = try await AgentLoop(provider: adapter, state: state).collectStep(request)
        if !observed, let usage = response.usage {
            await persistMeasuredUsage(.init(channelId: channel,
                provider: request.model.split(separator: ":").first.map(String.init) ?? provider.id,
                model: request.model, usage: usage, complete: false, runId: request.runId, userTurnId: request.userTurnId))
        }
        return .init(request: request, response: response)
    }

    func remoteModelStepResult(_ input: SloppyModelStepRequest, scope: String) async -> SloppyModelStepResponse {
        do { return try await remoteModelStep(input, scope: scope) }
        catch {
            return .init(request: input.request, failure: (error as? ModelStepFailure) ?? .init(
                category: error is CancellationError ? .cancelled : .provider, code: "remote_step_failed", message: "The remote model step failed."))
        }
    }

    func streamRemoteModelStep(_ input: SloppyModelStepRequest, scope: String) -> AsyncStream<CoreRouterServerSentEvent> {
        AsyncStream(bufferingPolicy: .bufferingOldest(1)) { continuation in
            let task = Task {
                let result = await remoteModelStepResult(input, scope: scope)
                if let data = try? JSONEncoder().encode(result) { continuation.yield(.init(event: "complete", data: data)) }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    func remoteInference(_ request: SloppyInferenceRequest) async throws -> SloppyInferenceResponse {
        let (model, session, capture, options) = try await prepareRemoteInference(request)
        let result = try await model.respond(within: session, to: Prompt(""), generating: String.self,
                                             includeSchemaInPrompt: false, options: options)
        let replay = await (model as? ClaudeCodeLanguageModel)?.replayCapture.snapshot(model: request.model)
        return await SloppyInferenceResponse(text: result.content, toolCalls: capture.calls, replay: replay)
    }

    func streamRemoteInference(_ request: SloppyInferenceRequest) async throws -> AsyncStream<CoreRouterServerSentEvent> {
        let (model, session, capture, options) = try await prepareRemoteInference(request)
        return AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
            let task = Task {
                do {
                    var text = ""
                    let stream = model.streamResponse(within: session, to: Prompt(""), generating: String.self,
                                                       includeSchemaInPrompt: false, options: options)
                    for try await snapshot in stream {
                        try Task.checkCancellation()
                        text = snapshot.content
                        let data = try JSONEncoder().encode(SloppyInferenceResponse(text: text, toolCalls: []))
                        continuation.yield(.init(event: "snapshot", data: data))
                    }
                    let replay = await (model as? ClaudeCodeLanguageModel)?.replayCapture.snapshot(model: request.model)
                    let result = await SloppyInferenceResponse(text: text, toolCalls: capture.calls, replay: replay)
                    continuation.yield(.init(event: "complete", data: try JSONEncoder().encode(result)))
                } catch {
                    continuation.yield(.init(event: "error", data: Data("{\"error\":\"remote_inference_failed\"}".utf8)))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func prepareRemoteInference(_ request: SloppyInferenceRequest, allowRemoteModel: Bool = false) async throws -> (
        any LanguageModel, LanguageModelSession, RemoteInferenceToolCapture, GenerationOptions
    ) {
        // Only configured local models may be exposed; remote-to-remote forwarding would allow cycles.
        guard (allowRemoteModel || !request.model.hasPrefix("sloppy:")),
              listAvailableProviderModels().contains(where: { $0.id == request.model }),
              let provider = modelProvider, provider.supports(modelName: request.model) else {
            throw SloppyRemoteError.unknownModel
        }
        var model = try await provider.createLanguageModel(for: request.model)
        if let replay = request.replay {
            if var remote = model as? SloppyRemoteModel, allowRemoteModel {
                remote.replaySeed = replay
                model = remote
            } else {
                guard replay.provider == "claude-code", replay.model == request.model,
                      var claude = model as? ClaudeCodeLanguageModel else { throw SloppyRemoteError.unknownModel }
                claude.replaySeed = replay
                model = claude
            }
        }
        var options = provider.generationOptions(for: request.model,
                                                 maxTokens: request.options.maximumResponseTokens ?? 8192,
                                                 reasoningEffort: request.reasoningEffort)
        options.temperature = request.options.temperature
        options.sampling = request.options.sampling
        let capture = RemoteInferenceToolCapture()
        let session = LanguageModelSession(model: model, tools: request.tools.map(RemoteInferenceTool.init), transcript: request.transcript)
        session.toolExecutionDelegate = capture
        return (model, session, capture, options)
    }
}

actor RemoteInferenceToolCapture: ToolExecutionDelegate {
    var calls: [Transcript.ToolCall] = []
    func didGenerateToolCalls(_ toolCalls: [Transcript.ToolCall], in session: LanguageModelSession) {
        calls = toolCalls
    }
    func toolCallDecision(for toolCall: Transcript.ToolCall, in session: LanguageModelSession) -> ToolExecutionDecision { .stop }
}

private struct RemoteInferenceTool: Tool {
    let definition: SloppyInferenceToolDefinition
    var name: String { definition.name }
    var description: String { definition.description }
    var parameters: GenerationSchema { definition.parameters }

    init(_ definition: SloppyInferenceToolDefinition) { self.definition = definition }

    func call(arguments: GeneratedContent) async throws -> String {
        throw SloppyRemoteError.toolUnavailable(name)
    }
}
