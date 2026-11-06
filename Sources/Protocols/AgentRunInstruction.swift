import Foundation

/// Runtime control is explicit and scoped by the surrounding run/turn/generation envelope.
public struct AgentRunInstruction: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case completionRecovery = "completion_recovery"
        case finalAnswer = "final_answer"
        case turnContext = "turn_context"
    }
    public var schemaVersion: Int
    public var id: String
    public var kind: Kind
    public var text: String
    public init(schemaVersion: Int = 1, id: String = UUID().uuidString, kind: Kind, text: String) {
        self.schemaVersion = schemaVersion; self.id = id; self.kind = kind; self.text = text
    }
}
