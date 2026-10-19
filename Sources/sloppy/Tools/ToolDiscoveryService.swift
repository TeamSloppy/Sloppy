import Foundation
import AgentRuntime
import Metrics
import Protocols

/// Discovery is a read-only projection of the catalog, never a grant or native-tool registration.
struct ToolDiscoveryEntry: Sendable {
    var id: String
    var title: String
    var description: String
    var parameterNames: [String]
    var mcp: MCPDynamicTool?

    var summary: JSONValue {
        var value: [String: JSONValue] = [
            "name": .string(id), "title": .string(String(title.prefix(160))),
            "description": .string(description.split(whereSeparator: \.isNewline).first.map { String($0.prefix(240)) } ?? ""),
            "source": .string(mcp == nil ? "builtin" : "mcp"),
        ]
        if let mcp {
            value["invocation"] = .object([
                "name": .string("mcp.call_tool"),
                "arguments": .object(["server": .string(mcp.serverID), "tool": .string(mcp.toolName)]),
            ])
        }
        return .object(value)
    }
}

extension ToolCatalog {
    static func discoveryEntries(mcpRegistry: (any MCPToolDiscovering)?) async -> [ToolDiscoveryEntry] {
        let builtIns = builtInEntries.map { entry in
            let schema = builtInRegistry.tool(for: entry.id).flatMap { tool -> JSONValue? in
                guard let data = try? JSONEncoder().encode(tool.parameters) else { return nil }
                return try? JSONDecoder().decode(JSONValue.self, from: data)
            }
            return ToolDiscoveryEntry(id: entry.id, title: entry.title, description: entry.description,
                parameterNames: schema?.asObject?["properties"]?.asObject?.keys.sorted() ?? [], mcp: nil)
        }
        let dynamic = await (mcpRegistry?.dynamicTools() ?? []).map { tool in
            ToolDiscoveryEntry(id: tool.id, title: tool.title, description: tool.description,
                parameterNames: tool.inputSchema.asObject?["properties"]?.asObject?.keys.sorted() ?? [], mcp: tool)
        }
        return (builtIns + dynamic).sorted { $0.id < $1.id }
    }
}

struct ToolDiscoveryQuery: Sendable {
    var query: String
    var ids: Set<String>
    var server: String?
    var limit: Int
    var offset: Int
    var includeSchemas: Bool

    enum ValidationError: Error { case invalidArguments }

    init(arguments: [String: JSONValue]) throws {
        func string(_ key: String) throws -> String? {
            guard let value = arguments[key] else { return nil }
            guard let text = value.asString, text.count <= 512 else { throw ValidationError.invalidArguments }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func integer(_ key: String, default fallback: Int, range: ClosedRange<Int>) throws -> Int {
            guard let value = arguments[key] else { return fallback }
            guard let number = value.asNumber, number.isFinite, number.rounded(.towardZero) == number,
                  number >= Double(range.lowerBound), number <= Double(range.upperBound) else {
                throw ValidationError.invalidArguments
            }
            return Int(number)
        }
        query = try string("query") ?? ""
        server = try string("server")
        if let server, server.isEmpty { throw ValidationError.invalidArguments }
        let rawIDs = arguments["ids"]?.asArray ?? []
        if arguments["ids"] != nil && arguments["ids"]?.asArray == nil { throw ValidationError.invalidArguments }
        guard rawIDs.count <= 10, rawIDs.allSatisfy({ $0.asString != nil }) else { throw ValidationError.invalidArguments }
        ids = Set(rawIDs.compactMap(\.asString).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        guard !ids.contains(""), ids.allSatisfy({ $0.count <= 512 }),
              query.isEmpty || ids.isEmpty, !query.isEmpty || !ids.isEmpty || server != nil else {
            throw ValidationError.invalidArguments
        }
        limit = try integer("limit", default: 5, range: 1...10)
        offset = try integer("offset", default: 0, range: 0...100_000)
        if let value = arguments["includeSchemas"], value.asBool == nil { throw ValidationError.invalidArguments }
        includeSchemas = arguments["includeSchemas"]?.asBool ?? true
    }
}

struct ToolDiscoveryMetrics: Codable, Sendable {
    var catalogTools: Int
    var matchedTools: Int
    var returnedTools: Int
    var returnedSchemas: Int
    var schemaBudgetOmissions: Int
    var catalogMCPSchemaEstimatedTokens: Int
    var returnedSchemaEstimatedTokens: Int
    var durationMs: Double = 0
    var catalogComplete: Bool = true

    func record() {
        let dimensions = [("outcome", catalogComplete ? (matchedTools == 0 ? "empty" : "matched") : "incomplete")]
        Counter(label: "sloppy.tool.discovery.requests", dimensions: dimensions).increment()
        Counter(label: "sloppy.tool.discovery.schemas_returned").increment(by: returnedSchemas)
        Counter(label: "sloppy.tool.discovery.schema_budget_omissions").increment(by: schemaBudgetOmissions)
        Recorder(label: "sloppy.tool.discovery.catalog_tools").record(catalogTools)
        Recorder(label: "sloppy.tool.discovery.matched_tools").record(matchedTools)
        Recorder(label: "sloppy.tool.discovery.catalog_mcp_schema_estimated_tokens").record(catalogMCPSchemaEstimatedTokens)
        Recorder(label: "sloppy.tool.discovery.returned_schema_estimated_tokens").record(returnedSchemaEstimatedTokens)
        Metrics.Timer(label: "sloppy.tool.discovery.duration").recordMilliseconds(durationMs)
    }
}

struct ToolDiscoveryResult: Sendable {
    var tools: [JSONValue]
    var nextOffset: Int?
    var metrics: ToolDiscoveryMetrics

    var payload: JSONValue {
        let encodedMetrics = (try? JSONEncoder().encode(metrics)).flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
        return .object([
            "tools": .array(tools), "nextOffset": nextOffset.map { .number(Double($0)) } ?? .null,
            "metrics": encodedMetrics ?? .null,
        ])
    }
}

enum ToolDiscoveryService {
    /// Wrapper and target must both be allowed; an explicit session scope is an intersection.
    static func isVisible(_ entry: ToolDiscoveryEntry, policy: AgentToolsPolicy, allowedIDs: Set<String>?) -> Bool {
        guard SubagentDelegation.isToolAllowedByPolicy(toolID: entry.id, policy: policy),
              allowedIDs.map({ $0.contains(entry.id) }) ?? true else { return false }
        if entry.mcp != nil {
            guard !ToolCatalog.knownToolIDs.contains(entry.id) else { return false }
            return SubagentDelegation.isToolAllowedByPolicy(toolID: "mcp.call_tool", policy: policy) &&
                (allowedIDs.map { $0.contains("mcp.call_tool") } ?? true)
        }
        return true
    }

    static func search(_ query: ToolDiscoveryQuery, entries: [ToolDiscoveryEntry], policy: AgentToolsPolicy,
                       allowedIDs: Set<String>? = nil, maxOutputBytes: Int = 24 * 1024) -> ToolDiscoveryResult {
        let visible = entries.filter { isVisible($0, policy: policy, allowedIDs: allowedIDs) }
        let ranked = visible.compactMap { entry -> (ToolDiscoveryEntry, Int)? in
            if let server = query.server, entry.mcp?.serverID != server { return nil }
            if !query.ids.isEmpty { return query.ids.contains(entry.id) ? (entry, 1_000) : nil }
            guard let score = score(query.query, entry: entry) else { return nil }
            return (entry, score)
        }.sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 > $1.1 }
        let estimator = TokenPressureEstimator()
        func tokens(_ schema: JSONValue) -> Int {
            estimator.estimateTextTokens(String(decoding: encodedJSON(schema), as: UTF8.self))
        }
        var metrics = ToolDiscoveryMetrics(catalogTools: visible.count, matchedTools: ranked.count,
            returnedTools: 0, returnedSchemas: 0, schemaBudgetOmissions: 0,
            catalogMCPSchemaEstimatedTokens: visible.compactMap(\.mcp).reduce(0) { $0 + tokens($1.inputSchema) },
            returnedSchemaEstimatedTokens: 0)
        // Reserve space for result metadata and summaries. Never truncate a JSON schema.
        let budget = max(0, min(24 * 1024, maxOutputBytes) - 2_048)
        var used = 0
        var results: [JSONValue] = []
        for (entry, _) in ranked.dropFirst(query.offset).prefix(query.limit) {
            var value = entry.summary.asObject ?? [:]
            if let mcp = entry.mcp, query.includeSchemas {
                var withSchema = value
                withSchema["parameters"] = mcp.inputSchema
                withSchema["schemaStatus"] = .string("included")
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let data = (try? encoder.encode(mcp.inputSchema)) ?? Data()
                withSchema["definitionHash"] = .string(TaskSyncCrypto.sha256Hex(data))
                let bytes = encodedJSON(.object(withSchema)).count
                if used + bytes <= budget {
                    value = withSchema
                    metrics.returnedSchemas += 1
                    metrics.returnedSchemaEstimatedTokens += tokens(mcp.inputSchema)
                } else {
                    value["schemaStatus"] = .string("omitted_budget")
                    metrics.schemaBudgetOmissions += 1
                }
            }
            let result = JSONValue.object(value)
            guard used + encodedJSON(result).count <= budget else { break }
            used += encodedJSON(result).count
            results.append(result)
        }
        metrics.returnedTools = results.count
        let next = query.offset + results.count
        return ToolDiscoveryResult(tools: results, nextOffset: next < ranked.count ? next : nil, metrics: metrics)
    }

    static func encodedJSON(_ value: JSONValue) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)) ?? Data()
    }

    private static func score(_ query: String, entry: ToolDiscoveryEntry) -> Int? {
        let query = query.lowercased()
        if query.isEmpty { return 0 }
        if entry.id.lowercased() == query || entry.mcp?.toolName.lowercased() == query { return 10_000 }
        let terms = query.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard !terms.isEmpty else { return nil }
        let fields = [(entry.id.lowercased(), 100), (entry.title.lowercased(), 40),
                      (entry.parameterNames.joined(separator: " ").lowercased(), 25), (entry.description.lowercased(), 10)]
        var score = 0
        for term in terms {
            guard let weight = fields.first(where: { $0.0.contains(term) })?.1 else { return nil }
            score += weight
        }
        return score
    }
}
