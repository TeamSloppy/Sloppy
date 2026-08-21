import ACPModel
import Foundation
import Protocols

actor ACPServerSessionConfiguration {
    struct Values: Sendable, Equatable {
        var mode: AgentChatMode
        var modelID: String?
        var reasoningEffort: ReasoningEffort?
    }

    private var valuesBySessionID: [String: Values] = [:]

    func contains(sessionID: String) -> Bool {
        valuesBySessionID[sessionID] != nil
    }

    func values(sessionID: String, defaults: Values) -> Values {
        if let values = valuesBySessionID[sessionID] {
            return values
        }
        valuesBySessionID[sessionID] = defaults
        return defaults
    }

    func update(sessionID: String, defaults: Values, transform: (inout Values) -> Void) -> Values {
        var values = valuesBySessionID[sessionID] ?? defaults
        transform(&values)
        valuesBySessionID[sessionID] = values
        return values
    }
}

extension SloppyACPServerDelegate {
    static let modeConfigID = SessionConfigId("mode")
    static let modelConfigID = SessionConfigId("model")
    static let reasoningEffortConfigID = SessionConfigId("reasoning_effort")
}
