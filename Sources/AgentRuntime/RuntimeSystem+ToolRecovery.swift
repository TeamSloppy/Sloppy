import Foundation

extension RuntimeSystem {
    /// Retrying replays the user message from scratch. After tools have run that would repeat their side
    /// effects, so keep the executed tool transcript for the next turn and stop instead.
    func haltRetryAfterExecutedTools(
        channelId: String,
        tracker: StreamActivityTracker,
        config: NativeAgentLoopConfig,
        onResponseChunk: (@Sendable (String) async -> Bool)?,
        outcomeHandler: (@Sendable (NativeAgentLoopOutcome) async -> Void)?
    ) async -> Bool {
        guard await tracker.hasExecutedTools else { return false }
        let entries = await tracker.toolTranscriptEntries
        if !entries.isEmpty, let cached = sessionsByChannel[channelId]?.session {
            pendingToolTranscriptByChannel[channelId] = (ObjectIdentifier(cached), entries)
        }
        let text = "The model connection was interrupted after tools had already run. Their results are kept; send a message to continue."
        if let onResponseChunk { _ = await onResponseChunk(text) }
        await channels.appendSystemMessage(channelId: channelId, content: text)
        await outcomeHandler?(await tracker.nativeLoopOutcome(
            maxToolRounds: config.maxToolRounds,
            finishedNaturally: false,
            lastAssistantText: text,
            turnExitReason: .streamRetryFailed
        ))
        return true
    }

    /// A stopped native tool loop is terminal for this model turn, including empty-response fallbacks.
    func finishToolLoopBlock(
        channelId: String,
        tracker: StreamActivityTracker,
        config: NativeAgentLoopConfig,
        onResponseChunk: (@Sendable (String) async -> Bool)?,
        outcomeHandler: (@Sendable (NativeAgentLoopOutcome) async -> Void)?
    ) async -> Bool {
        if await tracker.yieldedToUserMessage {
            sessionsByChannel.removeValue(forKey: channelId)
            await outcomeHandler?(await tracker.nativeLoopOutcome(
                maxToolRounds: config.maxToolRounds,
                finishedNaturally: false,
                lastAssistantText: await tracker.latestContent,
                turnExitReason: .steered
            ))
            return true
        }
        guard let message = await tracker.toolLoopStopMessage else { return false }
        sessionsByChannel.removeValue(forKey: channelId)
        if let onResponseChunk { _ = await onResponseChunk(message) }
        await channels.appendSystemMessage(channelId: channelId, content: message)
        await outcomeHandler?(await tracker.nativeLoopOutcome(
            maxToolRounds: config.maxToolRounds,
            finishedNaturally: false,
            lastAssistantText: message,
            turnExitReason: .toolLoopDetected
        ))
        return true
    }
}
