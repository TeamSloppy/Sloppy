import Foundation
import Observation

@Observable
@MainActor
public final class ClientSettings {
    private enum Keys {
        static let serverHost = "client_server_host"
        static let serverPort = "client_server_port"
        static let accentColorHex = "client_accent_color_hex"
        static let windowCloseBehavior = "client_window_close_behavior"
        static let lastAgentId = "client_last_agent_id"
        static let lastSessionId = "client_last_session_id"
        static let savedServers = "client_saved_servers"
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

    public var windowCloseBehavior: ClientWindowCloseBehavior {
        didSet { UserDefaults.standard.set(windowCloseBehavior.rawValue, forKey: Keys.windowCloseBehavior) }
    }

    public var lastAgentId: String? {
        didSet { UserDefaults.standard.set(lastAgentId, forKey: Keys.lastAgentId) }
    }

    public var lastSessionId: String? {
        didSet { UserDefaults.standard.set(lastSessionId, forKey: Keys.lastSessionId) }
    }

    public var savedServers: [SavedServer] {
        didSet {
            if let data = try? JSONEncoder().encode(savedServers) {
                UserDefaults.standard.set(data, forKey: Keys.savedServers)
            }
        }
    }

    public var baseURL: URL {
        URL(string: "http://\(serverHost):\(serverPort)") ?? URL(string: "http://localhost:25101")!
    }

    public var activeServer: SavedServer? {
        savedServers.first { $0.host == serverHost && $0.port == serverPort }
    }

    public init() {
        let defaults = UserDefaults.standard
        serverHost = defaults.string(forKey: Keys.serverHost) ?? "localhost"
        serverPort = defaults.integer(forKey: Keys.serverPort).nonZero ?? 25101
        accentColorHex = defaults.string(forKey: Keys.accentColorHex) ?? "#FF2D6F"
        windowCloseBehavior = defaults
            .string(forKey: Keys.windowCloseBehavior)
            .flatMap(ClientWindowCloseBehavior.init(rawValue:)) ?? .keepProcess
        lastAgentId = defaults.string(forKey: Keys.lastAgentId)
        lastSessionId = defaults.string(forKey: Keys.lastSessionId)

        if let data = defaults.data(forKey: Keys.savedServers),
           let servers = try? JSONDecoder().decode([SavedServer].self, from: data) {
            savedServers = servers
        } else {
            savedServers = []
        }
    }

    public func useServer(_ server: SavedServer) {
        serverHost = server.host
        serverPort = server.port
        if !savedServers.contains(where: { $0.id == server.id }) {
            savedServers.append(server)
        }
    }
}

public enum ClientWindowCloseBehavior: String, Codable, Sendable, Equatable, CaseIterable {
    case keepProcess = "keep_process"
    case quitOnLastWindow = "quit_on_last_window"
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
