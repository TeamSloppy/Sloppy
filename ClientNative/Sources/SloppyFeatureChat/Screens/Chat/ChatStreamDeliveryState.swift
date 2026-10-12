import Foundation
import Observation
import SloppyClientCore
import SloppyClientUI
import SwiftUI
import UniformTypeIdentifiers

struct SuspendedChatDelivery {
    var queue: ChatMessageQueue
    var optimisticMessages: [ChatMessage]
    var isSending: Bool
    var isAwaitingResponse: Bool
    var selectedModel: String?
    var reasoningEffort: String?
    var errorMessage: String?
    var revision: UInt = 0
}

/// Heartbeats repeat the latest cursor; ready establishes a new connection baseline.
struct ChatStreamCursorTracker {
    private(set) var cursor: Int?

    mutating func observe(_ update: ChatStreamUpdate) -> Bool {
        if update.kind == .sessionReady {
            cursor = update.cursor > 0 ? update.cursor : nil
            return false
        }
        guard update.cursor > 0 else { return false }
        let hasGap = cursor.map { update.cursor > $0 + (update.kind == .heartbeat ? 0 : 1) } ?? false
        cursor = max(cursor ?? 0, update.cursor)
        return hasGap
    }
}
