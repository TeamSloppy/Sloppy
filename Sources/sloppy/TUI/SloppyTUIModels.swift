import Protocols

enum SloppyTUIPickerKind {
    case model
    case agent
    case session
    case provider
    case providerCatalog
}

struct SloppyTUIPickerItem {
    var value: String
    var label: String
    var description: String?
    var isCurrent: Bool
}

struct SloppyTUIPicker {
    var kind: SloppyTUIPickerKind
    var title: String
    var items: [SloppyTUIPickerItem]
    var selectedIndex: Int
}

enum SloppyTUITimelineBlock {
    case message(role: AgentMessageRole, text: String)
    case local(String)
    case error(String)
    case thinking(String)
    case attachment(name: String, mimeType: String, sizeBytes: Int)
    case toolCall(tool: String, reason: String?, argumentNames: [String])
    case toolResult(tool: String, ok: Bool, error: String?, durationMs: Int?)

    var plainText: String {
        switch self {
        case .message(_, let text), .local(let text), .error(let text):
            return text
        case .thinking(let text):
            return text
        case .attachment(let name, let mimeType, _):
            return "\(name) \(mimeType)"
        case .toolCall(let tool, let reason, let argumentNames):
            return ([tool] + argumentNames + [reason].compactMap { $0 }).joined(separator: " ")
        case .toolResult(let tool, _, let error, _):
            return ([tool] + [error].compactMap { $0 }).joined(separator: " ")
        }
    }
}

extension AgentChatMode {
    var next: AgentChatMode {
        switch self {
        case .ask: return .build
        case .build: return .plan
        case .plan: return .debug
        case .debug: return .ask
        }
    }

    var title: String {
        switch self {
        case .ask: return "Ask"
        case .build: return "Build"
        case .plan: return "Plan"
        case .debug: return "Debug"
        }
    }
}

