import Foundation
import PluginSDK
import Protocols

/// The CLI gateway admits one upstream request; only AgentLoop can schedule tools or another step.
struct ClaudeCodeModelStepProvider: ModelStepProvider {
    let model: String
    let instructions: String
    let transport: ClaudeCodeTransport
    let usageContext: ModelUsageContext?

    func streamStep(_ request: ModelStepRequest) -> AsyncThrowingStream<ModelStepEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try Task.checkCancellation()
                    guard request.model == model else {
                        throw ModelStepFailure(category: .unavailable, code: "model_mismatch", message: "The CLI step is bound to another model.")
                    }
                    let nativeModel = String(model.dropFirst("claude-code:".count))
                    var prepared = request
                    switch request.reasoningEffort {
                    case .xhigh, .max: prepared.reasoningEffort = .high
                    default: break
                    }
                    let data = try AnthropicModelStepCodec.requestBody(prepared, model: nativeModel,
                        providerID: "claude-code", instructions: instructions)
                    guard var body = try JSONDecoder().decode(JSONValue.self, from: data).asObject,
                          let messages = body.removeValue(forKey: "messages")?.asArray else { throw ClaudeCodeError.invalidStream }
                    let system = body.removeValue(forKey: "system")?.asArray?.compactMap { $0.asObject?["text"]?.asString }.joined(separator: "\n\n") ?? ""
                    let history = try ClaudeCodeHistory(system: system, messages: messages)
                    body.removeValue(forKey: "model")
                    body.removeValue(forKey: "stream")
                    body["tools"] = body["tools"] ?? .array([])
                    continuation.yield(.started)
                    let result = try await transport.generate(model: nativeModel, history: history, extraBody: body,
                        effort: prepared.reasoningEffort?.rawValue, usageContext: usageContext)
                    try Task.checkCancellation()
                    var codec = AnthropicModelStepCodec(providerID: "claude-code", modelID: nativeModel)
                    _ = try codec.consume(result.wireResponse)
                    let response = try codec.finish()
                    if !result.reasoning.isEmpty { continuation.yield(.reasoningDelta(result.reasoning)) }
                    if !response.text.isEmpty { continuation.yield(.textDelta(response.text)) }
                    continuation.yield(.final(response))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: ModelStepFailure(category: .cancelled, code: "cli_cancelled", message: "The CLI request was cancelled."))
                } catch let failure as ModelStepFailure {
                    continuation.finish(throwing: failure)
                } catch {
                    continuation.finish(throwing: ModelStepFailure(category: .provider, code: "claude_code_failed",
                        message: error.localizedDescription))
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
