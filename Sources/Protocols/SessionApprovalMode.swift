import Foundation

/// A chat's approval mode, inherited by its delegated sessions.
public enum SessionApprovalMode: String, Codable, Sendable, Equatable {
    case askForApproval = "ask_for_approval"
    case approveForMe = "approve_for_me"
}

public struct SessionApprovalPolicy: Codable, Sendable, Equatable {
    public var mode: SessionApprovalMode

    public init(mode: SessionApprovalMode) {
        self.mode = mode
    }
}
