import Foundation
import AgentRuntime
import Protocols
import Testing
@testable import sloppy

@Suite("Strict completion evidence")
struct StrictEvidencePolicyTests {
    @Test(arguments: [1, 2])
    func staleEvidenceIsRejectedOnlyByTheExplicitVersion(version: Int) {
        let evidence = VerificationEvidence(id: "verification-1", kind: .test, tool: "runtime.exec", command: "swift test",
            arguments: [], cwd: "/workspace", exitCode: 0, observedAt: Date(), workScopeRevision: 1, sourceCallID: "original-call")
        let request = ToolInvocationRequest(tool: "session.complete", arguments: ["status": .string("completed"),
            "summary": .string("Implemented"), "verificationEvidenceIds": .array([.string(evidence.id)])])
        let decision = SessionCompletionPolicy.evaluate(request: request, mode: .build, evidence: [evidence],
            blockedCompletionRejection: nil, evidencePolicyVersion: version, workScopeRevision: 2)
        switch decision {
        case .accepted: #expect(version == 1)
        case .rejected(let result):
            #expect(version == 2)
            #expect(result.error?.code == "completion_verification_stale")
        }
    }
}
