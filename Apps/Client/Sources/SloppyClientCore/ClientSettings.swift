import Foundation
import Observation

@Observable
@MainActor
public final class ClientSettings {
    private enum Keys {
        static let serverHost = "client_server_host"
        static let serverPort = "client_server_port"
        static let accentColorHex = "client_accent_color_hex"
    }

    public var serverHost: String {
        didSet { UserDefaults.standard.set(serverHost, forKey: Keys.serverHost) }
    }

    public var serverPort: Int {
        didSet { UserDefaults.standard.set(serverPort, forKey: Keys.serverPort) }
    }

    public var accentColorHex: String {
        didSet { UserDefaults.standard.set(accentColorHex, forKey: Keys.accentColorHex) }
    }

    public var baseURL: URL {
        URL(string: "http://\(serverHost):\(serverPort)") ?? URL(string: "http://localhost:25101")!
    }

    public init() {
        let defaults = UserDefaults.standard
        serverHost = defaults.string(forKey: Keys.serverHost) ?? "localhost"
        serverPort = defaults.integer(forKey: Keys.serverPort).nonZero ?? 25101
        accentColorHex = defaults.string(forKey: Keys.accentColorHex) ?? "#FF2D6F"
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
