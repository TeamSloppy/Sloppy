import Foundation

public enum SloppyInstanceEndpoint: Codable, Equatable, Sendable {
    case direct(baseURL: URL)
    case relay(coordinatorBaseURL: URL, targetNodeID: String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case baseURL
        case targetNodeID
    }

    private enum Kind: String, Codable {
        case direct
        case relay
    }

    public var coordinatorBaseURL: URL {
        switch self {
        case .direct(let baseURL):
            baseURL
        case .relay(let coordinatorBaseURL, _):
            coordinatorBaseURL
        }
    }

    public var targetNodeID: String? {
        guard case .relay(_, let targetNodeID) = self else { return nil }
        return targetNodeID
    }

    public var isDirect: Bool {
        if case .direct = self { return true }
        return false
    }

    public var cacheNamespace: String {
        switch self {
        case .direct(let baseURL):
            return "direct:\(baseURL.absoluteString)"
        case .relay(let coordinatorBaseURL, let targetNodeID):
            return "relay:\(coordinatorBaseURL.absoluteString):\(targetNodeID)"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .direct:
            self = .direct(baseURL: try container.decode(URL.self, forKey: .baseURL))
        case .relay:
            self = .relay(
                coordinatorBaseURL: try container.decode(URL.self, forKey: .baseURL),
                targetNodeID: try container.decode(String.self, forKey: .targetNodeID)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .direct(let baseURL):
            try container.encode(Kind.direct, forKey: .kind)
            try container.encode(baseURL, forKey: .baseURL)
        case .relay(let coordinatorBaseURL, let targetNodeID):
            try container.encode(Kind.relay, forKey: .kind)
            try container.encode(coordinatorBaseURL, forKey: .baseURL)
            try container.encode(targetNodeID, forKey: .targetNodeID)
        }
    }
}

public struct SloppyInstance: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var endpoint: SloppyInstanceEndpoint
    public var status: MeshNodeStatus
    public var isLocal: Bool

    public init(
        id: String,
        name: String,
        endpoint: SloppyInstanceEndpoint,
        status: MeshNodeStatus = .offline,
        isLocal: Bool = false
    ) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.status = status
        self.isLocal = isLocal
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? id : trimmed
    }
}

public struct ClientMeshLocalNode: Codable, Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct ClientMeshTopology: Codable, Equatable, Sendable {
    public var networkId: String
    public var networkName: String
    public var localNode: ClientMeshLocalNode?
    public var nodes: [MeshNodeRecord]

    public init(
        networkId: String,
        networkName: String,
        localNode: ClientMeshLocalNode? = nil,
        nodes: [MeshNodeRecord] = []
    ) {
        self.networkId = networkId
        self.networkName = networkName
        self.localNode = localNode
        self.nodes = nodes
    }

    public func instances(coordinatorBaseURL: URL) -> [SloppyInstance] {
        var result: [SloppyInstance] = []
        if let localNode {
            let currentNode = nodes.first { $0.id == localNode.id }
            result.append(
                SloppyInstance(
                    id: localNode.id,
                    name: localNode.name,
                    endpoint: .direct(baseURL: coordinatorBaseURL),
                    status: currentNode?.status ?? .online,
                    isLocal: true
                )
            )
        } else {
            result.append(
                SloppyInstance(
                    id: "local:\(coordinatorBaseURL.absoluteString)",
                    name: coordinatorBaseURL.host ?? "Local Sloppy",
                    endpoint: .direct(baseURL: coordinatorBaseURL),
                    status: .online,
                    isLocal: true
                )
            )
        }

        for node in nodes where node.id != localNode?.id
            && node.capabilities.contains("sloppy.core.remote") {
            result.append(
                SloppyInstance(
                    id: node.id,
                    name: node.displayName,
                    endpoint: .relay(
                        coordinatorBaseURL: coordinatorBaseURL,
                        targetNodeID: node.id
                    ),
                    status: node.status,
                    isLocal: false
                )
            )
        }
        return result
    }
}

public enum SloppyInstanceSelection: Codable, Equatable, Hashable, Sendable {
    case all
    case instance(String)

    public var instanceID: String? {
        guard case .instance(let id) = self else { return nil }
        return id
    }
}

public struct InstanceScopedID: Hashable, Codable, Sendable, CustomStringConvertible {
    public var instanceID: String
    public var localID: String

    public init(instanceID: String, localID: String) {
        self.instanceID = instanceID
        self.localID = localID
    }

    public var description: String {
        "\(instanceID):\(localID)"
    }
}
