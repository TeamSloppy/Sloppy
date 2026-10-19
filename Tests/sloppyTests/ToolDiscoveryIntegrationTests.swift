import Foundation
import Testing
@testable import Protocols
@testable import sloppy

@Suite("Tool discovery integration")
struct ToolDiscoveryIntegrationTests {
    private func fixture() throws -> (URL, CoreConfig) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sloppy-discovery-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = root.appendingPathComponent("mcp.py")
        try #"""
        import json, sys
        for line in sys.stdin:
            request = json.loads(line)
            method = request.get("method")
            if method == "initialize":
                result = {"protocolVersion":"2024-11-05","capabilities":{"tools":{}},"serverInfo":{"name":"discovery-test","version":"1"}}
            elif method == "tools/list":
                second = request.get("params", {}).get("cursor") == "page2"
                name = "search_issues" if second else "read_project"
                result = {"tools":[{"name":name,"description":"Find project issues" if second else "Read a project","annotations":{"readOnlyHint":True},"inputSchema":{"type":"object","properties":{"projectKey":{"type":"string"}},"required":["projectKey"],"additionalProperties":False}}]}
                if not second:
                    result["nextCursor"] = "page2"
            elif method == "tools/call":
                result = {"content":[{"type":"text","text":json.dumps(request["params"]["arguments"], sort_keys=True)}]}
            else:
                result = {}
            if "id" in request:
                print(json.dumps({"jsonrpc":"2.0","id":request["id"],"result":result}), flush=True)
        """#.write(to: script, atomically: true, encoding: .utf8)
        var config = CoreConfig.test
        config.mcp = .init(servers: [.init(id: "tracker", transport: .stdio, command: "/usr/bin/python3", arguments: [script.path], timeoutMs: 60_000)])
        return (root, config)
    }

    @Test("Search all MCP pages, call selected schema, persist metrics, and reject revoked target access")
    func searchCallAndRevocation() async throws {
        let (root, config) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        _ = try await service.createAgent(.init(id: "dev", displayName: "Dev", role: "Developer", isSystem: false))
        // This trusted local fixture tests discovery, not the independent human approval flow.
        _ = try await service.updateAgentToolsPolicy(agentID: "dev", request: .init(approval: .init(untrustedContextGuard: .off)))
        let session = try await service.createAgentSession(agentID: "dev", request: .init(title: "Discovery"))
        await service.setSessionToolApprovalRequired(sessionID: session.id, enabled: false)
        let result = await service.invokeToolFromRuntime(agentID: "dev", sessionID: session.id,
            request: .init(tool: "system.search_tools", arguments: ["query": .string("search issues"), "server": .string("tracker")]))
        #expect(result.ok, "\(String(describing: result.error))")
        let match = try #require(result.data?.asObject?["tools"]?.asArray?.first?.asObject)
        let id = try #require(match["name"]?.asString)
        #expect(match["parameters"]?.asObject?["required"] == .array([.string("projectKey")]))
        #expect(result.data?.asObject?["metrics"]?.asObject?["returnedSchemas"] == .number(1))
        #expect(result.data?.asObject?["metrics"]?.asObject?["catalogComplete"] == .bool(true))
        var arguments = try #require(match["invocation"]?.asObject?["arguments"]?.asObject)
        arguments["arguments"] = .string(#"{"projectKey":"SLOPPY"}"#)
        let request = ToolInvocationRequest(tool: "mcp.call_tool", arguments: arguments)
        let called = await service.invokeToolFromRuntime(agentID: "dev", sessionID: session.id, request: request)
        #expect(called.ok, "\(String(describing: called.error))")
        #expect(called.data?.asObject?["content"]?.asArray?.first?.asObject?["text"]?.asString?.contains("SLOPPY") == true)
        let detail = try await service.getAgentSession(agentID: "dev", sessionID: session.id)
        let persisted = detail.events.compactMap(\.toolResult).first { $0.tool == "system.search_tools" }
        #expect(persisted?.data?.asObject?["metrics"]?.asObject?["returnedSchemas"] == .number(1))
        _ = try await service.updateAgentToolsPolicy(agentID: "dev", request: .init(tools: [id: false], approval: .init(untrustedContextGuard: .off)))
        let rejected = await service.invokeToolFromRuntime(agentID: "dev", sessionID: session.id, request: request)
        #expect(rejected.error?.code == "tool_forbidden")
        let hidden = await service.invokeToolFromRuntime(agentID: "dev", sessionID: session.id,
            request: .init(tool: "system.search_tools", arguments: ["ids": .array([.string(id)])]))
        #expect(hidden.data?.asObject?["tools"] == .array([]))
        await service.clearDiscoveryFixtureServers()
        let removed = await service.invokeToolFromRuntime(agentID: "dev", sessionID: session.id, request: request)
        #expect(removed.error?.code == "unknown_tool")
    }

    @Test("A delegated session cannot discover or call a target outside its allowlist")
    func delegatedScope() async throws {
        let (root, config) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        _ = try await service.createAgent(.init(id: "dev", displayName: "Dev", role: "Developer", isSystem: false))
        _ = try await service.updateAgentToolsPolicy(agentID: "dev", request: .init(approval: .init(untrustedContextGuard: .off)))
        let session = try await service.createAgentSession(agentID: "dev", request: .init(title: "Scoped"))
        await service.setSessionToolApprovalRequired(sessionID: session.id, enabled: false)
        await service.setDiscoveryFixtureScope(session.id, ids: ["system.search_tools", "mcp.call_tool"])
        let found = await service.invokeToolFromRuntime(agentID: "dev", sessionID: session.id,
            request: .init(tool: "system.search_tools", arguments: ["server": .string("tracker")]))
        #expect(found.ok)
        #expect(found.data?.asObject?["tools"] == .array([]))
        let called = await service.invokeToolFromRuntime(agentID: "dev", sessionID: session.id,
            request: .init(tool: "mcp.call_tool", arguments: ["server": .string("tracker"), "tool": .string("search_issues"), "arguments": .string("{}")]))
        #expect(called.error?.code == "tool_forbidden")
        await service.clearDiscoveryFixtureServers()
    }

    @Test("Failed MCP discovery is explicitly incomplete, not an authoritative no-match result")
    func incompleteCatalog() async throws {
        var config = CoreConfig.test
        config.mcp = .init(servers: [.init(id: "broken", transport: .stdio, command: "/sloppy-test-no-such-command", timeoutMs: 250)])
        let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        _ = try await service.createAgent(.init(id: "dev", displayName: "Dev", role: "Developer", isSystem: false))
        let session = try await service.createAgentSession(agentID: "dev", request: .init(title: "Incomplete"))
        let found = await service.invokeToolFromRuntime(agentID: "dev", sessionID: session.id,
            request: .init(tool: "system.search_tools", arguments: ["server": .string("broken")]))
        #expect(found.ok)
        #expect(found.data?.asObject?["metrics"]?.asObject?["catalogComplete"] == .bool(false))
        #expect(found.data?.asObject?["tools"] == .array([]))
    }
}

private extension CoreService {
    func setDiscoveryFixtureScope(_ sessionID: String, ids: Set<String>) {
        sessionSubagentToolAllowList[sessionID] = ids
    }

    func clearDiscoveryFixtureServers() async {
        await mcpRegistry.updateConfig(.init())
    }
}
