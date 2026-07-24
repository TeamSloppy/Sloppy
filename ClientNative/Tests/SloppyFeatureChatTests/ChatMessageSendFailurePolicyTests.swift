import Foundation
import Testing
import SloppyClientCore
@testable import SloppyFeatureChat

@Suite("Chat message send failure policy")
struct ChatMessageSendFailurePolicyTests {
    @Test("does not restore a draft after socket delivery replaced the optimistic message")
    func socketDeliveryDoesNotRestoreDraft() {
        let shouldRestore = ChatMessageSendFailurePolicy.shouldRestoreDraft(
            after: URLError(.networkConnectionLost),
            optimisticMessageIsPresent: false
        )

        #expect(!shouldRestore)
    }

    @Test("does not restore a draft when a successful response fails to decode")
    func decodingFailureDoesNotRestoreDraft() {
        let shouldRestore = ChatMessageSendFailurePolicy.shouldRestoreDraft(
            after: APIError.decodingFailed("Invalid response payload"),
            optimisticMessageIsPresent: true
        )

        #expect(!shouldRestore)
    }

    @Test("restores a draft when the server rejects an optimistic message")
    func rejectedMessageRestoresDraft() {
        let shouldRestore = ChatMessageSendFailurePolicy.shouldRestoreDraft(
            after: APIError.httpError(statusCode: 400, body: nil),
            optimisticMessageIsPresent: true
        )

        #expect(shouldRestore)
    }
}
