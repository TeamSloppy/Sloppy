import Crypto
import Foundation
import Protocols
import Testing
@testable import sloppy

@Suite(.serialized)
struct MCPHTTPDiscoveryTests {
    @Test(arguments: [false, true])
    func discoversModernCapabilitiesOverJSONAndSSE(useSSE: Bool) async throws {
        let methods = MCPFixtureMethods()
        try await withMCPServer { request in
            let method = request.rpcMethod
            await methods.append(method)
            if method == "tools/list" {
                return .init(status: 200, body: request.rpcReply("result", .object([
                    "resultType": .string("complete"), "tools": .array([]), "ttlMs": .number(60_000)
                ])))
            }
            guard method == "server/discover" else { return .init(status: 500, body: Data()) }
            #expect(request.header("authorization") == "Bearer fixture")
            #expect(request.header("Accept") == "application/json, text/event-stream")
            #expect(request.header("Content-Type") == "application/json")
            #expect(request.header("MCP-Protocol-Version") == "2026-07-28")
            #expect(request.header("Mcp-Method") == "server/discover")
            #expect(request.header("Mcp-Session-Id") == nil)
            #expect(request.header("Last-Event-ID") == nil)
            let metadata = request.rpc["params"]?.asObject?["_meta"]?.asObject
            #expect(metadata?["io.modelcontextprotocol/protocolVersion"] == .string("2026-07-28"))
            #expect(metadata?["io.modelcontextprotocol/clientCapabilities"] == .object([:]))
            #expect(metadata?["io.modelcontextprotocol/clientInfo"]?.asObject?["name"] == .string("sloppy"))
            let reply = request.discoverReply(capabilities: [
                "tools": .object([:]),
                "extensions": .object(["io.modelcontextprotocol/skills": .object([:])])
            ])
            guard useSSE else { return .init(status: 200, body: reply) }
            let progress = Data(#"{"jsonrpc":"2.0","method":"notifications/progress","params":{"progress":1}}"#.utf8)
            return .init(status: 200, body: Data(), contentType: "text/event-stream", sseStream: AsyncStream { stream in
                stream.yield(.init(event: "message", data: progress))
                stream.yield(.init(event: "message", data: reply))
                // The client must return when it sees the response, before EOF.
                let wait = Task {
                    try? await Task.sleep(for: .seconds(60))
                    stream.finish()
                }
                stream.onTermination = { _ in wait.cancel() }
            })
        } run: { endpoint in
            let registry = MCPClientRegistry(config: .init(servers: [
                .init(id: "modern", transport: .http, endpoint: endpoint, headers: [
                    "Authorization": "Bearer fixture",
                    "Mcp-Session-Id": "must-not-be-sent",
                    "Last-Event-ID": "must-not-be-sent",
                    "MCP-Protocol-Version": "2025-11-25"
                ], timeoutMs: 45_000)
            ]))

            let statuses = await registry.serverStatuses()
            let status = try #require(statuses.first)
            #expect(status.protocolVersion == "2026-07-28", Comment(rawValue: status.message ?? ""))
            #expect(status.advertisedCapabilities?["tools"] == .object([:]))
            #expect(status.advertisedCapabilities?["extensions"]?.asObject?.keys.contains("io.modelcontextprotocol/skills") == true)
            #expect(status.connected)
            #expect(status.message == nil)
            #expect(try await registry.listTools(serverID: "modern").tools.isEmpty)
            #expect(await methods.snapshot() == ["server/discover", "tools/list"])
        }
    }

    @Test(arguments: [400, 200])
    func fallsBackToLegacyAndListsTools(discoveryStatus: Int) async throws {
        let methods = MCPFixtureMethods()
        try await withMCPServer { request in
            let method = request.rpcMethod
            await methods.append(method)
            switch method {
            case "server/discover":
                let response = request.rpcReply("error", .object([
                    "code": .number(-32601), "message": .string("Method not found")
                ]))
                return .init(status: discoveryStatus, body: response)
            case "initialize":
                return .init(status: 200, body: request.rpcReply("result", .object([
                    "protocolVersion": .string("2025-11-25"),
                    "capabilities": .object(["tools": .object([:])]),
                    "serverInfo": .object(["name": .string("fixture"), "version": .string("1")])
                ])))
            case "notifications/initialized":
                return .init(status: 202, body: Data())
            case "tools/list":
                return .init(status: 200, body: request.rpcReply("result", .object([
                    "tools": .array([.object([
                        "name": .string("fixture_tool"), "inputSchema": .object(["type": .string("object")])
                    ])])
                ])))
            default:
                return .init(status: 500, body: Data())
            }
        } run: { endpoint in
            let registry = MCPClientRegistry(config: .init(servers: [
                .init(id: "legacy", transport: .http, endpoint: endpoint, timeoutMs: 45_000)
            ]))

            let tools = try await registry.listTools(serverID: "legacy").tools
            let statuses = await registry.serverStatuses()
            let status = try #require(statuses.first)

            #expect(tools.map(\.name) == ["fixture_tool"])
            #expect(status.connected)
            #expect(status.protocolVersion == "2025-11-25")
            #expect(status.message == nil)
            #expect(await methods.snapshot() == ["server/discover", "initialize", "notifications/initialized", "tools/list"])
        }
    }

    @Test(arguments: [401, 403, 404, -32020, -32021, -32022])
    func diagnosticsDoNotDowngradeModernErrors(statusOrCode: Int) async throws {
        let methods = MCPFixtureMethods()
        let marker: String
        switch statusOrCode {
        case -32020: marker = "headers"
        case -32021: marker = "capability"
        case -32022: marker = "2027-01-01"
        default: marker = "HTTP \(statusOrCode)"
        }
        try await withMCPServer { request in
            await methods.append(request.rpcMethod)
            let status = statusOrCode > 0 ? statusOrCode : 400
            let response = request.rpcReply("error", .object([
                "code": .number(Double(statusOrCode == 404 ? -32601 : statusOrCode)),
                "message": .string("sensitive upstream detail"),
                "data": .object(["supported": .array([.string("2027-01-01")])])
            ]))
            return .init(status: status, body: response)
        } run: { endpoint in
            let registry = MCPClientRegistry(config: .init(servers: [
                .init(id: "rejected", transport: .http, endpoint: endpoint, timeoutMs: 45_000)
            ]))

            let statuses = await registry.serverStatuses()
            let status = try #require(statuses.first)

            #expect(!status.connected)
            #expect(status.protocolVersion == nil)
            #expect(status.message?.contains(marker) == true, Comment(rawValue: status.message ?? ""))
            #expect(status.message?.contains("sensitive upstream detail") == false)
            #expect(await methods.snapshot() == ["server/discover"])
        }
    }

    @Test func changedCredentialsRenegotiateTheSameServerID() async throws {
        let methods = MCPFixtureMethods()
        try await withMCPServer { request in
            await methods.append(request.rpcMethod)
            guard request.header("authorization") == "Bearer original" else {
                return .init(status: 403, body: Data())
            }
            return .init(status: 200, body: request.discoverReply(capabilities: [:]))
        } run: { endpoint in
            var server = CoreConfig.MCP.Server(id: "rotated", transport: .http, endpoint: endpoint,
                                               headers: ["Authorization": "Bearer original"], timeoutMs: 45_000)
            let registry = MCPClientRegistry(config: .init(servers: [server]))
            #expect(await registry.serverStatuses().first?.protocolVersion == "2026-07-28")

            server.headers = ["Authorization": "Bearer new"]
            await registry.updateConfig(.init(servers: [server]))

            #expect(await registry.serverStatuses().first?.message?.contains("HTTP 403") == true)
            #expect(await methods.snapshot() == ["server/discover", "server/discover"])
        }
    }

    @Test func modernHTTPCallsPrimitivesAndMirrorsParameters() async throws {
        try await withMCPServer { request in
            let result: JSONValue
            switch request.rpcMethod {
            case "server/discover":
                return .init(status: 200, body: request.discoverReply(capabilities: [
                    "tools": .object([:]), "resources": .object([:]), "prompts": .object([:])
                ]))
            case "tools/list":
                result = .array([.object([
                    "name": .string("report"), "inputSchema": .object(["type": .string("object"), "properties": .object([
                        "region": .object(["type": .string("string"), "x-mcp-header": .string("Region")])
                    ])])
                ])])
                return request.complete(["tools": result, "ttlMs": .number(60_000)])
            case "tools/call":
                #expect(request.header("Mcp-Name") == "report")
                #expect(request.header("Mcp-Param-Region") == "=?base64?INCx0LUg?=")
                return request.complete(["content": .array([]), "structuredContent": .object(["count": .number(3)])])
            case "resources/list":
                return request.complete(["resources": .array([.object(["uri": .string("file:///report"), "name": .string("Report")])])])
            case "resources/read":
                #expect(request.header("Mcp-Name") == "file:///report")
                return request.complete(["contents": .array([.object(["uri": .string("file:///report"), "text": .string("report")])])])
            case "prompts/list":
                return request.complete(["prompts": .array([.object(["name": .string("review")])])])
            case "prompts/get":
                #expect(request.header("Mcp-Name") == "review")
                return request.complete(["messages": .array([.object([
                    "role": .string("user"), "content": .object(["type": .string("text"), "text": .string("Review it")])
                ])])])
            default: return .init(status: 404, body: Data())
            }
        } run: { endpoint in
            let registry = MCPClientRegistry(config: .init(servers: [.init(id: "modern", transport: .http, endpoint: endpoint)]))
            let result = try await registry.callTool(serverID: "modern", name: "report", arguments: ["region": .string(" бе ")])
            #expect(result.structuredContent == .object(["count": .number(3)]))
            let dynamic = try await registry.invokeDynamicTool(toolID: "mcp.modern.report", arguments: ["region": .string(" бе ")])
            #expect(dynamic?.data?.asObject?["structuredContent"] == result.structuredContent)
            #expect(try await registry.listResources(serverID: "modern").resources.map(\.name) == ["Report"])
            #expect(try await registry.readResource(serverID: "modern", uri: "file:///report").first?.text == "report")
            #expect(try await registry.listPrompts(serverID: "modern").prompts.map(\.name) == ["review"])
            #expect(try await registry.getPrompt(serverID: "modern", name: "review", arguments: [:]).messages.count == 1)
        }
    }

    #if !os(Windows)
    @Test func modernStdioAvoidsLegacyInitialization() async throws {
        let program = """
        import json, sys
        for line in sys.stdin:
            request = json.loads(line)
            method = request['method']
            if method == 'server/discover':
                result = {'supportedVersions': ['2026-07-28'], 'capabilities': {'tools': {}}}
            elif method == 'tools/list':
                result = {'tools': [{'name': 'stdio_echo', 'inputSchema': {'type': 'object'}}]}
            else:
                sys.exit(1)
            result['resultType'] = 'complete'
            print(json.dumps({'jsonrpc': '2.0', 'id': request['id'], 'result': result}), flush=True)
        """
        let registry = MCPClientRegistry(config: .init(servers: [
            .init(id: "stdio", transport: .stdio, command: "/usr/bin/env", arguments: ["python3", "-u", "-c", program])
        ]))
        let statuses = await registry.serverStatuses()
        #expect(statuses.first?.protocolVersion == "2026-07-28")
        #expect(try await registry.listTools(serverID: "stdio").tools.map(\.name) == ["stdio_echo"])
        await registry.updateConfig(.init(servers: []))
    }
    #endif

    @Test func elicitationResumesToolAndDeliversTaskToOriginalSession() async throws {
        try await withMCPServer { request in
            switch request.rpcMethod {
            case "server/discover":
                return .init(status: 200, body: request.discoverReply(capabilities: [
                    "tools": .object([:]), "extensions": .object([MCPToolInteraction.tasksID: .object([:])])
                ]))
            case "tools/list":
                return request.complete(["tools": .array([.object([
                    "name": .string("work"), "inputSchema": .object(["type": .string("object")])
                ])]), "ttlMs": .number(60_000)])
            case "tools/call":
                let params = request.rpc["params"]?.asObject ?? [:]
                let features = params["_meta"]?.asObject?["io.modelcontextprotocol/clientCapabilities"]?.asObject
                #expect(features?["elicitation"]?.asObject?["form"] == .object([:]))
                #expect(features?["extensions"]?.asObject?[MCPToolInteraction.tasksID] == .object([:]))
                if let responses = params["inputResponses"]?.asObject {
                    #expect(params["requestState"] == .string("opaque"))
                    #expect(responses["form"]?.asObject?["content"]?.asObject?["count"] == .number(3))
                    return request.complete(["resultType": .string("task"), "taskId": .string("remote"), "status": .string("working"),
                                             "ttlMs": .number(60_000), "pollIntervalMs": .number(500)])
                }
                return request.complete(["resultType": .string("input_required"), "requestState": .string("opaque"),
                    "inputRequests": .object(["form": .object(["method": .string("elicitation/create"), "params": .object([
                        "mode": .string("form"), "message": .string("How many?"), "requestedSchema": .object([
                            "type": .string("object"), "properties": .object(["count": .object(["type": .string("integer")])]),
                            "required": .array([.string("count")])
                        ])
                    ])])])])
            case "tasks/get":
                #expect(request.header("Mcp-Name") == "remote")
                return request.complete(["taskId": .string("remote"), "status": .string("completed"),
                                         "result": .object(["content": .array([.object([
                                            "type": .string("text"), "text": .string("Finished")
                                         ])])])])
            default: return .init(status: 404, body: Data())
            }
        } run: { endpoint in
            let (service, session) = try await self.chat(endpoint: endpoint)
            let call = Task {
                await service.invokeToolFromRuntime(agentID: session.agentId, sessionID: session.id,
                    request: .init(tool: "mcp.modern.work", arguments: [:]), recordSessionEvents: false)
            }
            defer { call.cancel() }
            let input = try await self.pendingInput(service, session: session)
            _ = try await service.answerAgentPlanInput(agentID: session.agentId, sessionID: session.id,
                requestID: input.id, payload: .init(answers: [.init(questionId: "response", customAnswer: #"{"count":3}"#)], userId: "dashboard"))
            let reply = await call.value
            #expect(reply.ok, "\(String(describing: reply.error))")
            let id = try #require(reply.data?.asObject?["structuredContent"]?.asObject?["taskId"]?.asString)
            await service.stopMCPTasks()
            let persisted = await service.workspaceRootURL.appendingPathComponent("mcp-tasks/\(id).json")
            #expect(FileManager.default.fileExists(atPath: persisted.path))
            await service.resumeMCPTasks()

            for _ in 0..<200 {
                let detail = try await service.getAgentSession(agentID: session.agentId, sessionID: session.id)
                if let event = detail.events.first(where: { $0.id == id }) {
                    #expect(event.toolResult?.data?.asObject?["status"] == .string("completed"))
                    #expect(detail.events.filter { $0.id == id }.count == 1)
                    return
                }
                try await Task.sleep(for: .milliseconds(25))
            }
            Issue.record("Task result did not reach the original chat")
        }
    }

    @Test func remoteSkillRequiresApprovalAndChecksBytes() async throws {
        let uri = "skill://review/SKILL.md"
        let markdown = "---\nname: review\ndescription: Review changes\n---\nInspect the diff."
        let digest = SHA256.hash(data: Data(markdown.utf8)).map { String(format: "%02x", $0) }.joined()
        let entry: JSONValue = .object([
            "uri": .string(uri),
            "frontmatter": .object(["name": .string("review"), "description": .string("Review changes")]),
            "resources": .array([.object(["uri": .string(uri), "digest": .string("sha256:" + digest),
                                          "size": .number(Double(markdown.utf8.count))])])
        ])
        let methods = MCPFixtureMethods()
        try await withMCPServer { request in
            await methods.append(request.rpcMethod)
            switch request.rpcMethod {
            case "server/discover":
                return .init(status: 200, body: request.discoverReply(capabilities: [
                    "resources": .object([:]), "extensions": .object([MCPRemoteSkill.extensionID: .object([:])])
                ]))
            case "skills/list": return request.complete(["skills": .array([entry])])
            case "skills/get": return request.complete(["skill": entry])
            case "resources/read":
                return request.complete(["contents": .array([.object(["uri": .string(uri), "text": .string(markdown)])])])
            default: return .init(status: 404, body: Data())
            }
        } run: { endpoint in
            let (service, session) = try await self.chat(endpoint: endpoint)
            let registry = await service.mcpRegistry
            let metadata = try await registry.remoteSkills(serverID: "modern", cursor: nil)
            #expect(metadata["skills"]?.asArray?.first?.asObject?["name"] == .string("review"))
            let operation = Task { try await service.useMCPSkill(agentID: session.agentId, sessionID: session.id,
                serverID: "modern", uri: uri, fileURI: nil, registry: registry) }
            defer { operation.cancel() }
            let input = try await self.pendingInput(service, session: session)
            #expect(!(await methods.snapshot()).contains("resources/read"))
            _ = try await service.answerAgentPlanInput(agentID: session.agentId, sessionID: session.id,
                requestID: input.id, payload: .init(answers: [.init(questionId: "response", selectedOptionId: "accept")], userId: "dashboard"))
            #expect(try await operation.value.asObject?["content"] == .string(markdown))
        }
    }

    private func chat(endpoint: String) async throws -> (CoreService, AgentSessionSummary) {
        var config = CoreConfig.test
        config.mcp = .init(servers: [.init(id: "modern", transport: .http, endpoint: endpoint)])
        let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let agent = try await service.createAgent(.init(id: "mcp-fixture", displayName: "MCP fixture", role: "Developer"))
        let session = try await service.createAgentSession(agentID: agent.id, request: .init(title: "MCP fixture"))
        await service.setSessionToolApprovalRequired(sessionID: session.id, enabled: false)
        _ = try await service.appendAgentSessionEvents(agentID: agent.id, sessionID: session.id, request: .init(events: [
            .init(agentId: agent.id, sessionId: session.id, type: .message,
                  message: .init(role: .user, segments: [.init(kind: .text, text: "Use MCP")], userId: "dashboard"))
        ]))
        return (service, session)
    }

    private func pendingInput(_ service: CoreService, session: AgentSessionSummary) async throws -> PlanInputRequest {
        for _ in 0..<200 {
            let detail = try await service.getAgentSession(agentID: session.agentId, sessionID: session.id)
            if let input = detail.events.compactMap(\.inputRequest).last { return input }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw MCPRegistryError.invalidResult("No MCP input arrived in the session.")
    }

    @Test func subscriptionRefreshesCachedToolCatalog() async throws {
        let feed = MCPFixtureSubscription()
        try await withMCPServer { request in
            switch request.rpcMethod {
            case "server/discover":
                return .init(status: 200, body: request.discoverReply(capabilities: [
                    "tools": .object(["listChanged": .bool(true)])
                ]))
            case "tools/list":
                let name = await feed.toolName
                return request.complete(["tools": .array([.object([
                    "name": .string(name), "inputSchema": .object(["type": .string("object")])
                ])]), "ttlMs": .number(60_000)])
            case "subscriptions/listen":
                let id = request.rpc["id"]?.asString ?? ""
                let (stream, continuation) = AsyncStream<CoreRouterServerSentEvent>.makeStream()
                await feed.subscribe(id: id, continuation: continuation)
                return .init(status: 200, body: Data(), contentType: "text/event-stream", sseStream: stream)
            default: return .init(status: 404, body: Data())
            }
        } run: { endpoint in
            let registry = MCPClientRegistry(config: .init(servers: [.init(id: "modern", transport: .http, endpoint: endpoint)]))
            _ = await registry.serverStatuses()
            for _ in 0..<200 {
                if await feed.ready, await registry.dynamicTools().map(\.toolName) == ["initial"] { break }
                try await Task.sleep(for: .milliseconds(25))
            }
            #expect(await feed.ready)
            #expect(await registry.dynamicTools().map(\.toolName) == ["initial"])
            await feed.change()
            for _ in 0..<200 {
                if await registry.dynamicTools().map(\.toolName) == ["updated"] { break }
                try await Task.sleep(for: .milliseconds(25))
            }
            #expect(await registry.dynamicTools().map(\.toolName) == ["updated"])
            await registry.updateConfig(.init(servers: []))
        }
    }

    private func withMCPServer(
        _ handle: @escaping @Sendable (HTTPRequest) async -> CoreRouterResponse,
        run: (String) async throws -> Void
    ) async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder(), sharedSkillsRootURLs: [])
        let router = CoreRouter(service: service)
        await router.post("/fixture-mcp", callback: handle)
        let server = CoreHTTPServer(host: "127.0.0.1", port: 0, router: router, logger: .init(label: "mcp.http.fixture"))
        try server.start()
        defer { try? server.shutdown() }
        let port = try #require(server.boundPort)
        try await run("http://127.0.0.1:\(port)/fixture-mcp")
    }
}

private actor MCPFixtureMethods {
    private var methods: [String] = []
    func append(_ method: String) { methods.append(method) }
    func snapshot() -> [String] { methods }
}

private extension HTTPRequest {
    var rpc: [String: JSONValue] {
        guard let body else { return [:] }
        return (try? JSONDecoder().decode(JSONValue.self, from: body))?.asObject ?? [:]
    }

    var rpcMethod: String { rpc["method"]?.asString ?? "" }

    func complete(_ fields: [String: JSONValue]) -> CoreRouterResponse {
        .init(status: 200, body: rpcReply("result", .object(fields.merging(["resultType": .string("complete")]) { first, _ in first })))
    }

    func discoverReply(capabilities: [String: JSONValue]) -> Data {
        rpcReply("result", .object([
            "resultType": .string("complete"), "supportedVersions": .array([.string("2026-07-28")]),
            "ttlMs": .number(60_000), "cacheScope": .string("private"), "capabilities": .object(capabilities)
        ]))
    }

    func rpcReply(_ field: String, _ value: JSONValue) -> Data {
        (try? JSONEncoder().encode(JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": rpc["id"] ?? .null,
            field: value
        ]))) ?? Data()
    }
}


private actor MCPFixtureSubscription {
    private var id: String?
    private var events: AsyncStream<CoreRouterServerSentEvent>.Continuation?
    private(set) var toolName = "initial"
    var ready: Bool { events != nil }

    func subscribe(id: String, continuation: AsyncStream<CoreRouterServerSentEvent>.Continuation) {
        self.id = id
        events = continuation
        emit("notifications/subscriptions/acknowledged", ["notifications": .object(["toolsListChanged": .bool(true)])])
    }

    func change() {
        toolName = "updated"
        emit("notifications/tools/list_changed", [:])
    }

    private func emit(_ method: String, _ params: [String: JSONValue]) {
        guard let id else { return }
        var params = params
        params["_meta"] = .object(["io.modelcontextprotocol/subscriptionId": .string(id)])
        let packet: JSONValue = .object(["jsonrpc": .string("2.0"), "method": .string(method), "params": .object(params)])
        if let data = try? JSONEncoder().encode(packet) { events?.yield(.init(event: "message", data: data)) }
    }
}
