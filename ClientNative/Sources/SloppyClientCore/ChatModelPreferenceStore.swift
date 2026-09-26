import Foundation

/// Keeps the composer choice for each chat and the starting choice for new chats.
public struct ChatModelPreferenceStore {
    private static let defaultsKey = "client_chat_model_preferences"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func selection(server: String, agentId: String, sessionId: String?) -> String? {
        let values = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
        if let sessionId,
           let selection = values[key(server: server, agentId: agentId, sessionId: sessionId)] {
            return selection
        }
        return values[key(server: server, agentId: agentId, sessionId: nil)]
    }

    public func setSelection(_ modelId: String, server: String, agentId: String, sessionId: String?) {
        var values = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
        values[key(server: server, agentId: agentId, sessionId: nil)] = modelId
        if let sessionId {
            values[key(server: server, agentId: agentId, sessionId: sessionId)] = modelId
        }
        defaults.set(values, forKey: Self.defaultsKey)
    }

    public func rememberSessionSelection(_ modelId: String, server: String, agentId: String, sessionId: String) {
        var values = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
        values[key(server: server, agentId: agentId, sessionId: sessionId)] = modelId
        defaults.set(values, forKey: Self.defaultsKey)
    }

    public func removeSession(server: String, agentId: String, sessionId: String) {
        var values = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
        values.removeValue(forKey: key(server: server, agentId: agentId, sessionId: sessionId))
        defaults.set(values, forKey: Self.defaultsKey)
    }

    private func key(server: String, agentId: String, sessionId: String?) -> String {
        let scope = [server, agentId, sessionId ?? ""]
        return scope.map { "\($0.utf8.count):\($0)" }.joined()
    }
}
