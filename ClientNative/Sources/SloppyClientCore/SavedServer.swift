import Foundation

public struct SavedServer: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var scheme: String
    public var host: String
    public var port: Int
    public var isAutoDiscovered: Bool
    public var tlsFingerprint: String?

    public init(
        id: String = UUID().uuidString,
        label: String,
        scheme: String = "http",
        host: String,
        port: Int,
        isAutoDiscovered: Bool = false,
        tlsFingerprint: String? = nil
    ) {
        self.id = id
        self.label = label
        self.scheme = scheme == "https" ? "https" : "http"
        self.host = host
        self.port = port
        self.isAutoDiscovered = isAutoDiscovered
        self.tlsFingerprint = tlsFingerprint
    }

    public var baseURL: URL {
        ServerAddress(scheme: scheme, host: host, port: port).baseURL
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, scheme, host, port, isAutoDiscovered, tlsFingerprint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            label: try container.decode(String.self, forKey: .label),
            scheme: try container.decodeIfPresent(String.self, forKey: .scheme) ?? "http",
            host: try container.decode(String.self, forKey: .host),
            port: try container.decode(Int.self, forKey: .port),
            isAutoDiscovered: try container.decode(Bool.self, forKey: .isAutoDiscovered),
            tlsFingerprint: try container.decodeIfPresent(String.self, forKey: .tlsFingerprint)
        )
    }
}

public enum ConnectionState: Equatable, Sendable {
    case connected
    case disconnected
    case reconnecting
}
