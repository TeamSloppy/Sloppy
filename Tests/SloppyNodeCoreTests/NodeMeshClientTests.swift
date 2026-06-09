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
        let identity = NodeIdentityGenerator.makeIdentity(
            name: "Worker",
            roles: ["worker"],
            capabilities: ["run_agent", "git"]
        )
        let daemon = NodeDaemon(config: NodeConfig(identity: identity))
        await daemon.connect()
        let client = NodeMeshClient(config: NodeConfig(identity: identity), daemon: daemon)
        _ = try await client.response(to: authChallengeEnvelope(for: identity, nonce: "nonce_ping"))

        let response = try #require(await client.response(
            to: MeshEnvelope(
                id: "rpc_1",
                type: .rpcRequest,
                from: "node_laptop",
                to: identity.nodeId,
                payload: .object([
                    "method": .string("node.ping"),
                    "params": .object([:]),
                ])
            )
        ))

        #expect(response.type == .rpcResponse)
        #expect(response.from == identity.nodeId)
        #expect(response.to == "node_laptop")
        #expect(response.payload.asObject?["requestId"] == .string("rpc_1"))
        #expect(response.payload.asObject?["ok"] == .bool(true))
        #expect(response.payload.asObject?["method"] == .string("node.ping"))
    }

    @Test("client signs relay auth challenge")
    func clientSignsRelayAuthChallenge() async throws {
        let identity = NodeIdentityGenerator.makeIdentity(
            name: "Worker",
            roles: ["worker"],
            capabilities: ["run_agent", "git"]
        )
        let client = NodeMeshClient(config: NodeConfig(identity: identity))

        let response = try #require(await client.response(to: authChallengeEnvelope(for: identity, nonce: "nonce_auth")))
        let payload = try JSONValueCoder.decode(MeshAuthResponsePayload.self, from: response.payload)

        #expect(response.type == .authResponse)
        #expect(response.from == identity.nodeId)
        #expect(response.to == "relay")
        #expect(payload.nonce == "nonce_auth")
        #expect(payload.nodeId == identity.nodeId)
        #expect(payload.publicKey == identity.publicKey)
        #expect(NodeIdentityGenerator.verify(signature: payload.signature, challenge: Data("nonce_auth".utf8), publicKey: identity.publicKey))
    }

    @Test("client ignores rpc before relay auth completes")
    func clientIgnoresRPCBeforeRelayAuthCompletes() async throws {
        let identity = NodeIdentityGenerator.makeIdentity(
            name: "Worker",
            roles: ["worker"],
            capabilities: ["run_agent", "git"]
        )
        let client = NodeMeshClient(config: NodeConfig(identity: identity))

        let response = await client.response(
            to: MeshEnvelope(
                id: "rpc_before_auth",
                type: .rpcRequest,
                from: "node_laptop",
                to: identity.nodeId,
                payload: .object([
                    "method": .string("node.ping"),
                    "params": .object([:]),
                ])
            )
        )

        #expect(response == nil)
    }

    @Test("rpc manager correlates matching response")
    func rpcManagerCorrelatesMatchingResponse() async throws {
        let manager = NodeMeshRPCManager()
        let request = MeshEnvelope(
            id: "rpc_waiting",
            type: .rpcRequest,
            from: "node_laptop",
            to: "node_worker",
            payload: .object([
                "method": .string("node.ping"),
                "params": .object([:]),
            ])
        )

        async let response = manager.send(request, timeout: 1) { envelope in
            #expect(envelope.id == "rpc_waiting")
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        let delivered = await manager.receive(MeshEnvelope(
            type: .rpcResponse,
            from: "node_worker",
            to: "node_laptop",
            payload: .object([
                "requestId": .string("rpc_waiting"),
                "ok": .bool(true),
            ])
        ))

        #expect(delivered)
        #expect(try await response.payload.asObject?["ok"] == JSONValue.bool(true))
    }

    @Test("rpc manager times out and ignores late response")
    func rpcManagerTimesOutAndIgnoresLateResponse() async throws {
        let manager = NodeMeshRPCManager()
        let request = MeshEnvelope(
            id: "rpc_timeout",
            type: .rpcRequest,
            from: "node_laptop",
            to: "node_worker",
            payload: .object([
                "method": .string("node.status"),
                "params": .object([:]),
            ])
        )

        do {
            _ = try await manager.send(request, timeout: 0.01) { _ in }
            Issue.record("Expected RPC timeout")
        } catch let error as NodeMeshRPCError {
            #expect(error == .timeout("rpc_timeout"))
        }

        let delivered = await manager.receive(MeshEnvelope(
            type: .rpcResponse,
            from: "node_worker",
            to: "node_laptop",
            payload: .object([
                "requestId": .string("rpc_timeout"),
                "ok": .bool(true),
            ])
        ))
        #expect(delivered == false)
    }

    @Test("client handles shared project list and get rpc")
    func clientHandlesSharedProjectListAndGetRPC() async throws {
        let worker = NodeIdentityGenerator.makeIdentity(name: "Worker", roles: ["worker"], capabilities: ["git"])
        let laptop = NodeIdentityGenerator.makeIdentity(name: "Laptop", roles: ["client"], capabilities: ["git"])
        let outsider = NodeIdentityGenerator.makeIdentity(name: "Outsider", roles: ["client"], capabilities: [])
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        try store.registerNode(worker)
        try store.registerNode(laptop)
        try store.registerNode(outsider)
        let project = try store.createSharedProject(name: "Mesh Project", repoUrl: "git@example.com:mesh.git")
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: laptop.nodeId,
            localRepoPath: "/Users/laptop/mesh",
            role: "controller",
            permissions: [MeshPermission.projectRead.rawValue, MeshPermission.nodeRPC.rawValue]
        )
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: worker.nodeId,
            localRepoPath: "/Users/worker/mesh",
            role: "worker",
            permissions: MeshPermission.workerDefaults.rawValues
        )
        let client = NodeMeshClient(config: NodeConfig(identity: worker), meshStore: store)
        _ = try await client.response(to: authChallengeEnvelope(for: worker, nonce: "nonce_shared_projects"))

        let listResponse = try #require(await client.response(to: MeshEnvelope(
            id: "rpc_project_list",
            type: .rpcRequest,
            from: laptop.nodeId,
            to: worker.nodeId,
            payload: .object([
                "method": .string("shared_project.list"),
                "params": .object([:]),
            ])
        )))
        let listedProjects = try #require(listResponse.payload.asObject?["result"]?.asObject?["projects"]?.asArray)
        #expect(listedProjects.count == 1)
        #expect(listedProjects.first?.asObject?["id"] == JSONValue.string(project.id))
        #expect(listedProjects.first?.asObject?["repoUrl"] == JSONValue.string("git@example.com:mesh.git"))

        let getResponse = try #require(await client.response(to: MeshEnvelope(
            id: "rpc_project_get",
            type: .rpcRequest,
            from: laptop.nodeId,
            to: worker.nodeId,
            payload: .object([
                "method": .string("shared_project.get"),
                "params": .object(["id": .string(project.id)]),
            ])
        )))
        #expect(getResponse.payload.asObject?["ok"] == JSONValue.bool(true))
        #expect(getResponse.payload.asObject?["result"]?.asObject?["id"] == JSONValue.string(project.id))

        let forbidden = try #require(await client.response(to: MeshEnvelope(
            id: "rpc_project_forbidden",
            type: .rpcRequest,
            from: outsider.nodeId,
            to: worker.nodeId,
            payload: .object([
                "method": .string("shared_project.get"),
                "params": .object(["id": .string(project.id)]),
            ])
        )))
        #expect(forbidden.payload.asObject?["ok"] == JSONValue.bool(false))
        #expect(forbidden.payload.asObject?["error"]?.asObject?["code"] == JSONValue.string("forbidden"))
    }

    @Test("project status reports local shared project git state")
    func projectStatusReportsLocalSharedProjectGitState() async throws {
        let worker = NodeIdentityGenerator.makeIdentity(name: "Worker", roles: ["worker"], capabilities: ["git"])
        let laptop = NodeIdentityGenerator.makeIdentity(name: "Laptop", roles: ["client"], capabilities: ["git"])
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sloppy-mesh-project-status-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], at: repoURL)

        let store = NodeMeshStore(stateURL: temporaryStateURL())
        try store.registerNode(worker)
        try store.registerNode(laptop)
        let project = try store.createSharedProject(name: "Mesh Project", repoUrl: "git@example.com:mesh.git")
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: laptop.nodeId,
            localRepoPath: "/Users/laptop/mesh",
            role: "controller",
            permissions: [MeshPermission.projectRead.rawValue, MeshPermission.nodeRPC.rawValue]
        )
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: worker.nodeId,
            localRepoPath: repoURL.path,
            role: "worker",
            permissions: MeshPermission.workerDefaults.rawValues
        )
        let client = NodeMeshClient(config: NodeConfig(identity: worker), meshStore: store)
        _ = try await client.response(to: authChallengeEnvelope(for: worker, nonce: "nonce_project_status"))

        let response = try #require(await client.response(to: MeshEnvelope(
            id: "rpc_project_status",
            type: .rpcRequest,
            from: laptop.nodeId,
            to: worker.nodeId,
            payload: .object([
                "method": .string("project.status"),
                "params": .object(["sharedProjectId": .string(project.id)]),
            ])
        )))

        let result = try #require(response.payload.asObject?["result"]?.asObject)
        #expect(response.payload.asObject?["ok"] == JSONValue.bool(true))
        #expect(result["sharedProjectId"] == JSONValue.string(project.id))
        #expect(result["localRepoPath"] == JSONValue.string(repoURL.path))
        #expect(result["gitBranch"] == JSONValue.string("main"))
        #expect(result["dirty"] == JSONValue.bool(false))
    }

    private func authChallengeEnvelope(for identity: NodeIdentity, nonce: String) throws -> MeshEnvelope {
        MeshEnvelope(
            type: .authChallenge,
            from: "relay",
            to: identity.nodeId,
            payload: try JSONValueCoder.encode(
                MeshAuthChallengePayload(
                    nonce: nonce,
                    nodeId: identity.nodeId,
                    publicKey: identity.publicKey,
                    issuedAt: Date(timeIntervalSince1970: 1_716_000_000)
                )
            )
        )
    }

    private func temporaryStateURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sloppy-mesh-client-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("mesh.json")
    }

    private func runGit(_ arguments: [String], at directoryURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = directoryURL
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
