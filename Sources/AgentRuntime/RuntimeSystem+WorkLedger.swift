import AnyLanguageModel
import Foundation
import PluginSDK
import Protocols

extension RuntimeSystem {
    static let derivedChannelMarkers = [":memory-checkpoint:"]

    /// Background channels derived from a session channel (for example a memory checkpoint) must run on the
    /// model of the session that spawned them, not on the provider default.
    func inheritedModel(for channelId: String) -> String? {
        for marker in Self.derivedChannelMarkers {
            if let range = channelId.range(of: marker) {
                return lastActiveModelByChannel[String(channelId[..<range.lowerBound])]
            }
        }
        return nil
    }

    /// The same observation path is used by streaming, fallback and context-reset requests.
    /// Access checks and approvals remain in the injected invoker.
    func observedToolHandler(
        channelId: String,
        model: String,
        tracker: StreamActivityTracker?,
        observationHandler: (@Sendable (RuntimeResponseObservation) async -> Void)?,
        invoker: @escaping @Sendable (ToolInvocationRequest) async -> ToolInvocationResult
    ) -> @Sendable (ToolInvocationRequest) async -> ToolInvocationResult {
        { request in
            await self.logNativeToolCallDecoded(channelId: channelId, model: model, request: request)
            let toolCallID = request.argumentDiagnostics?.toolCallId ?? UUID().uuidString
            await tracker?.toolStarted(id: toolCallID)
            await observationHandler?(.toolCall(request))
            let result = await invoker(request)
            await self.recordLedgerObservation(channelId: channelId, request: request, result: result)
            await self.usageToolOutcomeHandler?(channelId, toolCallID, result.ok)
            await observationHandler?(.toolResult(result))
            await tracker?.toolFinished(id: toolCallID, result: result)
            return result
        }
    }

    func recordLedgerObservation(channelId: String, request: ToolInvocationRequest, result: ToolInvocationResult) {
        workLedgerByChannel[channelId, default: SessionWorkLedger()].observe(request: request, result: result)
    }

    public func workLedgerText(channelId: String) -> String {
        workLedgerByChannel[channelId]?.render() ?? ""
    }

    /// A streamed turn records only the final reply in the session transcript. Re-insert the tool calls
    /// and outputs of that turn so the next turn still sees what was read and done.
    func mergePendingToolTranscript(
        channelId: String,
        session: LanguageModelSession,
        activeModel: String,
        provider: any ModelProvider
    ) async throws -> LanguageModelSession {
        guard let pending = pendingToolTranscriptByChannel.removeValue(forKey: channelId),
              pending.session == ObjectIdentifier(session),
              !pending.entries.isEmpty
        else { return session }

        let tools = sanitizedModelTools(channelId: channelId, modelProvider: provider, includeTools: !session.tools.isEmpty, activeModel: activeModel)
        let toolEntries = Array(transcriptWithProviderSafeToolNames(Transcript(entries: pending.entries), tools: tools))
        var entries = Array(session.transcript)
        if let last = entries.last, case .response = last {
            entries.insert(contentsOf: toolEntries, at: entries.count - 1)
        } else {
            entries.append(contentsOf: toolEntries)
        }
        let model = try await createUsageObservedModel(provider: provider, model: activeModel, channelId: channelId)
        let rebuilt = LanguageModelSession(model: model, tools: tools, transcript: Transcript(entries: entries))
        sessionsByChannel[channelId] = CachedLanguageModelSession(model: activeModel, session: rebuilt)
        return rebuilt
    }
}

extension RuntimeSystem {
    func cacheSessionForTesting(channelId: String, model: String, session: LanguageModelSession) {
        sessionsByChannel[channelId] = CachedLanguageModelSession(model: model, session: session)
    }

    func setPendingToolTranscriptForTesting(channelId: String, session: LanguageModelSession, entries: [Transcript.Entry]) {
        pendingToolTranscriptByChannel[channelId] = (ObjectIdentifier(session), entries)
    }
}
