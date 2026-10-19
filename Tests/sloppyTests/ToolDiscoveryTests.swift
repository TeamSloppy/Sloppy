import Foundation
import Testing
import PluginSDK
@testable import AgentRuntime
@testable import Protocols
@testable import sloppy

@Suite("Tool discovery")
struct ToolDiscoveryTests {
    private let schema: JSONValue = .object([
        "type": .string("object"), "required": .array([.string("projectKey")]),
        "properties": .object(["projectKey": .object(["type": .string("string")])]),
        "additionalProperties": .bool(false),
    ])

    private func entry(_ id: String, description: String = "Find project issues", schema: JSONValue? = nil) -> ToolDiscoveryEntry {
        let tool = MCPDynamicTool(id: id, serverID: "tracker", toolName: id,
            title: "Search issues", description: description, inputSchema: schema ?? self.schema)
        return ToolDiscoveryEntry(id: id, title: tool.title, description: description,
            parameterNames: ["projectKey"], mcp: tool)
    }

    @Test("Exact names outrank lexical matches; all query terms and argument names participate")
    func rankingAndParameterNames() throws {
        let entries = [entry("mcp.tracker.z"), entry("mcp.tracker.a"),
            entry("mcp.tracker.search", description: "Unrelated description")]
        let exact = ToolDiscoveryService.search(try .init(arguments: ["query": .string("mcp.tracker.search")]),
            entries: entries, policy: .init())
        #expect(exact.tools.first?.asObject?["name"] == .string("mcp.tracker.search"))
        let query = try ToolDiscoveryQuery(arguments: ["query": .string("PROJECTKEY issues")])
        let forward = ToolDiscoveryService.search(query, entries: entries, policy: .init())
        let reverse = ToolDiscoveryService.search(query, entries: Array(entries.reversed()), policy: .init())
        #expect(forward.tools == reverse.tools)
        #expect(forward.tools.first?.asObject?["name"] == .string("mcp.tracker.a"))
        let empty = ToolDiscoveryService.search(try .init(arguments: ["query": .string("projectKey missingterm")]),
            entries: entries, policy: .init())
        #expect(empty.tools.isEmpty)
        #expect(empty.metrics.matchedTools == 0)
    }

    @Test("Filter target, wrapper and delegated scope before emitting entries or metrics")
    func visibility() throws {
        let allowed = entry("mcp.tracker.allowed")
        let hidden = entry("mcp.tracker.hidden")
        var policy = AgentToolsPolicy()
        policy.defaultPolicy = .deny
        policy.tools = [allowed.id: true, "mcp.call_tool": true]
        let query = try ToolDiscoveryQuery(arguments: ["server": .string("tracker")])
        let found = ToolDiscoveryService.search(query, entries: [hidden, allowed], policy: policy)
        #expect(found.tools.count == 1)
        #expect(found.metrics.catalogTools == 1)
        #expect(found.metrics.matchedTools == 1)
        #expect(found.metrics.catalogMCPSchemaEstimatedTokens == found.metrics.returnedSchemaEstimatedTokens)
        #expect(ToolDiscoveryService.search(query, entries: [allowed], policy: policy, allowedIDs: []).tools.isEmpty)
        #expect(ToolDiscoveryService.search(query, entries: [allowed], policy: policy, allowedIDs: ["mcp.call_tool"]).tools.isEmpty)
        #expect(ToolDiscoveryService.search(query, entries: [allowed], policy: policy, allowedIDs: [allowed.id]).tools.isEmpty)
        #expect(ToolDiscoveryService.search(query, entries: [allowed], policy: policy,
            allowedIDs: [allowed.id, "mcp.call_tool"]).tools.count == 1)
        #expect(!ToolDiscoveryService.isVisible(entry("files.read"), policy: .init(), allowedIDs: nil))
        policy.tools["mcp.call_tool"] = false
        #expect(ToolDiscoveryService.search(query, entries: [allowed], policy: policy).tools.isEmpty)
    }

    @Test("Return the complete MCP schema and invocation route; compact mode omits schemas")
    func selectedSchema() throws {
        let item = entry("mcp.tracker.search", description: "First line\nSecond line")
        let query = try ToolDiscoveryQuery(arguments: ["ids": .array([.string(item.id)])])
        let result = ToolDiscoveryService.search(query, entries: [item], policy: .init())
        let match = try #require(result.tools.first?.asObject)
        #expect(match["parameters"] == schema)
        #expect(match["description"] == .string("First line"))
        #expect(match["definitionHash"]?.asString?.count == 64)
        #expect(match["invocation"]?.asObject?["name"] == .string("mcp.call_tool"))
        #expect(match["invocation"]?.asObject?["arguments"]?.asObject?["tool"] == .string(item.id))
        #expect(result.metrics.returnedSchemas == 1)
        #expect(result.metrics.returnedSchemaEstimatedTokens > 0)
        let compact = ToolDiscoveryService.search(try .init(arguments: ["ids": .array([.string(item.id)]), "includeSchemas": .bool(false)]),
            entries: [item], policy: .init())
        #expect(compact.tools.first?.asObject?["parameters"] == nil)
        #expect(compact.metrics.returnedSchemas == 0)
    }

    @Test("Oversized schemas are omitted whole; output is bounded and pages have an explicit continuation")
    func budgetAndPagination() throws {
        let oversized = entry("mcp.tracker.a", schema: .object(["description": .string(String(repeating: "x", count: 40_000))]))
        let entries = [entry("mcp.tracker.b"), oversized, entry("mcp.tracker.c")]
        let first = ToolDiscoveryService.search(try .init(arguments: ["server": .string("tracker"), "limit": .number(1)]),
            entries: entries, policy: .init())
        #expect(first.tools.count == 1)
        #expect(first.tools[0].asObject?["schemaStatus"] == .string("omitted_budget"))
        #expect(first.tools[0].asObject?["parameters"] == nil)
        #expect(first.metrics.schemaBudgetOmissions == 1)
        #expect(ToolDiscoveryService.encodedJSON(first.payload).count < 24 * 1024)
        #expect(first.nextOffset == 1)
        let rest = ToolDiscoveryService.search(try .init(arguments: ["server": .string("tracker"), "offset": .number(1)]),
            entries: entries, policy: .init())
        #expect(rest.tools.count == 2)
        #expect(rest.nextOffset == nil)
        let tiny = ToolDiscoveryService.search(try .init(arguments: ["server": .string("tracker")]),
            entries: entries, policy: .init(), maxOutputBytes: 1)
        #expect(tiny.tools.isEmpty)
        #expect(tiny.nextOffset == 0)
    }

    @Test("Invalid selectors, types and bounds fail before search")
    func validation() {
        let cases: [[String: JSONValue]] = [
            [:], ["query": .string(" ")], ["query": .bool(true)],
            ["query": .string("x"), "ids": .array([.string("x")])],
            ["ids": .string("x")], ["ids": .array([.number(1)])], ["ids": .array([.string("")])],
            ["query": .string("x"), "limit": .number(11)],
            ["query": .string("x"), "limit": .number(1.5)],
            ["query": .string("x"), "limit": .number(1e200)],
            ["query": .string("x"), "offset": .number(.infinity)],
            ["query": .string("x"), "offset": .number(-1)],
            ["query": .string("x"), "includeSchemas": .string("true")],
        ]
        for arguments in cases {
            #expect(throws: ToolDiscoveryQuery.ValidationError.self) { try ToolDiscoveryQuery(arguments: arguments) }
        }
    }

    @Test("Built-in discovery uses implementation argument names without exposing native schemas")
    func builtInSummaries() async throws {
        let entries = await ToolCatalog.discoveryEntries(mcpRegistry: nil)
        let query = try ToolDiscoveryQuery(arguments: ["ids": .array([.string("system.search_tools")])])
        let result = ToolDiscoveryService.search(query, entries: entries, policy: .init())
        #expect(result.tools.first?.asObject?["source"] == .string("builtin"))
        #expect(result.tools.first?.asObject?["parameters"] == nil)
        let item = try #require(entries.first { $0.id == "system.search_tools" })
        #expect(item.parameterNames.contains("includeSchemas"))
        #expect(ToolConcurrencyPolicy.readOnlyToolIDs.contains("system.search_tools"))
        #expect(UntrustedContextGuard.producesUntrustedOutput(toolID: "system.search_tools"))
    }
}
