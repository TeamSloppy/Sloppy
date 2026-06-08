import Foundation
import Protocols
import Testing
@testable import SloppyNodeCore

@Suite("NodeMeshClient")
struct NodeMeshClientTests {
    @Test("relay URL resolves to mesh websocket endpoint")
    func relayURLResolvesToMeshWebSocketEndpoint() throws {
        #expect(try NodeMeshClient.resolveRelayWebSocketURL("https://sloppy.example.com").absoluteString == "wss://sloppy.example.com/v1/node/mesh/ws")
        #expect(try NodeMeshClient.resolveRelayWebSocketURL("http://127.0.0.1:8787/").absoluteString == "ws://127.0.0.1:8787/v1/node/mesh/ws")
        #expect(try NodeMeshClient.resolveRelayWebSocketURL("ws://relay.local/custom").absoluteString == "ws://relay.local/custom")
        #expect(try NodeMeshClient.resolveRelayWebSocketURL("wss://relay.local/custom").absoluteString == "wss://relay.local/custom")
    }

    @Test("hello envelope includes identity roles and capabilities")
    func helloEnvelopeIncludesIdentityRolesAndCapabilities() {
        let identity = NodeIdentity(
            nodeId: "node_laptop",
            name: "Laptop",
            publicKey: "ed25519:laptop",
            privateKey: "ed25519:private",
            roles: ["client", "worker"],
            capabilities: ["git", "run_agent"]
        )

        let envelope = NodeMeshClient.makeHelloEnvelope(identity: identity)

        #expect(envelope.type == .nodeHello)
        #expect(envelope.from == "node_laptop")
        #expect(envelope.payload.asObject?["name"] == .string("Laptop"))
        #expect(envelope.payload.asObject?["publicKey"] == .string("ed25519:laptop"))
        #expect(envelope.payload.asObject?["roles"] == .array([.string("client"), .string("worker")]))
        #expect(envelope.payload.asObject?["capabilities"] == .array([.string("git"), .string("run_agent")]))
    }

    @Test("client handles node ping rpc request")
    func clientHandlesNodePingRPCRequest() async throws {
        let identity = NodeIdentity(
            nodeId: "node_worker",
            name: "Worker",
            publicKey: "ed25519:worker",
            privateKey: "ed25519:private",
            roles: ["worker"],
            capabilities: ["run_agent", "git"]
        )
        let daemon = NodeDaemon(config: NodeConfig(identity: identity))
        await daemon.connect()
        let client = NodeMeshClient(config: NodeConfig(identity: identity), daemon: daemon)

        let response = try #require(await client.response(
            to: MeshEnvelope(
                id: "rpc_1",
                type: .rpcRequest,
                from: "node_laptop",
                to: "node_worker",
                payload: .object([
                    "method": .string("node.ping"),
                    "params": .object([:]),
                ])
            )
        ))

        #expect(response.type == .rpcResponse)
        #expect(response.from == "node_worker")
        #expect(response.to == "node_laptop")
        #expect(response.payload.asObject?["requestId"] == .string("rpc_1"))
        #expect(response.payload.asObject?["ok"] == .bool(true))
        #expect(response.payload.asObject?["method"] == .string("node.ping"))
    }
}
