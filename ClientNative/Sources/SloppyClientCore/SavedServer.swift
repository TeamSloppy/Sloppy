import Foundation

public struct SavedServer: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var host: String
    public var port: Int
    public var isAutoDiscovered: Bool

    public init(id: String = UUID().uuidString, label: String, host: String, port: Int, isAutoDiscovered: Bool = false) {
        self.id = id
        self.label = label
        self.host = host
        self.port = port
        self.isAutoDiscovered = isAutoDiscovered
    }

    public var baseURL: URL {
        ServerAddress.parse(host: host, port: String(port))?.baseURL
            ?? ServerAddress(host: "localhost").baseURL
    }
}

public enum ConnectionState: Equatable, Sendable {
    case connected
    case disconnected
    case reconnecting
}
