import Foundation

public enum ChatApprovalMode: String, Codable, Sendable, CaseIterable {
    case askForApproval = "ask_for_approval"
    case approveForMe = "approve_for_me"

    public var title: String {
        switch self {
        case .askForApproval: "Ask for approval"
        case .approveForMe: "Approve for me"
        }
    }

    public var detail: String {
        switch self {
        case .askForApproval: "Ask you before actions that require approval."
        case .approveForMe: "JEV reviews actions. If unavailable, Visor reviews them. When a human decision is needed, ask you."
        }
    }
}

public struct ChatApprovalPolicy: Codable, Sendable, Equatable {
    public var mode: ChatApprovalMode

    public init(mode: ChatApprovalMode) {
        self.mode = mode
    }
}
