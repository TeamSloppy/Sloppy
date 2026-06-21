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
        public var toolCallId: String?
        public var toolName: String
        public var providerToolName: String?
        public var argumentKind: String
        public var rawArguments: JSONValue?
        public var message: String

        public init(
            toolCallId: String? = nil,
            toolName: String,
            providerToolName: String? = nil,
            argumentKind: String,
            rawArguments: JSONValue? = nil,
            message: String
        ) {
            self.toolCallId = toolCallId
            self.toolName = toolName
            self.providerToolName = providerToolName
            self.argumentKind = argumentKind
            self.rawArguments = rawArguments
            self.message = message
        }
    }

    private struct ArgumentConversion: Sendable {
        var arguments: [String: JSONValue]
        var diagnostics: ToolInvocationArgumentDiagnostics
    }

    public let toolCallHandler: @Sendable (ToolInvocationRequest) async -> ToolInvocationResult
    private static let logger = Logger.pluginSDK(label: "sloppy.tool.delegate")
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
        let conversion = await jsonArguments(from: toolCall, toolName: toolName)
        let request = ToolInvocationRequest(
            tool: toolName,
            arguments: conversion.arguments,
            argumentDiagnostics: conversion.diagnostics
        )
        let result = await toolCallHandler(request)
        return .provideOutput([.text(.init(content: encodedResult(result)))])
    }

    private func jsonArguments(from toolCall: Transcript.ToolCall, toolName: String) async -> ArgumentConversion {
        let content = toolCall.arguments
        let providerToolName = toolCall.toolName == toolName ? nil : toolCall.toolName
        guard case .structure(let properties, _) = content.kind else {
            let kind = argumentKindDescription(content)
            let rawArguments = jsonValue(from: content)
            let diagnostic = ArgumentDiagnostic(
                toolCallId: toolCall.id,
                toolName: toolName,
                providerToolName: providerToolName,
                argumentKind: kind,
                rawArguments: rawArguments,
                message: "Native tool call arguments were not an object; using empty arguments."
            )
            Self.logger.warning(
                "tool_call_arguments_not_object",
                metadata: [
                    "tool_call_id": .string(toolCall.id),
                    "tool": .string(toolName),
                    "provider_tool": .string(toolCall.toolName),
                    "argument_kind": .string(kind),
                    "raw_arguments": .string(encodedJSONValue(rawArguments))
                ]
            )
            await argumentDiagnosticsHandler?(diagnostic)
            return ArgumentConversion(
                arguments: [:],
                diagnostics: ToolInvocationArgumentDiagnostics(
                    toolCallId: toolCall.id,
                    providerToolName: providerToolName,
                    originalToolName: toolName,
                    rawArgumentKind: kind,
                    rawArguments: rawArguments,
                    decodedArgumentCount: 0,
                    usedEmptyArgumentsFallback: true,
                    message: diagnostic.message
                )
            )
        }
        let arguments = properties.mapValues { jsonValue(from: $0) }
        return ArgumentConversion(
            arguments: arguments,
            diagnostics: ToolInvocationArgumentDiagnostics(
                toolCallId: toolCall.id,
                providerToolName: providerToolName,
                originalToolName: toolName,
                rawArgumentKind: "structure",
                decodedArgumentCount: arguments.count,
                usedEmptyArgumentsFallback: false
            )
        )
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

    private func encodedJSONValue(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8)
        else {
            return "<unencodable>"
        }
        return string
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
