import Foundation

extension RuntimeSystem {
    /// Hand a post-tool disconnect to the journal owner. Only the owner can verify
    /// which tool effects were persisted before resuming the turn.
    func haltRetryAfterExecutedTools(
        channelId: String,
        tracker: StreamActivityTracker,
        config: NativeAgentLoopConfig,
        onResponseChunk: (@Sendable (String) async -> Bool)?,
        outcomeHandler: (@Sendable (NativeAgentLoopOutcome) async -> Void)?,
        contextExhausted: Bool = false
    ) async -> Bool {
        guard await tracker.hasExecutedTools else { return false }
        let entries = await tracker.toolTranscriptEntries
        if !entries.isEmpty, let cached = sessionsByChannel[channelId]?.session {
            pendingToolTranscriptByChannel[channelId] = (ObjectIdentifier(cached), entries)
        }
        let text = contextExhausted
            ? "The model context was exhausted after tool execution. The tool results were kept."
            : config.managesPostToolRecovery
            ? "The model connection was interrupted after tool execution. Check the saved results and use /restore to continue."
            : "The model connection was interrupted after tools had already run. Their results are kept; send a message to continue."
        if !config.managesPostToolRecovery {
            if let onResponseChunk { _ = await onResponseChunk(text) }
            await channels.appendSystemMessage(channelId: channelId, content: text)
        }
        await outcomeHandler?(await tracker.nativeLoopOutcome(
            maxToolRounds: config.maxToolRounds,
            finishedNaturally: false,
            lastAssistantText: text,
            turnExitReason: contextExhausted ? .contextWindowRecoveryFailed
                : (config.managesPostToolRecovery ? .streamInterruptedAfterTools : .streamRetryFailed)
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
