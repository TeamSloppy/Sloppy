import Foundation
import Testing
@testable import SloppyClientCore

@Suite("Connection monitor transport recovery")
struct ConnectionMonitorRecoveryTests {
    @Test @MainActor func repeatedTimeoutsReplaceTheStaleTransportBeforeTheNextHealthCheck() async {
        let peer = RecoveryPeer()
        let monitor = ConnectionMonitor(endpoint: managedEndpoint, healthCheck: { _ in
            await peer.check()
        }, recoverTransport: { _ in
            await peer.reconnect()
            return true
        })

        #expect(await monitor.checkHealth() == false)
        #expect(await peer.recoveries == 0)
        #expect(await monitor.checkHealth() == false)
        #expect(await peer.recoveries == 1)
        #expect(await monitor.checkHealth())
        #expect(monitor.lastFailureMessage == nil)
    }

    @Test @MainActor func successfulHealthCheckBreaksTheFailureStreak() async {
        let peer = RecoveryPeer(results: [.timeout, .healthy, .timeout])
        let monitor = ConnectionMonitor(endpoint: managedEndpoint, healthCheck: { _ in
            await peer.check()
        }, recoverTransport: { _ in
            await peer.reconnect()
            return true
        })

        for _ in 0..<3 { _ = await monitor.checkHealth() }
        #expect(await peer.recoveries == 0)
    }

    @Test @MainActor func httpFailureDoesNotResetAnAuthenticatedTransport() async {
        let peer = RecoveryPeer(results: [
            HealthCheckResult(isHealthy: false, failureMessage: "HTTP 401"),
            HealthCheckResult(isHealthy: false, failureMessage: "HTTP 503"),
        ])
        let monitor = ConnectionMonitor(endpoint: managedEndpoint, healthCheck: { _ in
            await peer.check()
        }, recoverTransport: { _ in
            await peer.reconnect()
            return true
        })

        _ = await monitor.checkHealth()
        _ = await monitor.checkHealth()
        #expect(await peer.recoveries == 0)
    }

    @Test @MainActor func directConnectionNeverResetsTheConsoleTransport() async {
        let peer = RecoveryPeer()
        let monitor = ConnectionMonitor(endpoint: .direct(baseURL: managedEndpoint.coordinatorBaseURL), healthCheck: { _ in
            await peer.check()
        }, recoverTransport: { _ in
            await peer.reconnect()
            return true
        })

        _ = await monitor.checkHealth()
        _ = await monitor.checkHealth()
        #expect(await peer.recoveries == 0)
    }

    @Test @MainActor func stoppingAnInFlightHealthCheckPreventsRecovery() async {
        let started = AsyncStream<Void>.makeStream()
        let finish = AsyncStream<Void>.makeStream()
        let peer = RecoveryPeer()
        let monitor = ConnectionMonitor(endpoint: managedEndpoint, healthCheck: { _ in
            started.continuation.yield(())
            for await _ in finish.stream { break }
            return .timeout
        }, recoverTransport: { _ in
            await peer.reconnect()
            return true
        })

        let task = Task { await monitor.checkHealth() }
        for await _ in started.stream { break }
        monitor.stop()
        finish.continuation.yield(())
        #expect(await task.value == false)
        #expect(monitor.lastFailureMessage == nil)
        #expect(await peer.recoveries == 0)
    }

    @Test(arguments: [URLError.Code.timedOut, .networkConnectionLost, .cannotConnectToHost, .cancelled, .serverCertificateUntrusted])
    func healthServiceClassifiesTheErrorWithoutMatchingItsMessage(_ code: URLError.Code) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HealthFailureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let url = try #require(URL(string: "https://failure\(-code.rawValue).test"))
        let http = BackendHTTPClient(baseURL: url, session: session, authSessionStore: AuthSessionStore(persistence: .memory))
        let result = await HealthService(http: http).check()

        #expect(!result.isHealthy)
        #expect(result.requiresTransportReconnect == [URLError.Code.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(code))
    }

    private var managedEndpoint: SloppyInstanceEndpoint {
        .managed(relayURL: URL(string: "https://relay.sloppy.test")!, targetDeviceID: UUID())
    }
}

private extension HealthCheckResult {
    static var timeout: Self { .init(isHealthy: false, failureMessage: "timeout", requiresTransportReconnect: true) }
    static var healthy: Self { .init(isHealthy: true) }
}

private actor RecoveryPeer {
    private var results: [HealthCheckResult]
    private(set) var recoveries = 0

    init(results: [HealthCheckResult] = [.timeout, .timeout]) { self.results = results }
    func check() -> HealthCheckResult { results.isEmpty ? .healthy : results.removeFirst() }
    func reconnect() { recoveries += 1; results = [.healthy] }
}

private final class HealthFailureURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let rawCode = request.url?.host?.split(separator: ".").first.flatMap { Int($0.dropFirst(7)) }.map { -$0 } ?? URLError.timedOut.rawValue
        client?.urlProtocol(self, didFailWithError: URLError(URLError.Code(rawValue: rawCode)))
    }
    override func stopLoading() {}
}
