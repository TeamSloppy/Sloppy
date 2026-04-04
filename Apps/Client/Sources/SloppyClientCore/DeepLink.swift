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
            let port = portString.flatMap(Int.init) ?? 25101
            let label = items.first(where: { $0.name == "label" })?.value
            return .connect(host: host, port: port, label: label)
        default:
            return nil
        }
    }

    public var serverURL: URL? {
        switch self {
        case .connect(let host, let port, _):
            return URL(string: "http://\(host):\(port)")
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
