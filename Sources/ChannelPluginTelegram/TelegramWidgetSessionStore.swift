import Foundation
import PluginSDK

/// Volatile capabilities: old widgets safely expire on restart, stop, or after 24 hours.
actor TelegramWidgetSessionStore {
    struct Entry: Sendable {
        let handle: String
        let owner: TelegramWidgetOwner
        let chatID: Int64
        let messageID: Int64
        let actions: Set<String>
        let createdAt: Date
    }
    private var entries: [String: Entry] = [:]
    private var queries: Set<String> = []

    func register(owner: TelegramWidgetOwner, chatID: Int64, messageID: Int64, actions: [String]) -> String {
        prune()
        if entries.count >= 256, let oldest = entries.values.min(by: { $0.createdAt < $1.createdAt }) {
            entries[oldest.handle] = nil
        }
        let handle = UUID().uuidString
        entries[handle] = Entry(handle: handle, owner: owner, chatID: chatID, messageID: messageID,
                                actions: Set(actions), createdAt: Date())
        return handle
    }
    func entry(handle: String, owner: TelegramWidgetOwner) -> Entry? {
        prune()
        guard let entry = entries[handle], entry.owner == owner else { return nil }
        return entry
    }
    func claim(query: TelegramBotAPI.WidgetQuery) -> Entry? {
        prune()
        guard query.type == nil || (query.type?.type == "data" && query.type?.hasWallet == false),
              let chat = query.chat, chat.type == "private", chat.id == query.from.id,
              let messageID = query.messageId, (1...64).contains(query.data.utf8.count),
              !queries.contains(query.id),
              let entry = entries.values.first(where: {
                  $0.chatID == chat.id && $0.messageID == messageID && $0.owner.userID == query.from.id
                      && $0.actions.contains(query.data)
              }) else { return nil }
        if queries.count >= 4096 { queries.removeAll() }
        queries.insert(query.id)
        return entry
    }
    func clear() { entries.removeAll(); queries.removeAll() }
    private func prune() {
        let cutoff = Date().addingTimeInterval(-86400)
        entries = entries.filter { $0.value.createdAt > cutoff }
    }
}
