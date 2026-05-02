import Foundation
import Protocols

enum TelegramToolApprovalCallback: Equatable {
    case approve(String)
    case reject(String)
    case unknown
}

enum TelegramToolApproval {
    static func callbackApprove(id: String) -> String {
        "TA|A|\(id)"
    }

    static func callbackReject(id: String) -> String {
        "TA|R|\(id)"
    }

    static func parseCallback(_ data: String) -> TelegramToolApprovalCallback {
        let parts = data.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == "TA" else {
            return .unknown
        }
        switch parts[1] {
        case "A":
            return parts[2].isEmpty ? .unknown : .approve(parts[2])
        case "R":
            return parts[2].isEmpty ? .unknown : .reject(parts[2])
        default:
            return .unknown
        }
    }

    static func keyboard(id: String) -> [[[String: String]]] {
        [[
            ["text": "Approve", "callback_data": callbackApprove(id: id)],
            ["text": "Reject", "callback_data": callbackReject(id: id)]
        ]]
    }

    static func pendingText(_ approval: ToolApprovalRecord) -> String {
        var lines = [
            "Tool approval required",
            "",
            "Tool: \(approval.tool)"
        ]
        if let reason = approval.reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            lines.append("Reason: \(reason)")
        }
        lines.append("Approval ID: \(approval.id)")
        return lines.joined(separator: "\n")
    }

    static func resolvedText(_ approval: ToolApprovalRecord) -> String {
        let status: String = switch approval.status {
        case .pending:
            "pending"
        case .approved:
            "approved"
        case .rejected:
            "rejected"
        case .timedOut:
            "expired"
        }
        return "Tool approval \(status)\n\nTool: \(approval.tool)\nApproval ID: \(approval.id)"
    }
}
