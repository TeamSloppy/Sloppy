import Foundation
import SloppyRemoteProtocol
import Testing
@testable import SloppyClientCore

@Suite("Console remote request deadlines")
struct ConsoleRemoteRequestTests {
    @Test func deadlineIncludesConnectionPreparation() async throws {
        let client = ConsoleRemoteClientRegistry(requestTransport: { _, request in
            try await Task.sleep(for: .seconds(5))
            return RemoteCoreResponse(requestID: request.requestID, status: 200, body: Data())
        })
        do {
            _ = try await client.request(hostID: UUID(), method: "GET", path: "/health", body: nil, timeout: 0.02)
            Issue.record("An unavailable connection must respect the health-check deadline")
        } catch let error as URLError {
            #expect(error.code == .timedOut)
        }
    }

    @Test func cancellationDoesNotWaitForTheResponseDeadline() async throws {
        let started = AsyncStream<Void>.makeStream()
        let client = ConsoleRemoteClientRegistry(requestTransport: { _, request in
            started.continuation.yield(())
            try await Task.sleep(for: .seconds(5))
            return RemoteCoreResponse(requestID: request.requestID, status: 200, body: Data())
        })
        let request = Task { try await client.request(hostID: UUID(), method: "GET", path: "/health", body: nil) }
        for await _ in started.stream { break }
        request.cancel()
        await #expect(throws: CancellationError.self) { try await request.value }
    }

    @Test func expiredRequestDoesNotFailTheNextRequest() async throws {
        let client = ConsoleRemoteClientRegistry(requestTransport: { _, request in
            if request.path == "/slow" { try await Task.sleep(for: .seconds(5)) }
            return RemoteCoreResponse(requestID: request.requestID, status: 200, body: Data(request.path.utf8))
        })
        await #expect(throws: URLError.self) {
            try await client.request(hostID: UUID(), method: "GET", path: "/slow", body: nil, timeout: 0.02)
        }
        let response = try await client.request(hostID: UUID(), method: "GET", path: "/health", body: nil)
        #expect(response.status == 200)
        #expect(response.body == Data("/health".utf8))
    }
}
