import AnyLanguageModel
import Foundation
import PluginSDK
import Protocols

extension RuntimeSystem {
    /// Source-compatible entry point. The former reconnect/stream/repair owners are retired.
    func respondInline(channelId: String, userMessage: String, model: String?, reasoningEffort: ReasoningEffort?,
        onResponseChunk: (@Sendable (String) async -> Bool)?,
        toolInvoker: (@Sendable (ToolInvocationRequest) async -> ToolInvocationResult)?,
        observationHandler: (@Sendable (RuntimeResponseObservation) async -> Void)?,
        nativeLoopConfig: NativeAgentLoopConfig,
        nativeLoopOutcomeHandler: (@Sendable (NativeAgentLoopOutcome) async -> Void)?,
        streamRetries: Int = 2, reconnectAttempt: Int = 0, rejectedModels: Set<String> = [], runState: RunState? = nil, agentLoopServices: AgentLoopServices? = nil) async {
        if agentLoopServices == nil, modelProvider == nil || resolvedAgentLoopModel(channelID: channelId, model: model) == nil {
            let fallback = "Responded inline"
            if let onResponseChunk { _ = await onResponseChunk(fallback) }
            await channels.appendSystemMessage(channelId: channelId, content: fallback)
            await nativeLoopOutcomeHandler?(.init(maxToolRounds: nativeLoopConfig.maxToolRounds,
                finishedNaturally: true, lastAssistantText: fallback, turnExitReason: .fallbackNoModel))
            return
        }
        var config = nativeLoopConfig
        config.engine = .unified
        await respondUsingAgentLoop(channelId: channelId, userMessage: userMessage, model: model,
            reasoningEffort: reasoningEffort, onResponseChunk: onResponseChunk, observationHandler: observationHandler,
            config: config, outcomeHandler: nativeLoopOutcomeHandler, runState: runState, services: agentLoopServices, toolInvoker: toolInvoker)
    }

    func isInterruptedModelSessionError(_ error: any Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: nsError.code) {
            case .networkConnectionLost, .timedOut:
                return true
            case .cancelled:
                return false
            case .unknown:
                // FoundationNetworking can lose the socket error code on Windows and
                // surface libcurl send/receive failures as NSURLErrorUnknown instead.
                // These are libcurl diagnostics, not model output or user text.
                if let description = nsError.userInfo[NSLocalizedDescriptionKey] as? String,
                   description.hasPrefix("Recv failure:") || description.hasPrefix("Send failure:") {
                    return true
                }
            default:
                break
            }
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isInterruptedModelSessionError(underlying)
        }

        return false
    }

    func emptyResponseRepairPrompt(
        channelId: String,
        originalUserMessage: String,
        transcript: Transcript
    ) async -> String {
        let channelMessages = await formatChannelMessagesForRepair(channelId: channelId)
        let modelTranscript = formatModelTranscriptForRepair(transcript)
        return """
        The previous model turn completed but produced no user-visible final answer.

        Write the final concise response for the user now. Use only the visible transcript, completed tool results, and progress shown below. Do not call tools. Do not claim to run new commands. Do not repeat completed work; summarize the solution or current outcome.

        [Current user message]
        \(originalUserMessage)

        [Visible channel transcript]
        \(channelMessages)

        [Model transcript and completed tool context]
        \(modelTranscript)

        [Final answer]
        """
    }

    func formatChannelMessagesForRepair(channelId: String, maxCharacters: Int = 6000) async -> String {
        let messages = await channels.snapshot(channelId: channelId)?.messages ?? []
        let lines = messages.suffix(20).map { message in
            "\(message.userId): \(message.content)"
        }
        return limitedRepairContext(lines.joined(separator: "\n"), maxCharacters: maxCharacters)
    }

    func formatModelTranscriptForRepair(_ transcript: Transcript, maxCharacters: Int = 12000) -> String {
        let lines = transcript.suffix(50).map { entry -> String in
            switch entry {
            case .instructions:
                return "instructions: [omitted]"
            case let .prompt(prompt):
                return "user: \(Self.textContent(from: prompt.segments))"
            case let .response(response):
                return "assistant: \(Self.textContent(from: response.segments))"
            case let .toolCalls(calls):
                let names = calls.map(\.toolName).joined(separator: ", ")
                return "tool calls: \(names)"
            case let .toolOutput(output):
                let text = Self.textContent(from: output.segments)
                return "tool result \(output.toolName): \(text)"
            }
        }
        return limitedRepairContext(lines.joined(separator: "\n"), maxCharacters: maxCharacters)
    }

    nonisolated static func textContent(from segments: [Transcript.Segment]) -> String {
        segments.compactMap { segment -> String? in
            switch segment {
            case let .text(text):
                return text.content
            case let .structure(structure):
                return structure.content.jsonString
            case .image:
                return "[image]"
            }
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func limitedRepairContext(_ text: String, maxCharacters: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "(empty)"
        }
        guard trimmed.count > maxCharacters else {
            return trimmed
        }
        let start = trimmed.index(trimmed.endIndex, offsetBy: -maxCharacters)
        return "[truncated]\n" + String(trimmed[start...])
    }
}
