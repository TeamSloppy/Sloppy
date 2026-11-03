import Foundation
import Testing
@testable import SloppyClientCore

@MainActor
struct BackendHTTPClientCancellationTests {
    @Test("a cancelled request never creates a task in an invalidated URLSession")
    func cancelledRequestAfterSessionInvalidation() async throws {
        let session = URLSession(configuration: .ephemeral)
        let http = BackendHTTPClient(baseURL: try #require(URL(string: "https://cancelled-request.invalid")),
                                     session: session, authSessionStore: AuthSessionStore(persistence: .memory))
        // Queue on the main actor so teardown wins before request preparation starts.
        let request = Task { try await http.getData("/v1/config/chat-approval-default") }
        request.cancel()
        session.invalidateAndCancel()
        do {
            _ = try await request.value
            Issue.record("A cancelled request must not succeed")
        } catch {
            #expect(error is CancellationError)
        }
    }
}
