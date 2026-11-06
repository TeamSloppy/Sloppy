import Foundation
import AnyLanguageModel
import PluginSDK
import Protocols
import Testing

struct RemoteStepTestProvider: ModelProvider, ModelStepProviderFactory {
    let base: any ModelProvider
    let step: any ModelStepProvider
    var id: String { base.id }
    var supportedModels: [String] { base.supportedModels }
    func createLanguageModel(for modelName: String) async throws -> any LanguageModel { try await base.createLanguageModel(for: modelName) }
    func supportsModelSteps(for modelName: String) -> Bool { base.supports(modelName: modelName) }
    func createModelStepProvider(for modelName: String, usageContext: ModelUsageContext?) async throws -> (any ModelStepProvider)? { step }
}

struct RemoteFixtureStep: ModelStepProvider {
    let signature: String
    let thinking: String
    var block: (@Sendable () async throws -> Void)? = nil
    func streamStep(_ request: ModelStepRequest) -> AsyncThrowingStream<ModelStepEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.started)
                    try await block?()
                    let signed: Protocols.JSONValue = .object(["signature": .string(signature), "thinking": .string(thinking)])
                    if request.messages.last?.toolOutput != nil {
                        #expect(request.messages.last(where: { $0.role == .assistant })?.continuation?.content == signed)
                        continuation.yield(.final(.init(text: "from-work", stopReason: .endTurn)))
                    } else {
                        continuation.yield(.final(.init(toolCalls: [.init(id: "native-call", name: "local_echo",
                            rawArguments: #"{"value":"requesting-computer"}"#)], stopReason: .toolCalls,
                            continuation: .init(providerId: "fixture", modelId: request.model, format: "signed-fixture-v1", content: signed))))
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

func remoteFixtureRequest(model: String = "claude-code:sonnet") -> ModelStepRequest {
    .init(runId: UUID().uuidString, userTurnId: UUID().uuidString, stepId: UUID().uuidString, attemptId: UUID().uuidString,
        model: model, projectionRevision: "1", cacheScope: "fixture", messages: [.init(role: .user, text: "private-console-prompt")],
        tools: [.init(name: "local_echo", parameters: .object(["type": .string("object")]))])
}

func performRemoteFixtureRound(_ provider: any ModelStepProvider, model: String,
    tool: @Sendable (String) async throws -> String) async throws -> String {
    var request = remoteFixtureRequest(model: model)
    var first: ModelStepResponse?
    for try await event in provider.streamStep(request) { if case .final(let value) = event { first = value } }
    let response = try #require(first)
    #expect(response.toolCalls.count == 1)
    let call = try #require(response.toolCalls.first)
    let arguments = try JSONDecoder().decode(Protocols.JSONValue.self, from: Data(call.rawArguments.utf8))
    let value = try #require(arguments.asObject?["value"]?.asString)
    let result = try await tool(value)
    request.messages += [.init(role: .assistant, toolCalls: response.toolCalls, continuation: response.continuation),
        .init(role: .tool, toolOutput: .init(callId: call.id, name: call.name, content: result))]
    request.stepId = UUID().uuidString; request.attemptId = UUID().uuidString
    var final: ModelStepResponse?
    for try await event in provider.streamStep(request) { if case .final(let value) = event { final = value } }
    #expect(final?.stopReason == .endTurn)
    return try #require(final).text
}
