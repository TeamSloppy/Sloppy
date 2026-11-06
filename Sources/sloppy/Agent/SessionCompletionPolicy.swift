import Foundation
import AgentRuntime
import Protocols

/// Product policy is pure; the run owner applies an accepted record and persists its result.
enum SessionCompletionPolicy {
    enum Decision {
        case accepted(RunCompletion)
        case rejected(ToolInvocationResult)
    }

    static func evaluate(
        request: ToolInvocationRequest,
        mode: AgentChatMode,
        evidence: [VerificationEvidence],
        blockedCompletionRejection: String?,
        evidencePolicyVersion: Int = 1,
        workScopeRevision: Int? = nil
    ) -> Decision {
        let summary = request.arguments["summary"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawStatus = request.arguments["status"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let disposition = RunCompletionDisposition(rawValue: rawStatus) else {
            return reject("invalid_completion_status", "`status` must be completed, blocked, or waiting_input.")
        }
        guard !summary.isEmpty else {
            return reject("completion_summary_required", "`summary` must describe the completed work, blocker, or requested input.")
        }

        let verification = strings("verification", in: request)
        let requestedIDs = strings("verificationEvidenceIds", in: request)
        let limitations = strings("limitations", in: request)
        let evidenceByID = Dictionary(evidence.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let missingIDs = requestedIDs.filter { evidenceByID[$0] == nil }
        guard missingIDs.isEmpty else {
            return reject("completion_verification_not_found", "Verification evidence must reference successful tool results from the current turn. Unknown IDs: \(missingIDs.joined(separator: ", ")).")
        }
        let resolved = requestedIDs.compactMap { evidenceByID[$0] }
        if disposition == .completed, evidencePolicyVersion == 2,
           resolved.contains(where: { $0.workScopeRevision == nil || $0.workScopeRevision != workScopeRevision }) {
            return reject("completion_verification_stale", "The work changed after this verification. Run the applicable check again and use its new evidence ID.")
        }
        if disposition == .completed, mode == .build || mode == .debug,
           !resolved.contains(where: { sufficient($0, for: mode) }) {
            return reject("completion_verification_required", "Completed Build and Debug turns require current-turn evidence from a successful build, test, or run: runtime.exec/runtime.process, or an MCP tool the server marks as verification (its result carries `verificationEvidence.id`). Debug also accepts screenshot evidence.")
        }
        if disposition == .blocked {
            if let blockedCompletionRejection {
                return reject("completion_blocked_prematurely", blockedCompletionRejection)
            }
            if limitations.isEmpty {
                return reject("completion_limitations_required", "Blocked completion requires at least one concrete limitation or blocker.")
            }
        }
        return .accepted(RunCompletion(disposition: disposition, summary: summary, verification: verification,
            verificationEvidence: resolved, limitations: limitations))
    }

    private static func strings(_ key: String, in request: ToolInvocationRequest) -> [String] {
        request.arguments[key]?.asArray?.compactMap(\.asString)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? []
    }

    private static func sufficient(_ evidence: VerificationEvidence, for mode: AgentChatMode) -> Bool {
        switch mode {
        case .build: return evidence.kind == .build || evidence.kind == .test || evidence.kind == .run
        case .debug: return evidence.kind == .build || evidence.kind == .test || evidence.kind == .run || evidence.kind == .screenshot
        default: return true
        }
    }

    private static func reject(_ code: String, _ message: String) -> Decision {
        .rejected(ToolInvocationResult(tool: SessionCompleteTool.toolName, ok: false,
            error: ToolErrorPayload(code: code, message: message, retryable: true)))
    }
}
