import Foundation

public enum DeepLink: Sendable {
    case connect(host: String, port: Int, label: String?)

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
        default:
            return nil
        }
    }

    public var serverURL: URL? {
        switch self {
        case .connect(let host, let port, _):
            return ServerAddress(host: host, port: port).baseURL
        }
    }

    public var savedServer: SavedServer {
        switch self {
        case .connect(let host, let port, let label):
            return SavedServer(
                label: label ?? "Sloppy @ \(host)",
                host: host,
                port: port,
                isAutoDiscovered: false
            )
        }
    }
}
