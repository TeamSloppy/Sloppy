import Foundation
import AnyLanguageModel
import Logging
import Metrics
import Protocols

struct SystemSearchToolsTool: CoreTool {
    let domain = "system"
    let title = "Search tools"
    let status = "fully_functional"
    let name = "system.search_tools"
    let description = "Optional targeted search of the permitted built-in and MCP catalog by name, description, or argument names. Use when the user requests catalog search; default MCP discovery uses mcp.list_tools. Returns compact summaries and only matching MCP schemas. Call returned MCP tools with mcp.call_tool using invocation.arguments.server/tool and your arguments JSON. Built-in results are summaries only; search does not register native tools or grant permissions."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "query", description: "Lexical search, up to 512 characters; use query or ids, not both", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "ids", description: "Up to 10 exact canonical tool IDs", schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)), isOptional: true),
            .init(name: "server", description: "Optional MCP server ID; server alone lists that server's permitted tools", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "limit", description: "Results per page, 1-10; default 5", schema: DynamicGenerationSchema(type: Int.self), isOptional: true),
            .init(name: "offset", description: "Pagination offset from nextOffset; default 0", schema: DynamicGenerationSchema(type: Int.self), isOptional: true),
            .init(name: "includeSchemas", description: "Include full selected MCP schemas (default true); false returns compact summaries only", schema: DynamicGenerationSchema(type: Bool.self), isOptional: true),
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let query: ToolDiscoveryQuery
        do { query = try ToolDiscoveryQuery(arguments: arguments) }
        catch {
            Counter(label: "sloppy.tool.discovery.requests", dimensions: [("outcome", "invalid_arguments")]).increment()
            return toolFailure(tool: name, code: "invalid_arguments", message: "Supply query or ids (not both), or server. limit must be 1-10, offset nonnegative, and includeSchemas boolean.", retryable: false)
        }
        let started = ContinuousClock.now
        let entries = await ToolCatalog.discoveryEntries(mcpRegistry: context.mcpRegistry)
        var result = ToolDiscoveryService.search(query, entries: entries, policy: context.policy,
            allowedIDs: context.discoveryAllowedToolIDs, maxOutputBytes: context.policy.guardrails.maxExecOutputBytes)
        let elapsed = started.duration(to: .now).components
        result.metrics.durationMs = Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
        result.metrics.catalogComplete = await context.mcpRegistry.dynamicDiscoveryIsComplete()
        result.metrics.record()
        context.logger.info("Tool discovery completed", metadata: [
            "agent_id": .string(context.agentID), "session_id": .string(context.sessionID),
            "matched_tools": .stringConvertible(result.metrics.matchedTools),
            "returned_schemas": .stringConvertible(result.metrics.returnedSchemas),
            "schema_budget_omissions": .stringConvertible(result.metrics.schemaBudgetOmissions),
            "duration_ms": .stringConvertible(result.metrics.durationMs),
        ])
        if result.tools.isEmpty, result.metrics.matchedTools > query.offset {
            return toolFailure(tool: name, code: "discovery_output_limit", message: "The tool output budget is too small to return a catalog entry.", retryable: false)
        }
        return toolSuccess(tool: name, data: result.payload)
    }
}
