import Foundation
import Protocols
@testable import SloppyNodeCore
import Testing

@Suite("NodeMeshEvent")
struct NodeMeshEventTests {
    @Test("signed mesh event verifies with actor public key")
    func signedMeshEventVerifiesWithActorPublicKey() throws {
        let identity = NodeIdentityGenerator.makeIdentity(
            name: "Home",
            roles: ["worker"],
            capabilities: ["git"]
        )
        let event = MeshEvent(
            type: .taskCreated,
            actorNodeId: identity.nodeId,
            targetNodeId: nil,
            projectId: "sp_sloppy",
            logicalTime: 1,
            payload: .object([
                "taskId": .string("mesh_task_1"),
                "title": .string("Run tests"),
            ])
        )

        let signed = try MeshEventSigner.sign(event, identity: identity)

        #expect(signed.event.actorNodeId == identity.nodeId)
        #expect(try MeshEventSigner.verify(signed, publicKey: identity.publicKey) == true)
    }

    @Test("tampered signed mesh event fails verification")
    func tamperedSignedMeshEventFailsVerification() throws {
        let identity = NodeIdentityGenerator.makeIdentity(
            name: "Home",
            roles: ["worker"],
            capabilities: ["git"]
        )
        let event = MeshEvent(
            type: .taskCreated,
            actorNodeId: identity.nodeId,
            projectId: "sp_sloppy",
            logicalTime: 1,
            payload: .object(["title": .string("Run tests")])
        )
        var signed = try MeshEventSigner.sign(event, identity: identity)
        signed.event.payload = .object(["title": .string("Different")])

        #expect(try MeshEventSigner.verify(signed, publicKey: identity.publicKey) == false)
    }

    @Test("event signing payload is stable")
    func eventSigningPayloadIsStable() throws {
        let event = MeshEvent(
            id: "evt_1",
            type: .projectCreated,
            actorNodeId: "node_home",
            targetNodeId: nil,
            projectId: "sp_sloppy",
            logicalTime: 42,
            wallTime: Date(timeIntervalSince1970: 1_800_000_000),
            causalParents: ["evt_0"],
            payload: .object(["name": .string("Sloppy")])
        )

        let data = try MeshEventSigner.signingData(for: event)
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains(#""id":"evt_1""#))
        #expect(text.contains(#""type":"project.created""#))
        #expect(text.contains(#""logicalTime":42"#))
    }
}
