import Foundation

public struct NodeMeshRemoteJoiner: Sendable {
    public typealias AcceptInvite = @Sendable (URL, MeshInviteAcceptRequest) async throws -> MeshNodeRecord

    public var configStore: NodeConfigStore
    public var acceptInvite: AcceptInvite

    public init(
        configStore: NodeConfigStore = NodeConfigStore(),
        acceptInvite: @escaping AcceptInvite
    ) {
        self.configStore = configStore
        self.acceptInvite = acceptInvite
    }

    public func join(_ request: MeshRemoteJoinRequest) async throws -> MeshRemoteJoinResult {
        let bundle: MeshInviteBundle
        do {
            bundle = try MeshInviteBundle.parse(request.token)
        } catch {
            throw MeshRemoteJoinError.invalidInvite(String(describing: error))
        }

        let config = try localConfig(for: request, relayURL: bundle.relayURL)
        if let expectedPublicKey = bundle.publicKey,
           expectedPublicKey != config.identity.publicKey {
            throw MeshRemoteJoinError.identityMismatch(
                expectedPublicKey: expectedPublicKey,
                actualPublicKey: config.identity.publicKey
            )
        }

        let acceptURL = try coordinatorAcceptURL(from: bundle.relayURL)
        let acceptRequest = MeshInviteAcceptRequest(
            token: request.token,
            endpoint: bundle.relayURL,
            nodeId: config.identity.nodeId,
            name: config.identity.name,
            publicKey: config.identity.publicKey,
            roles: config.identity.roles,
            capabilities: config.identity.capabilities
        )
        let node = try await acceptInvite(acceptURL, acceptRequest)
        try configStore.save(NodeConfig(identity: config.identity, relayURL: bundle.relayURL))
        return MeshRemoteJoinResult(
            node: node,
            relayURL: bundle.relayURL,
            coordinatorAcceptURL: acceptURL.absoluteString
        )
    }

    private func localConfig(for request: MeshRemoteJoinRequest, relayURL: String) throws -> NodeConfig {
        if !request.force, let existing = try? configStore.load() {
            return NodeConfig(identity: existing.identity, relayURL: relayURL)
        }

        return try configStore.initialize(
            name: normalizedName(request.name),
            roles: ["worker"],
            capabilities: ["run_agent", "git"],
            relayURL: relayURL,
            force: request.force
        )
    }

    private func normalizedName(_ name: String?) -> String {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return "Sloppy Node"
        }
        return trimmed
    }

    private func coordinatorAcceptURL(from relayURL: String) throws -> URL {
        guard var components = URLComponents(string: relayURL),
              components.scheme?.isEmpty == false,
              components.host?.isEmpty == false
        else {
            throw MeshRemoteJoinError.invalidInvite("relay URL is invalid")
        }
        components.path = "/v1/node/mesh/invites/accept"
        components.query = nil
        guard let url = components.url else {
            throw MeshRemoteJoinError.invalidInvite("relay URL is invalid")
        }
        return url
    }
}
