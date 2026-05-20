import AnyLanguageModel
import Foundation
import Logging
import Protocols

/// Bridges AnyLanguageModel's `ToolExecutionDelegate` to Sloppy's tool invocation closure.
///
/// Intercepts native tool calls produced by the model, converts `GeneratedContent` arguments
/// to `[String: JSONValue]`, invokes the tool via the provided handler, and returns the
/// encoded result as structured output back to the session.
public struct SloppyToolExecutionDelegate: ToolExecutionDelegate {
    public struct ArgumentDiagnostic: Sendable, Equatable {
        public var toolName: String
        public var argumentKind: String
        public var message: String

        public init(toolName: String, argumentKind: String, message: String) {
            self.toolName = toolName
            self.argumentKind = argumentKind
            self.message = message
        }
    }

    public let toolCallHandler: @Sendable (ToolInvocationRequest) async -> ToolInvocationResult
    private static let logger = Logger(label: "sloppy.tool.delegate")
    private let toolNameMap: [String: String]
    private let generatedToolCallsHandler: (@Sendable ([Transcript.ToolCall]) async -> Void)?
    private let toolCallDecisionOverride: (@Sendable (Transcript.ToolCall) async -> ToolExecutionDecision?)?
    private let argumentDiagnosticsHandler: (@Sendable (ArgumentDiagnostic) async -> Void)?

    public init(
        toolNameMap: [String: String] = [:],
        generatedToolCallsHandler: (@Sendable ([Transcript.ToolCall]) async -> Void)? = nil,
        toolCallDecisionOverride: (@Sendable (Transcript.ToolCall) async -> ToolExecutionDecision?)? = nil,
        argumentDiagnosticsHandler: (@Sendable (ArgumentDiagnostic) async -> Void)? = nil,
        toolCallHandler: @escaping @Sendable (ToolInvocationRequest) async -> ToolInvocationResult
    ) {
        self.toolNameMap = toolNameMap
        self.generatedToolCallsHandler = generatedToolCallsHandler
        self.toolCallDecisionOverride = toolCallDecisionOverride
        self.argumentDiagnosticsHandler = argumentDiagnosticsHandler
        self.toolCallHandler = toolCallHandler
    }

    public func didGenerateToolCalls(_ toolCalls: [Transcript.ToolCall], in session: LanguageModelSession) async {
        await generatedToolCallsHandler?(toolCalls)
    }

    public func toolCallDecision(
        for toolCall: Transcript.ToolCall,
        in session: LanguageModelSession
    ) async -> ToolExecutionDecision {
        if let override = await toolCallDecisionOverride?(toolCall) {
            return override
        }
        let toolName = toolNameMap[toolCall.toolName] ?? toolCall.toolName
        let arguments = await jsonArguments(from: toolCall.arguments, toolName: toolName)
        let request = ToolInvocationRequest(
            tool: toolName,
            arguments: arguments
        )
        let result = await toolCallHandler(request)
        return .provideOutput([.text(.init(content: encodedResult(result)))])
    }

    private func jsonArguments(from content: GeneratedContent, toolName: String) async -> [String: JSONValue] {
        guard case .structure(let properties, _) = content.kind else {
            let kind = argumentKindDescription(content)
            let diagnostic = ArgumentDiagnostic(
                toolName: toolName,
                argumentKind: kind,
                message: "Native tool call arguments were not an object; using empty arguments."
            )
            Self.logger.warning(
                "tool_call_arguments_not_object",
                metadata: [
                    "tool": .string(toolName),
                    "argument_kind": .string(kind)
                ]
            )
            await argumentDiagnosticsHandler?(diagnostic)
            return [:]
        }
        return properties.mapValues { jsonValue(from: $0) }
    }

    private func argumentKindDescription(_ content: GeneratedContent) -> String {
        switch content.kind {
        case .null: return "null"
        case .bool: return "bool"
        case .number: return "number"
        case .string: return "string"
        case .array: return "array"
        case .structure: return "structure"
        }
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

    public static func encodedResult(_ result: ToolInvocationResult) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{\"ok\":\(result.ok)}"
        }
        return string
    }

    private func encodedResult(_ result: ToolInvocationResult) -> String {
        Self.encodedResult(result)
    }
}
