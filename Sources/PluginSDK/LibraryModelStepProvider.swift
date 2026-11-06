import Foundation
import AnyLanguageModel

enum LibraryModelStepBridge {
    static func convert<Input: Encodable, Output: Decodable>(_ value: Input, to: Output.Type = Output.self) throws -> Output {
        try JSONDecoder().decode(Output.self, from: JSONEncoder().encode(value))
    }
    static func failure(_ error: any Error) -> ModelStepFailure {
        if let failure = error as? ModelStepFailure { return failure }
        let failure = AnyLanguageModel.StepHTTPTransport.normalizedFailure(error)
        return .init(category: .init(rawValue: failure.category.rawValue) ?? .transport,
                     code: failure.code, message: failure.message, retryable: failure.retryable,
                     stage: .init(rawValue: failure.stage.rawValue) ?? .streaming,
                     retryAfterSeconds: failure.retryAfterSeconds, parameter: failure.parameter)
    }
    static func event(_ value: AnyLanguageModel.LanguageModelStepEvent) throws -> ModelStepEvent {
        switch value {
        case .started: return .started
        case .textDelta(let text): return .textDelta(text)
        case .reasoningDelta(let text): return .reasoningDelta(text)
        case .toolCallDelta(let index, let name, let arguments):
            return .toolCallDelta(index: index, name: name, arguments: arguments)
        case .final(let response): return .final(try convert(response))
        }
    }
}

/// Runtime policy stays in PluginSDK; all generation I/O belongs to AnyLanguageModel.
struct LibraryModelStepProvider: ModelStepProvider {
    let provider: any LanguageModelStepProvider
    func streamStep(_ request: ModelStepRequest) -> AsyncThrowingStream<ModelStepEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingOldest(256)) { continuation in
            let task = Task {
                do {
                    let input: AnyLanguageModel.LanguageModelStepRequest = try LibraryModelStepBridge.convert(request)
                    for try await event in provider.streamStep(input) {
                        try await ModelStepEventDelivery.yield(try LibraryModelStepBridge.event(event), into: continuation)
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: LibraryModelStepBridge.failure(error)) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
