import Foundation

/// Application payloads handled by the client, scoped to one Core endpoint.
public struct ConnectionTrafficSnapshot: Sendable {
    public fileprivate(set) var sentBytes: Int64 = 0
    public fileprivate(set) var receivedBytes: Int64 = 0
    public fileprivate(set) var requestsInFlight = 0
    public fileprivate(set) var openEventStreams = 0
}

final class ConnectionTraffic: @unchecked Sendable {
    static let shared = ConnectionTraffic()

    private let lock = NSLock()
    private var snapshots: [String: ConnectionTrafficSnapshot] = [:]

    func snapshot(for endpoint: SloppyInstanceEndpoint) -> ConnectionTrafficSnapshot {
        lock.withLock { snapshots[endpoint.cacheNamespace] ?? .init() }
    }

    func update(
        _ endpoint: SloppyInstanceEndpoint,
        requests: Int = 0,
        streams: Int = 0,
        sent: Int = 0,
        received: Int = 0
    ) {
        lock.withLock {
            let key = endpoint.cacheNamespace
            var snapshot = snapshots[key] ?? .init()
            snapshot.requestsInFlight += requests
            snapshot.openEventStreams += streams
            snapshot.sentBytes += Int64(sent)
            snapshot.receivedBytes += Int64(received)
            snapshots[key] = snapshot
        }
    }
}
