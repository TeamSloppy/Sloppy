import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

struct NetworkIPv4Candidate: Equatable, Sendable {
    let interfaceName: String
    let address: String
}

struct ServerDisplayEndpoints: Equatable, Sendable {
    let bindAddress: String
    let localAPIURL: String?
    let lanAPIURL: String?
    let dashboardAPIBase: String
    let preferredAPIBase: String
    let preferredDashboardURL: String?
}

enum NetworkAddressResolver {
    static func enumerateIPv4Candidates() -> [NetworkIPv4Candidate] {
        var rawPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&rawPointer) == 0, let first = rawPointer else {
            return []
        }
        defer { freeifaddrs(rawPointer) }

        var candidates: [NetworkIPv4Candidate] = []
        var current: UnsafeMutablePointer<ifaddrs>? = first

        while let pointer = current {
            let interface = pointer.pointee
            defer { current = interface.ifa_next }

            guard let addressPointer = interface.ifa_addr else {
                continue
            }

            let flags = Int32(interface.ifa_flags)
            guard (flags & Int32(IFF_UP)) != 0 else {
                continue
            }

            let family = Int32(addressPointer.pointee.sa_family)
            guard family == AF_INET else {
                continue
            }

            let interfaceName = String(cString: interface.ifa_name)
            if (flags & Int32(IFF_LOOPBACK)) != 0 {
                continue
            }

            var address = addressPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
                pointer.pointee.sin_addr
            }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
                continue
            }

            let host = String(decoding: buffer.prefix { $0 != 0 }.map(UInt8.init), as: UTF8.self)
            guard !isLoopbackIPv4(host), !isLinkLocalIPv4(host) else {
                continue
            }

            candidates.append(.init(interfaceName: interfaceName, address: host))
        }

        return candidates
    }

    static func resolvePrimaryLANIPv4() -> String? {
        resolvePrimaryLANIPv4(from: enumerateIPv4Candidates())
    }

    static func resolvePrimaryLANIPv4(from candidates: [NetworkIPv4Candidate]) -> String? {
        let sorted = candidates
            .filter { !$0.address.isEmpty && !isLoopbackIPv4($0.address) && !isLinkLocalIPv4($0.address) }
            .sorted { lhs, rhs in
                let lhsTuple = sortTuple(for: lhs)
                let rhsTuple = sortTuple(for: rhs)
                if lhsTuple != rhsTuple {
                    return lhsTuple < rhsTuple
                }
                return lhs.address < rhs.address
            }
        return sorted.first?.address
    }

    static func makeDisplayEndpoints(
        bindHost: String,
        apiPort: Int,
        dashboardPort: Int? = nil,
        lanIPv4: String? = nil
    ) -> ServerDisplayEndpoints {
        let normalizedBindHost = bindHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let bindAddress = "\(normalizedBindHost):\(apiPort)"

        let localHost: String? = {
            if isWildcardHost(normalizedBindHost) { return "127.0.0.1" }
            if isLocalOnlyHost(normalizedBindHost) { return "127.0.0.1" }
            return nil
        }()

        let lanHost: String? = {
            if isWildcardHost(normalizedBindHost) {
                return lanIPv4
            }
            if isLocalOnlyHost(normalizedBindHost) {
                return nil
            }
            return normalizedBindHost.isEmpty ? lanIPv4 : normalizedBindHost
        }()

        let preferredHost: String = {
            if let lanHost, !lanHost.isEmpty { return lanHost }
            if let localHost, !localHost.isEmpty { return localHost }
            return "127.0.0.1"
        }()

        let localAPIURL = localHost.map { "http://\($0):\(apiPort)" }
        let lanAPIURL = lanHost.map { "http://\($0):\(apiPort)" }
        let preferredAPIBase = "http://\(preferredHost):\(apiPort)"

        return .init(
            bindAddress: bindAddress,
            localAPIURL: localAPIURL,
            lanAPIURL: lanAPIURL,
            dashboardAPIBase: preferredAPIBase,
            preferredAPIBase: preferredAPIBase,
            preferredDashboardURL: dashboardPort.map { "http://\(preferredHost):\($0)" }
        )
    }

    private static func sortTuple(for candidate: NetworkIPv4Candidate) -> (Int, Int, String) {
        (
            isPrivateIPv4(candidate.address) ? 0 : 1,
            interfacePriority(candidate.interfaceName),
            candidate.interfaceName
        )
    }

    private static func interfacePriority(_ interfaceName: String) -> Int {
        let lowered = interfaceName.lowercased()
        if lowered.hasPrefix("en") { return 0 }
        if lowered.hasPrefix("eth") { return 1 }
        if lowered.hasPrefix("wlan") { return 2 }
        if lowered.hasPrefix("bridge") { return 3 }
        return 4
    }

    private static func isWildcardHost(_ host: String) -> Bool {
        let lowered = host.lowercased()
        return lowered.isEmpty || lowered == "0.0.0.0" || lowered == "::" || lowered == "*"
    }

    private static func isLocalOnlyHost(_ host: String) -> Bool {
        let lowered = host.lowercased()
        return lowered == "localhost" || lowered == "::1" || isLoopbackIPv4(lowered)
    }

    private static func isLoopbackIPv4(_ host: String) -> Bool {
        host == "127.0.0.1" || host.hasPrefix("127.")
    }

    private static func isLinkLocalIPv4(_ host: String) -> Bool {
        host.hasPrefix("169.254.")
    }

    private static func isPrivateIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else {
            return false
        }

        if parts[0] == 10 { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        return false
    }
}
