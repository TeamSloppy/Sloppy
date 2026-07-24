import Foundation

public struct ServerAddress: Equatable, Sendable {
    public var scheme: String
    public var host: String
    public var port: Int

    public init(scheme: String = "http", host: String, port: Int = 25101) {
        self.scheme = scheme == "https" ? "https" : "http"
        self.host = host
        self.port = port
    }

    public var baseURL: URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        return components.url ?? URL(string: "http://localhost:25101")!
    }

    public var isLoopback: Bool {
        Self.isLoopbackHost(host)
    }

    public static func isLoopbackHost(_ rawHost: String?) -> Bool {
        guard let host = rawHost?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !host.isEmpty else {
            return false
        }
        if host == "localhost" || host == "::1" || host == "[::1]" {
            return true
        }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ UInt8($0) != nil }) else {
            return false
        }
        return parts[0] == "127"
    }

    public static func parse(
        host rawHost: String,
        port rawPort: String? = nil,
        defaultPort: Int = 25101
    ) -> ServerAddress? {
        let hostInput = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hostInput.isEmpty else { return nil }

        let portInput = rawPort?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackPort = portInput.flatMap(Int.init) ?? defaultPort
        let addressInput = hostInput.contains("://") ? hostInput : "http://\(hostInput)"

        guard let components = URLComponents(string: addressInput),
              let host = components.host,
              !host.isEmpty
        else {
            return nil
        }

        return ServerAddress(
            scheme: components.scheme ?? "http",
            host: host,
            port: components.port ?? fallbackPort
        )
    }
}
