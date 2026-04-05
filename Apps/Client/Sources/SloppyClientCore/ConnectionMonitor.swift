import Foundation
import Observation

@Observable
@MainActor
public final class ConnectionMonitor {
    public private(set) var state: ConnectionState = .disconnected

    private var baseURL: URL
    private var checkTask: Task<Void, Never>?
    private let checkInterval: TimeInterval = 10

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    public func start(baseURL: URL) {
        self.baseURL = baseURL
        stop()
        state = .reconnecting
        checkTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    public func stop() {
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
        let url = baseURL.appendingPathComponent("/health")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                return (200..<300).contains(http.statusCode)
            }
            return false
        } catch {
            return false
        }
    }
}
