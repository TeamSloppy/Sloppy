import Foundation
import AnyLanguageModel
import PluginSDK
import Protocols

/// A generation fixture returns calls only. The production pipeline owns every effect.
struct FixtureModelStep: ModelStepProvider {
    let next: @Sendable (ModelStepRequest) async throws -> ModelStepResponse
    func streamStep(_ request: ModelStepRequest) -> AsyncThrowingStream<ModelStepEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.started)
                    continuation.yield(.final(try await next(request)))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

struct FixtureToolDeclaration: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String
    let name: String
    var example = GeneratedContent(properties: [:])
    let description = "Scripted declaration; only the runtime invoker may execute effects."
    var parameters: GenerationSchema {
        func schema(_ value: Protocols.JSONValue) -> Protocols.JSONValue {
            switch value {
            case .string: return .object(["type": .string("string")])
            case .bool: return .object(["type": .string("boolean")])
            case .number: return .object(["type": .string("number")])
            case .array(let values): return .object(["type": .string("array"), "items": values.first.map(schema) ?? .object(["type": .string("string")])])
            case .object(let values): return .object(["type": .string("object"), "properties": .object(values.mapValues(schema)), "required": .array([])])
            case .null: return .object(["type": .string("string")])
            }
        }
        let value = try! JSONDecoder().decode(Protocols.JSONValue.self, from: Data(example.jsonString.utf8))
        return try! JSONDecoder().decode(GenerationSchema.self, from: JSONEncoder().encode(schema(value)))
    }
    func call(arguments: GeneratedContent) async throws -> String { throw CancellationError() }
}
