import Foundation
import Observation
import SloppyClientCore
import SloppyClientUI
import SwiftUI
import UniformTypeIdentifiers

@Observable
@MainActor
public final class ChatTranscriptState {
    private static let initialVisibleWindowSize = 64
    private static let revealStep = 64

    private var allMessages: [ChatMessage] = []
    private var visibleStartIndex = 0

    public private(set) var messages: [ChatMessage] = []
    private(set) var entries: [ChatTranscriptEntry] = []
    private(set) var renderRevision: UInt = 0
    private(set) var identityRevision: UInt = 0

    var isEmpty: Bool {
        allMessages.isEmpty
    }

    var lastMessage: ChatMessage? {
        allMessages.last
    }

    var hasEarlierMessages: Bool {
        visibleStartIndex > 0
    }

    var hiddenMessageCount: Int {
        visibleStartIndex
    }

    func replaceAll(_ newMessages: [ChatMessage]) {
        allMessages = newMessages
        visibleStartIndex = max(0, newMessages.count - Self.initialVisibleWindowSize)
        refreshVisibleMessages()
    }

    func reconcile(with newMessages: [ChatMessage], revealingEarlier: Bool = false) {
        guard !allMessages.isEmpty else {
            replaceAll(newMessages)
            return
        }

        let visibleAnchorID = messages.first?.id
        // An older page must not roll back a card or response already updated by SSE.
        let updates: [ChatMessage.ID: ChatMessage] = revealingEarlier ? [:]
            : Dictionary(newMessages.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        var existingIDs = Set(allMessages.map(\.id))
        let additions = newMessages.filter { existingIDs.insert($0.id).inserted }.map { updates[$0.id] ?? $0 }
        allMessages = (allMessages.map { updates[$0.id] ?? $0 }
            + additions)
            .sorted { $0.createdAt < $1.createdAt }
        if revealingEarlier {
            visibleStartIndex = 0
        } else if let visibleAnchorID, let index = allMessages.firstIndex(where: { $0.id == visibleAnchorID }) {
            visibleStartIndex = index
        }
        refreshVisibleMessages()
    }

    var optimisticMessages: [ChatMessage] {
        allMessages.filter { $0.id.hasPrefix("optimistic-user-") }
    }

    func acknowledgeUserMessage(_ message: ChatMessage, optimisticID: String? = nil) {
        guard message.role == .user else { return }
        removeAll { $0.id == (optimisticID ?? "optimistic-user-\(message.id)") }
        reconcile(with: [message])
    }

    func clear() {
        allMessages = []
        visibleStartIndex = 0
        messages = []
        entries = []
        renderRevision &+= 1
        identityRevision &+= 1
    }

    func append(_ message: ChatMessage) {
        allMessages.append(message)
        refreshVisibleMessages()
    }

    func removeAll(where shouldBeRemoved: (ChatMessage) -> Bool) {
        allMessages.removeAll(where: shouldBeRemoved)
        visibleStartIndex = min(visibleStartIndex, allMessages.count)
        refreshVisibleMessages()
    }

    func upsert(_ message: ChatMessage, before anchorMessageId: String? = nil) {
        if let idx = allMessages.firstIndex(where: { $0.id == message.id }) {
            allMessages[idx] = message
        } else if let anchorMessageId,
                  let anchorIndex = allMessages.firstIndex(where: { $0.id == anchorMessageId }) {
            allMessages.insert(message, at: anchorIndex)
        } else {
            allMessages.append(message)
        }
        refreshVisibleMessages()
    }

    func replaceStreamingAssistant(messageId: String, with message: ChatMessage) {
        if let idx = allMessages.firstIndex(where: { $0.id == messageId }) {
            allMessages[idx] = message
        } else if let idx = allMessages.firstIndex(where: { $0.id == message.id }) {
            allMessages[idx] = message
        } else {
            allMessages.append(message)
        }
        refreshVisibleMessages()
    }

    func appendStreamingAssistantText(_ text: String, messageId: String) {
        if let messageIndex = allMessages.lastIndex(where: { $0.id == messageId }) {
            var message = allMessages[messageIndex]
            if let segmentIndex = message.segments.lastIndex(where: { $0.kind == .text }) {
                message.segments[segmentIndex].text = (message.segments[segmentIndex].text ?? "") + text
            } else {
                message.segments.append(ChatMessageSegment(kind: .text, text: text))
            }
            allMessages[messageIndex] = message
            // Text growth cannot change grouping or identity. Update the affected row
            // without rebuilding the transcript and all of its activity groups.
            let visibleIndex = messageIndex - visibleStartIndex
            if messages.indices.contains(visibleIndex),
               let entryIndex = entries.lastIndex(where: { $0.id == "message:\(messageId)" }),
               case .message = entries[entryIndex] {
                messages[visibleIndex] = message
                var response = message
                response.segments.removeAll(where: \.isAssistantActivity)
                entries[entryIndex] = .message(response)
                renderRevision &+= 1
                return
            }
        } else {
            allMessages.append(
                ChatMessage(
                    id: messageId,
                    role: .assistant,
                    segments: [ChatMessageSegment(kind: .text, text: text)]
                )
            )
        }
        refreshVisibleMessages()
    }

    func revealEarlierMessages() {
        visibleStartIndex = max(0, visibleStartIndex - Self.revealStep)
        refreshVisibleMessages()
    }

    private func refreshVisibleMessages() {
        guard !allMessages.isEmpty else {
            let hadEntries = !entries.isEmpty
            messages = []
            entries = []
            visibleStartIndex = 0
            renderRevision &+= 1
            if hadEntries {
                identityRevision &+= 1
            }
            return
        }

        visibleStartIndex = max(0, min(visibleStartIndex, allMessages.count - 1))
        let visibleMessages = Array(allMessages[visibleStartIndex...])
        let nextEntries = ChatTranscriptGrouping.entries(from: visibleMessages)
        if entries.map(\.id) != nextEntries.map(\.id) {
            identityRevision &+= 1
        }
        messages = visibleMessages
        entries = nextEntries
        renderRevision &+= 1
    }
}
