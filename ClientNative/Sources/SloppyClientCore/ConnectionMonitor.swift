import Foundation
import Logging
import Observation

@Observable
@MainActor
public final class ConnectionMonitor {
    public private(set) var state: ConnectionState = .disconnected
    public private(set) var checkedURL: URL?
    public private(set) var lastFailureMessage: String?

    private var baseURL: URL
    private var endpoint: SloppyInstanceEndpoint
    private var checkTask: Task<Void, Never>?
    private let logger: Logger
    private let checkInterval: TimeInterval = 10
    private var healthCheckAttempt = 0
    private var consecutiveTransportFailures = 0
    private var monitorID = UUID()
    private let healthCheck: @Sendable (SloppyInstanceEndpoint) async -> HealthCheckResult
    private let recoverTransport: @Sendable (SloppyInstanceEndpoint) async -> Bool

    public init(
        baseURL: URL,
        logger: Logger = Logger(label: "sloppy.connection-monitor")
    ) {
        self.baseURL = baseURL
        self.endpoint = .direct(baseURL: baseURL)
        self.logger = logger
        self.healthCheck = { endpoint in
            // A managed check can include proof, Relay authentication, a fresh
            // WebSocket and peer TLS before the Core request itself is sent.
            let timeout: TimeInterval = if case .managed = endpoint { 10 } else { 5 }
            return await HealthService(http: BackendHTTPClient(endpoint: endpoint)).check(timeout: timeout)
        }
        self.recoverTransport = { endpoint in
            guard case .managed(_, let hostID) = endpoint else { return false }
            return await ConsoleRemoteClientRegistry.shared.recoverAfterHealthFailure(hostID: hostID)
        }
    }

    init(
        endpoint: SloppyInstanceEndpoint,
        healthCheck: @escaping @Sendable (SloppyInstanceEndpoint) async -> HealthCheckResult,
        recoverTransport: @escaping @Sendable (SloppyInstanceEndpoint) async -> Bool
    ) {
        self.baseURL = endpoint.coordinatorBaseURL
        self.endpoint = endpoint
        self.logger = Logger(label: "sloppy.connection-monitor")
        self.healthCheck = healthCheck
        self.recoverTransport = recoverTransport
    }

    public func start(baseURL: URL) {
        start(endpoint: .direct(baseURL: baseURL))
    }

    public func start(endpoint: SloppyInstanceEndpoint) {
        self.endpoint = endpoint
        self.baseURL = endpoint.coordinatorBaseURL
        stop()
        state = .reconnecting
        checkedURL = baseURL.appendingPathComponent("health")
        lastFailureMessage = nil
        healthCheckAttempt = 0
        consecutiveTransportFailures = 0
        logger.info("Starting connection monitor for \(baseURL.absoluteString)")
        checkTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    public func stop() {
        if checkTask != nil {
            logger.info("Stopping connection monitor for \(baseURL.absoluteString)")
        }
        checkTask?.cancel()
        checkTask = nil
        monitorID = UUID()
    }

    public func markDisconnected() {
        state = .disconnected
    }

    public func markReconnecting() {
        state = .reconnecting
    }

    private func runLoop() async {
        while !Task.isCancelled {
            let reachable = await checkHealth()
            if !Task.isCancelled {
                state = reachable ? .connected : .disconnected
            }
            try? await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
        }
    }

    func checkHealth() async -> Bool {
        checkedURL = baseURL.appendingPathComponent("health")
        healthCheckAttempt += 1

        let currentID = monitorID
        let checkedEndpoint = endpoint
        let result = await healthCheck(checkedEndpoint)
        guard !Task.isCancelled, monitorID == currentID else { return false }
        lastFailureMessage = result.failureMessage

        if !result.isHealthy {
            logger.warning("Health check attempt \(healthCheckAttempt) failed: \(result.failureMessage ?? "unknown error")")
        }

        consecutiveTransportFailures = !result.isHealthy && result.requiresTransportReconnect
            ? consecutiveTransportFailures + 1 : 0
        if case .managed = checkedEndpoint, consecutiveTransportFailures >= 2 {
            // The host may have reconnected its Relay socket and lost the peer's
            // TLS state. A fresh transport starts a new handshake instead of
            // repeatedly sending records for a session the host no longer has.
            consecutiveTransportFailures = 0
            if await recoverTransport(checkedEndpoint) {
                logger.info("connection.health.transport-reset")
            }
        }

        return result.isHealthy
    }
}
