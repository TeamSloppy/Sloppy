import Foundation
import Observation
import SloppyClientCore
import SloppyClientUI
import SwiftUI
import UniformTypeIdentifiers

struct ChatMessageSendFailurePolicy {
    static func shouldRestoreDraft(
        after error: Error,
        optimisticMessageIsPresent: Bool
    ) -> Bool {
        guard optimisticMessageIsPresent else {
            return false
        }

        if let apiError = error as? APIError,
           case .decodingFailed = apiError {
            return false
        }

        return true
    }
}

struct SessionCatalogFetchResult: Sendable {
    var agentId: String
    var sessions: [ChatSessionSummary]?
}

struct ChatStreamingTurnTracker {
    private struct Turn {
        let sessionId: String
        let messageId: String
        var didReceiveFinalMessage = false
    }

    private var turns: [Turn] = []

    mutating func begin(sessionId: String, messageId: String) {
        turns.append(Turn(sessionId: sessionId, messageId: messageId))
    }

    func currentMessageId(for sessionId: String) -> String? {
        turns.first(where: { $0.sessionId == sessionId })?.messageId
    }

    mutating func claimFinalMessageId(for sessionId: String) -> String? {
        guard let index = turns.firstIndex(where: {
            $0.sessionId == sessionId && !$0.didReceiveFinalMessage
        }) else {
            return nil
        }
        turns[index].didReceiveFinalMessage = true
        return turns[index].messageId
    }

    @discardableResult
    mutating func completeNextTurn(for sessionId: String) -> String? {
        guard let index = turns.firstIndex(where: { $0.sessionId == sessionId }) else { return nil }
        return turns.remove(at: index).messageId
    }

    mutating func clear(sessionId: String? = nil) {
        guard let sessionId else {
            turns.removeAll()
            return
        }
        turns.removeAll { $0.sessionId == sessionId }
    }
}
