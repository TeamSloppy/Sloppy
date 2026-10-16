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

    func duplicateReadResult(channelId: String, request: ToolInvocationRequest) -> ToolInvocationResult? {
        workLedgerByChannel[channelId]?.duplicateReadResult(for: request).map { result in
            logger.info("Repeated read answered from session ledger", metadata: [
                "channel_id": .string(channelId),
                "tool": .string(request.tool),
            ])
            return result
        } ?? nil
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
