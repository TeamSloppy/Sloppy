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
    private actor PreparedDecisionStore {
        private var decisions: [String: ToolExecutionDecision] = [:]
        private(set) var stopped = false
        private var malformedStreak = 0

        func recordMalformed() -> Int {
            malformedStreak += 1
            return malformedStreak
        }

        func resetMalformed() { malformedStreak = 0 }

        func stop() { stopped = true }

        func replace(with prepared: [(String, ToolExecutionDecision)]) {
            decisions = Dictionary(prepared, uniquingKeysWith: { _, latest in latest })
        }

        func take(for toolCallID: String) -> ToolExecutionDecision? {
            decisions.removeValue(forKey: toolCallID)
        }
    }

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
    private let emptyArgumentsAllowedTools: Set<String>
    private let executedToolCallHandler: (@Sendable (Transcript.ToolCall, Transcript.ToolOutput) async -> Void)?
    private let malformedArgumentsHandler: (@Sendable (ArgumentDiagnostic, Int) async -> Void)?
    private let concurrencySafeTools: Set<String>
    private let preparedDecisionStore = PreparedDecisionStore()

    public init(
        toolNameMap: [String: String] = [:],
        emptyArgumentsAllowedTools: Set<String> = [],
        concurrencySafeTools: Set<String> = ToolConcurrencyPolicy.readOnlyToolIDs,
        generatedToolCallsHandler: (@Sendable ([Transcript.ToolCall]) async -> Void)? = nil,
        toolCallDecisionOverride: (@Sendable (Transcript.ToolCall) async -> ToolExecutionDecision?)? = nil,
        argumentDiagnosticsHandler: (@Sendable (ArgumentDiagnostic) async -> Void)? = nil,
        malformedArgumentsHandler: (@Sendable (ArgumentDiagnostic, Int) async -> Void)? = nil,
        executedToolCallHandler: (@Sendable (Transcript.ToolCall, Transcript.ToolOutput) async -> Void)? = nil,
        toolCallHandler: @escaping @Sendable (ToolInvocationRequest) async -> ToolInvocationResult
    ) {
        self.toolNameMap = toolNameMap
        self.emptyArgumentsAllowedTools = emptyArgumentsAllowedTools
        self.concurrencySafeTools = concurrencySafeTools
        self.generatedToolCallsHandler = generatedToolCallsHandler
        self.toolCallDecisionOverride = toolCallDecisionOverride
        self.argumentDiagnosticsHandler = argumentDiagnosticsHandler
        self.malformedArgumentsHandler = malformedArgumentsHandler
        self.executedToolCallHandler = executedToolCallHandler
        self.toolCallHandler = toolCallHandler
    }

    public func didGenerateToolCalls(_ toolCalls: [Transcript.ToolCall], in session: LanguageModelSession) async {
        await generatedToolCallsHandler?(toolCalls)
        guard toolCalls.count > 1 else {
            return
        }

        // Read-only runs execute together; any other call is a barrier that runs alone in model order.
        let segments = ToolConcurrencyPolicy.segments(count: toolCalls.count) { index in
            let name = toolCalls[index].toolName
            return concurrencySafeTools.contains(toolNameMap[name] ?? name)
        }
        var prepared: [(String, ToolExecutionDecision)] = []
        prepared.reserveCapacity(toolCalls.count)
        for segment in segments {
            if await preparedDecisionStore.stopped { break }
            let calls = Array(toolCalls[segment])
            if calls.count == 1 {
                prepared.append((calls[0].id, await resolveDecision(for: calls[0])))
                continue
            }
            let results = await withTaskGroup(
                of: (String, ToolExecutionDecision).self,
                returning: [(String, ToolExecutionDecision)].self
            ) { group in
                for toolCall in calls {
                    group.addTask {
                        (toolCall.id, await resolveDecision(for: toolCall))
                    }
                }
                var collected: [(String, ToolExecutionDecision)] = []
                collected.reserveCapacity(calls.count)
                for await result in group { collected.append(result) }
                return collected
            }
            prepared.append(contentsOf: results)
        }
        await preparedDecisionStore.replace(with: prepared)
    }

    public func didExecuteToolCall(
        _ toolCall: Transcript.ToolCall,
        output: Transcript.ToolOutput,
        in session: LanguageModelSession
    ) async {
        await executedToolCallHandler?(toolCall, output)
    }

    public func toolCallDecision(
        for toolCall: Transcript.ToolCall,
        in session: LanguageModelSession
    ) async -> ToolExecutionDecision {
        if await preparedDecisionStore.stopped { return .stop }
        if let prepared = await preparedDecisionStore.take(for: toolCall.id) {
            return prepared
        }
        return await resolveDecision(for: toolCall)
    }

    private func resolveDecision(for toolCall: Transcript.ToolCall) async -> ToolExecutionDecision {
        if await preparedDecisionStore.stopped { return .stop }
        if let override = await toolCallDecisionOverride?(toolCall) {
            return override
        }
        let toolName = toolNameMap[toolCall.toolName] ?? toolCall.toolName
        let conversion = await jsonArguments(from: toolCall, toolName: toolName)
        if conversion.diagnostics.usedEmptyArgumentsFallback {
            // Never run a tool with guessed arguments: the model would see a misleading
            // "field is required" error for a call it actually filled in.
            let streak = await preparedDecisionStore.recordMalformed()
            await malformedArgumentsHandler?(
                ArgumentDiagnostic(
                    toolCallId: toolCall.id,
                    toolName: toolName,
                    providerToolName: toolCall.toolName == toolName ? nil : toolCall.toolName,
                    argumentKind: conversion.diagnostics.rawArgumentKind,
                    rawArguments: conversion.diagnostics.rawArguments,
                    message: conversion.diagnostics.message ?? ""
                ),
                streak
            )
            let result = Self.malformedArgumentsResult(toolName: toolName, streak: streak)
            return .provideOutput([.text(.init(content: encodedResult(result)))])
        }
        await preparedDecisionStore.resetMalformed()
        let request = ToolInvocationRequest(
            tool: toolName,
            arguments: conversion.arguments,
            argumentDiagnostics: conversion.diagnostics
        )
        let result = await toolCallHandler(request)
        if !result.ok, result.error?.code == "tool_loop_detected" {
            await preparedDecisionStore.stop()
            return .stop
        }
        return .provideOutput([.text(.init(content: encodedResult(result)))])
    }

    private func jsonArguments(from toolCall: Transcript.ToolCall, toolName: String) async -> ArgumentConversion {
        let content = toolCall.arguments
        let providerToolName = toolCall.toolName == toolName ? nil : toolCall.toolName
        if case .string(let text) = content.kind,
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           emptyArgumentsAllowedTools.contains(toolName) || emptyArgumentsAllowedTools.contains(toolCall.toolName) {
            // Tools without required parameters may legitimately be called with an empty argument string.
            return ArgumentConversion(
                arguments: [:],
                diagnostics: ToolInvocationArgumentDiagnostics(
                    toolCallId: toolCall.id,
                    providerToolName: providerToolName,
                    originalToolName: toolName,
                    rawArgumentKind: "empty",
                    decodedArgumentCount: 0,
                    usedEmptyArgumentsFallback: false
                )
            )
        }
        guard case .structure(let properties, _) = content.kind else {
            let kind = argumentKindDescription(content)
            let rawArguments = jsonValue(from: content)
            let diagnostic = ArgumentDiagnostic(
                toolCallId: toolCall.id,
                toolName: toolName,
                providerToolName: providerToolName,
                argumentKind: kind,
                rawArguments: rawArguments,
                message: "Native tool call arguments were not an object; the tool will not be run."
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

    /// Stable error code for tool calls whose arguments did not arrive as a JSON object.
    public static let malformedArgumentsErrorCode = "tool_call_arguments_malformed"

    static func malformedArgumentsResult(toolName: String, streak: Int) -> ToolInvocationResult {
        var hint = "Repeat this call with the complete JSON object of arguments, issuing one tool call at a time."
        if streak >= 2 {
            hint += " This happened \(streak) times in a row: do not batch calls, and do not conclude the task is blocked because of it."
        }
        return ToolInvocationResult(
            tool: toolName,
            ok: false,
            error: ToolErrorPayload(
                code: malformedArgumentsErrorCode,
                message: "The arguments of this call arrived empty or were not a JSON object, so the tool was not run. This is a transport problem, not a problem with the arguments you intended.",
                retryable: true,
                hint: hint
            )
        )
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
