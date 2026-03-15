import AnyLanguageModel
import Foundation
import Protocols

/// Bridges AnyLanguageModel's `ToolExecutionDelegate` to Sloppy's tool invocation closure.
///
/// Intercepts native tool calls produced by the model, converts `GeneratedContent` arguments
/// to `[String: JSONValue]`, invokes the tool via the provided handler, and returns the
/// encoded result as structured output back to the session.
public struct SloppyToolExecutionDelegate: ToolExecutionDelegate {
    public let toolCallHandler: @Sendable (ToolInvocationRequest) async -> ToolInvocationResult

    public init(toolCallHandler: @escaping @Sendable (ToolInvocationRequest) async -> ToolInvocationResult) {
        self.toolCallHandler = toolCallHandler
    }

    public func toolCallDecision(
        for toolCall: Transcript.ToolCall,
        in session: LanguageModelSession
    ) async -> ToolExecutionDecision {
        let request = ToolInvocationRequest(
            tool: toolCall.toolName,
            arguments: jsonArguments(from: toolCall.arguments)
        )
        let result = await toolCallHandler(request)
        return .provideOutput([.text(.init(content: encodedResult(result)))])
    }

    private func jsonArguments(from content: GeneratedContent) -> [String: JSONValue] {
        guard case .structure(let properties, _) = content.kind else {
            return [:]
        }
        return properties.mapValues { jsonValue(from: $0) }
    }

    private func jsonValue(from content: GeneratedContent) -> JSONValue {
        switch content.kind {
        case .null: return .null
        case .bool(let v): return .bool(v)
        case .number(let v): return .number(v)
        case .string(let v): return .string(v)
        case .array(let elements): return .array(elements.map { jsonValue(from: $0) })
        case .structure(let properties, _):
            return .object(properties.mapValues { jsonValue(from: $0) })
        }
    }

    private func encodedResult(_ result: ToolInvocationResult) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{\"ok\":\(result.ok)}"
        }
        return string
    }
}
