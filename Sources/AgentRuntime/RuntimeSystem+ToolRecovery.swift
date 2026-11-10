import Foundation

extension RuntimeSystem {
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
