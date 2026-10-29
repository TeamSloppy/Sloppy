import Foundation
import Observation

@Observable
@MainActor
public final class ClientSettings {
    private let defaults: UserDefaults
    private enum Keys {
        static let serverHost = "client_server_host"
        static let serverPort = "client_server_port"
        static let accentColorHex = "client_accent_color_hex"
        static let colorScheme = "client_color_scheme"
        static let windowCloseBehavior = "client_window_close_behavior"
        static let lastAgentId = "client_last_agent_id"
        static let lastSessionId = "client_last_session_id"
        static let pinnedSessionIds = "client_pinned_session_ids"
        static let savedServers = "client_saved_servers"
    }

    public var serverHost: String {
        didSet { defaults.set(serverHost, forKey: Keys.serverHost) }
    }

    public var serverPort: Int {
        didSet { defaults.set(serverPort, forKey: Keys.serverPort) }
    }

    public var accentColorHex: String {
        didSet { defaults.set(accentColorHex, forKey: Keys.accentColorHex) }
    }

    public var colorScheme: ClientColorScheme {
        didSet { defaults.set(colorScheme.rawValue, forKey: Keys.colorScheme) }
    }

    public var windowCloseBehavior: ClientWindowCloseBehavior {
        didSet { defaults.set(windowCloseBehavior.rawValue, forKey: Keys.windowCloseBehavior) }
    }

    public var lastAgentId: String? {
        didSet { defaults.set(lastAgentId, forKey: Keys.lastAgentId) }
    }

    public var lastSessionId: String? {
        didSet { defaults.set(lastSessionId, forKey: Keys.lastSessionId) }
    }

    public var pinnedSessionIds: Set<String> {
        didSet {
            defaults.set(Array(pinnedSessionIds).sorted(), forKey: Keys.pinnedSessionIds)
        }
    }

    public var savedServers: [SavedServer] {
        didSet {
            if let data = try? JSONEncoder().encode(savedServers) {
                defaults.set(data, forKey: Keys.savedServers)
            }
        }
    }

    public var baseURL: URL {
        ServerAddress.parse(host: serverHost, port: String(serverPort))?.baseURL
            ?? ServerAddress(host: "localhost").baseURL
    }

    public var activeServer: SavedServer? {
        savedServers.first { $0.host == serverHost && $0.port == serverPort }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        serverHost = defaults.string(forKey: Keys.serverHost) ?? "localhost"
        serverPort = defaults.integer(forKey: Keys.serverPort).nonZero ?? 25101
        accentColorHex = defaults.string(forKey: Keys.accentColorHex) ?? "#FF2D6F"
        colorScheme = defaults
            .string(forKey: Keys.colorScheme)
            .flatMap(ClientColorScheme.init(rawValue:)) ?? .dark
        windowCloseBehavior = defaults
            .string(forKey: Keys.windowCloseBehavior)
            .flatMap(ClientWindowCloseBehavior.init(rawValue:)) ?? .keepProcess
        lastAgentId = defaults.string(forKey: Keys.lastAgentId)
        lastSessionId = defaults.string(forKey: Keys.lastSessionId)
        pinnedSessionIds = Set(defaults.stringArray(forKey: Keys.pinnedSessionIds) ?? [])

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

    public func isSessionPinned(_ sessionId: String) -> Bool {
        pinnedSessionIds.contains(sessionId)
    }

    public func setSessionPinned(_ sessionId: String, isPinned: Bool) {
        if isPinned {
            pinnedSessionIds.insert(sessionId)
        } else {
            pinnedSessionIds.remove(sessionId)
        }
    }
}

public enum ClientColorScheme: String, Codable, Sendable, Equatable, CaseIterable {
    case light
    case dark
}

public enum ClientWindowCloseBehavior: String, Codable, Sendable, Equatable, CaseIterable {
    case keepProcess = "keep_process"
    case quitOnLastWindow = "quit_on_last_window"
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
