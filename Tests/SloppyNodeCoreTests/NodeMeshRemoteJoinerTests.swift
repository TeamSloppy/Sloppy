import Foundation
import Testing
@testable import SloppyNodeCore

@Suite("NodeMeshRemoteJoiner")
struct NodeMeshRemoteJoinerTests {
    @Test("remote join creates local identity and accepts invite at coordinator")
    func remoteJoinCreatesLocalIdentityAndAcceptsInviteAtCoordinator() async throws {
        let configURL = temporaryConfigURL()
        let token = try MeshInviteBundle(
            inviteToken: "slp_invite_remote",
            relayURL: "https://mesh.example.com",
            networkId: "personal",
            networkName: "VPS-Node"
        ).tokenString()
        let recorder = AcceptRecorder()
        let joiner = NodeMeshRemoteJoiner(
            configStore: NodeConfigStore(configURL: configURL),
            acceptInvite: { url, request in
                await recorder.record(url: url, request: request)
                return MeshNodeRecord(
                    id: request.nodeId ?? "missing",
                    name: request.name ?? "missing",
                    publicKey: request.publicKey ?? "missing",
                    roles: request.roles ?? [],
                    endpoint: request.endpoint,
                    status: .offline,
                    capabilities: request.capabilities ?? []
                )
            }
        )

        let result = try await joiner.join(MeshRemoteJoinRequest(token: token, name: "Work Mac"))
        let accepted = await recorder.snapshot()

        #expect(result.relayURL == "https://mesh.example.com")
        #expect(accepted.url?.absoluteString == "https://mesh.example.com/v1/node/mesh/invites/accept")
        #expect(accepted.request?.token == token)
        #expect(accepted.request?.nodeId == result.node.id)
        #expect(accepted.request?.publicKey == result.node.publicKey)
        let savedConfig = try NodeConfigStore(configURL: configURL).load()
        #expect(savedConfig.relayURL == "https://mesh.example.com")
        #expect(savedConfig.networkId == "personal")
        #expect(savedConfig.networkName == "VPS-Node")
        #expect(result.networkId == "personal")
        #expect(result.networkName == "VPS-Node")
    }

    @Test("remote join preserves existing identity unless force is true")
    func remoteJoinPreservesExistingIdentityUnlessForceIsTrue() async throws {
        let configURL = temporaryConfigURL()
        let store = NodeConfigStore(configURL: configURL)
        let existing = try store.initialize(name: "Existing", roles: ["worker"], capabilities: ["git"])
        let token = try MeshInviteBundle(
            inviteToken: "slp_invite_remote",
            relayURL: "https://mesh.example.com",
            networkId: "personal",
            networkName: "VPS-Node"
        ).tokenString()
        let joiner = NodeMeshRemoteJoiner(
            configStore: store,
            acceptInvite: { _, request in
                MeshNodeRecord(
                    id: request.nodeId ?? "missing",
                    name: request.name ?? "missing",
                    publicKey: request.publicKey ?? "missing",
                    roles: request.roles ?? [],
                    endpoint: request.endpoint,
                    status: .offline,
                    capabilities: request.capabilities ?? []
                )
            }
        )

        let result = try await joiner.join(MeshRemoteJoinRequest(token: token, name: "New Name"))

        #expect(result.node.id == existing.identity.nodeId)
        #expect(result.node.name == existing.identity.name)
        #expect(try store.load().identity.nodeId == existing.identity.nodeId)
        #expect(try store.load().relayURL == "https://mesh.example.com")
        #expect(try store.load().networkName == "VPS-Node")
    }

    private func temporaryConfigURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sloppy-node-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("node.json")
    }
}

private actor AcceptRecorder {
    private var acceptedURL: URL?
    private var acceptedRequest: MeshInviteAcceptRequest?

    func record(url: URL, request: MeshInviteAcceptRequest) {
        acceptedURL = url
        acceptedRequest = request
    }

    func snapshot() -> (url: URL?, request: MeshInviteAcceptRequest?) {
        (acceptedURL, acceptedRequest)
    }
}
