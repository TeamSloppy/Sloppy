import Foundation
import SloppyRemoteProtocol
import Testing
@testable import SloppyClientCore

@Suite("Managed session socket recovery")
struct SessionSocketRecoveryTests {
    @Test func unavailableRelayDoesNotBlockTheEventConsumer() async throws {
        let manager = SessionSocketManager(
            endpoint: .managed(relayURL: URL(string: "https://relay.example")!, targetDeviceID: UUID()),
            agentId: "agent", sessionId: "session",
            managedStreamProvider: { _, _ in throw URLError(.notConnectedToInternet) },
            retrySleep: { _ in throw CancellationError() }
        )
        let updates = await manager.connect()
        var iterator = updates.makeAsyncIterator()
        let update = await iterator.next()
        #expect(update?.kind == .sessionReady)
        await manager.disconnect()
    }

    @Test func successfulDataResetsTheDelayAfterRepeatedFailures() async throws {
        let server = SessionRecoveryServer()
        let manager = SessionSocketManager(
            endpoint: .managed(relayURL: URL(string: "https://relay.example")!, targetDeviceID: UUID()),
            agentId: "agent", sessionId: "session",
            managedStreamProvider: { _, _ in try await server.open() },
            retrySleep: { try await server.wait($0) }
        )
        let updates = await manager.connect()
        for await update in updates where update.cursor == 42 { break }
        await server.finished
        #expect(await server.delays == [.seconds(1), .seconds(2), .seconds(1)])
        await manager.disconnect()
    }
}

private actor SessionRecoveryServer {
    private var attempts = 0
    private(set) var delays: [Duration] = []
    private let completion = AsyncStream<Void>.makeStream()

    var finished: Void {
        get async { for await _ in completion.stream { return } }
    }

    func open() throws -> AsyncStream<RemoteStreamFrame> {
        attempts += 1
        if attempts <= 2 { throw URLError(.networkConnectionLost) }
        return AsyncStream { continuation in
            continuation.yield(RemoteStreamFrame(streamID: UUID(), action: .data,
                data: Data("{\"kind\":\"heartbeat\",\"cursor\":42}".utf8)))
            continuation.finish()
        }
    }

    func wait(_ delay: Duration) throws {
        delays.append(delay)
        if delays.count == 3 {
            completion.continuation.yield(())
            completion.continuation.finish()
            throw CancellationError()
        }
    }
}
