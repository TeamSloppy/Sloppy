import Foundation
import Network

public actor LocalNetworkScanner {
    public static let sloppyPort: UInt16 = 25101

    public init() {}

    /// Scans the local /24 subnet for Sloppy servers on port 25101.
    /// Yields discovered servers as they are found.
    public func scan() -> AsyncStream<SavedServer> {
        AsyncStream { continuation in
            Task {
                guard let subnetBase = Self.localSubnetBase() else {
                    continuation.finish()
                    return
                }

                await withTaskGroup(of: SavedServer?.self) { group in
                    for i in 1...254 {
                        let host = "\(subnetBase).\(i)"
                        group.addTask {
                            await Self.probe(host: host)
                        }
                    }

                    for await result in group {
                        if let server = result {
                            continuation.yield(server)
                        }
                    }
                }

                continuation.finish()
            }
        }
    }

    private static func probe(host: String) async -> SavedServer? {
        let connected = await tcpConnect(host: host, port: sloppyPort, timeout: 1.5)
        guard connected else { return nil }

        let confirmed = await confirmSloppyServer(host: host, port: sloppyPort)
        guard confirmed else { return nil }

        return SavedServer(
            label: "Sloppy @ \(host)",
            host: host,
            port: Int(sloppyPort),
            isAutoDiscovered: true
        )
    }

    private static func tcpConnect(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )

        let once = OnceFlag()

        return await withCheckedContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.tryFire {
                        connection.cancel()
                        continuation.resume(returning: true)
                    }
                case .failed, .cancelled:
                    once.tryFire {
                        continuation.resume(returning: false)
                    }
                default:
                    break
                }
            }
            connection.start(queue: .global())

            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                once.tryFire {
                    connection.cancel()
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private static func confirmSloppyServer(host: String, port: UInt16) async -> Bool {
        guard let url = URL(string: "http://\(host):\(port)/v1/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3

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

    /// Derives the local /24 subnet base (e.g. "192.168.1") from the device's primary IP.
    static func localSubnetBase() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var current = ifaddr
        while let addr = current {
            let flags = Int32(addr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp && !isLoopback,
               addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(
                    addr.pointee.ifa_addr,
                    socklen_t(addr.pointee.ifa_addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                let ip = hostname.prefix(while: { $0 != 0 }).map { Character(UnicodeScalar(UInt8(bitPattern: $0))) }
                let ipStr = String(ip)
                let parts = ipStr.split(separator: ".")
                if parts.count == 4 {
                    return "\(parts[0]).\(parts[1]).\(parts[2])"
                }
            }
            current = addr.pointee.ifa_next
        }
        return nil
    }
}

/// Thread-safe flag that ensures an action is only executed once.
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func tryFire(_ action: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !fired else { return }
        fired = true
        action()
    }
}
