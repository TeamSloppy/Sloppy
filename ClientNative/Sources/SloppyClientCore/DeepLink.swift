import Foundation

public enum DeepLink: Equatable, Sendable {
    case connect(host: String, port: Int, label: String?)
    case open
    case project(id: String)
    case session(agentId: String, sessionId: String)
    case dictationToggle(agentId: String, sessionId: String)

    public static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme == "sloppy" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        switch url.host {
        case "connect":
            let items = components.queryItems ?? []
            guard let host = items.first(where: { $0.name == "host" })?.value, !host.isEmpty else { return nil }
            let portString = items.first(where: { $0.name == "port" })?.value
            guard let address = ServerAddress.parse(host: host, port: portString) else { return nil }
            let label = items.first(where: { $0.name == "label" })?.value
            return .connect(host: address.host, port: address.port, label: label)
        case "open":
            return .open
        case "project":
            guard let id = components.nonEmptyQueryValue(named: "id") else { return nil }
            return .project(id: id)
        case "session":
            guard let agentId = components.nonEmptyQueryValue(named: "agent"),
                  let sessionId = components.nonEmptyQueryValue(named: "id") else { return nil }
            return .session(agentId: agentId, sessionId: sessionId)
        case "dictation" where url.path == "/toggle":
            guard let agentId = components.nonEmptyQueryValue(named: "agent"),
                  let sessionId = components.nonEmptyQueryValue(named: "session") else { return nil }
            return .dictationToggle(agentId: agentId, sessionId: sessionId)
        default:
            return nil
        }
    }

    public var serverURL: URL? {
        switch self {
        case .connect(let host, let port, _):
            return ServerAddress(host: host, port: port).baseURL
        case .open, .project, .session, .dictationToggle:
            return nil
        }
    }

    public var savedServer: SavedServer? {
        switch self {
        case .connect(let host, let port, let label):
            return SavedServer(
                label: label ?? "Sloppy @ \(host)",
                host: host,
                port: port,
                isAutoDiscovered: false
            )
        case .open, .project, .session, .dictationToggle:
            return nil
        }
    }
}

private extension URLComponents {
    func nonEmptyQueryValue(named name: String) -> String? {
        guard let value = queryItems?.first(where: { $0.name == name })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}
