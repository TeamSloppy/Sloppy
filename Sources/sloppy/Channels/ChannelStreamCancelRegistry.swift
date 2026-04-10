import Foundation

/// Cooperative cancel flags for inbound channel model streams (`onResponseChunk` returns false).
actor ChannelStreamCancelRegistry {
    private var channelIds: Set<String> = []

    func requestCancel(channelId: String) {
        channelIds.insert(channelId)
    }

    func isCancelling(channelId: String) -> Bool {
        channelIds.contains(channelId)
    }

    func clearCancel(channelId: String) {
        channelIds.remove(channelId)
    }
}
