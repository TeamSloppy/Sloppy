import Foundation
import PluginSDK
import Protocols

/// Turn completion decisions depend on protocol state, never on assistant phrasing.
enum AgentLoopCompletionPolicy {
    enum Decision {
        case finish
        case recover(RecoveryReason, Int, ModelStepPurpose, AgentRunInstruction)
    }

    static func afterEnd(_ response: ModelStepResponse, purpose: ModelStepPurpose,
                         config: NativeAgentLoopConfig, hadTools: Bool) -> Decision {
        if config.requiresExplicitCompletion == true {
            return .recover(.missingCompletion, config.completionRecoveryLimit ?? 3, .completionRecovery,
                .init(kind: .completionRecovery, text:
                    "The turn has no accepted completion record. Continue any necessary work and verification using the remaining authorized tools, then call the declared completion finalizer with an accurate disposition. If blocked or waiting for input, report that through the finalizer. Do not repeat work already recorded in the journal."))
        }
        if response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .recover(.emptyFinal, hadTools ? 1 : 2, .finalAnswer,
                .init(kind: .finalAnswer, text:
                    "Provide the final user-facing answer from the settled results already in the journal. This request has no tools. Do not repeat any tool calls or claim work beyond the recorded results."))
        }
        return .finish
    }
}
