import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging
import Observation

@Observable
@MainActor
public final class ConnectionMonitor {
    public private(set) var state: ConnectionState = .disconnected
    public private(set) var checkedURL: URL?
    public private(set) var lastFailureMessage: String?

    private var baseURL: URL
    private var checkTask: Task<Void, Never>?
    private let logger: Logger
    private let checkInterval: TimeInterval = 10
    private var healthCheckAttempt = 0

    public init(
        baseURL: URL,
        logger: Logger = Logger(label: "sloppy.connection-monitor")
    ) {
        self.baseURL = baseURL
        self.logger = logger
    }

    public func start(baseURL: URL) {
        self.baseURL = baseURL
        stop()
        state = .reconnecting
        checkedURL = baseURL.appendingPathComponent("health")
        lastFailureMessage = nil
        healthCheckAttempt = 0
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

    private func checkHealth() async -> Bool {
        let url = baseURL.appendingPathComponent("health")
        checkedURL = url
        healthCheckAttempt += 1
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                let ok = (200..<300).contains(http.statusCode)
                lastFailureMessage = ok ? nil : "HTTP \(http.statusCode)"
                if ok {
                } else {
                    logger.warning("Health check attempt \(healthCheckAttempt) failed: HTTP \(http.statusCode)")
                }
                return ok
            }
            lastFailureMessage = "Invalid HTTP response"
            logger.warning("Health check attempt \(healthCheckAttempt) failed: invalid HTTP response")
            return false
        } catch {
            let nsError = error as NSError
            lastFailureMessage = "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
            logger.warning("Health check attempt \(healthCheckAttempt) failed: \(nsError.domain) \(nsError.code): \(nsError.localizedDescription)")
            return false
        }
    }
}
