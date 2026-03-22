import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging
import Protocols

public struct MemoryProviderCapabilities: Codable, Sendable, Equatable {
    public var supportsSemanticSearch: Bool
    public var supportsFullText: Bool
    public var supportsDelete: Bool
    public var providerOwnsEmbeddings: Bool

    public init(
        supportsSemanticSearch: Bool,
        supportsFullText: Bool,
        supportsDelete: Bool,
        providerOwnsEmbeddings: Bool
    ) {
        self.supportsSemanticSearch = supportsSemanticSearch
        self.supportsFullText = supportsFullText
        self.supportsDelete = supportsDelete
        self.providerOwnsEmbeddings = providerOwnsEmbeddings
    }
}

public struct MemoryProviderDocument: Codable, Sendable, Equatable {
    public var id: String
    public var text: String
    public var summary: String?
    public var kind: MemoryKind
    public var memoryClass: MemoryClass
    public var scope: MemoryScope
    public var source: MemorySource?
    public var metadata: [String: JSONValue]
    public var createdAt: Date

    public init(
        id: String,
        text: String,
        summary: String? = nil,
        kind: MemoryKind,
        memoryClass: MemoryClass,
        scope: MemoryScope,
        source: MemorySource? = nil,
        metadata: [String: JSONValue] = [:],
        createdAt: Date
    ) {
        self.id = id
        self.text = text
        self.summary = summary
        self.kind = kind
        self.memoryClass = memoryClass
        self.scope = scope
        self.source = source
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

public struct MemoryProviderQuery: Codable, Sendable, Equatable {
    public var query: String
    public var limit: Int
    public var scope: MemoryScope?

    public init(query: String, limit: Int, scope: MemoryScope? = nil) {
        self.query = query
        self.limit = limit
        self.scope = scope
    }
}

public struct MemoryProviderQueryResult: Codable, Sendable, Equatable {
    public var id: String
    public var score: Double
    public var kind: MemoryKind?
    public var memoryClass: MemoryClass?
    public var source: MemorySource?
    public var createdAt: Date?

    public init(
        id: String,
        score: Double,
        kind: MemoryKind? = nil,
        memoryClass: MemoryClass? = nil,
        source: MemorySource? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.score = score
        self.kind = kind
        self.memoryClass = memoryClass
        self.source = source
        self.createdAt = createdAt
    }
}

public protocol MemoryProvider: Sendable {
    var id: String { get }
    var capabilities: MemoryProviderCapabilities { get }

    func upsert(document: MemoryProviderDocument) async throws
    func query(request: MemoryProviderQuery) async throws -> [MemoryProviderQueryResult]
    func delete(id: String) async throws
    func health() async -> Bool
}

enum MemoryProviderError: Error {
    case notConfigured
    case unsupported
    case transportFailure
    case invalidResponse
}

actor SQLiteFallbackProvider: MemoryProvider {
    let id: String = "sqlite-fallback"
    let capabilities = MemoryProviderCapabilities(
        supportsSemanticSearch: false,
        supportsFullText: true,
        supportsDelete: true,
        providerOwnsEmbeddings: true
    )

    private var index: [String: MemoryProviderDocument] = [:]

    func upsert(document: MemoryProviderDocument) async throws {
        index[document.id] = document
    }

    func query(request: MemoryProviderQuery) async throws -> [MemoryProviderQueryResult] {
        let normalizedQuery = request.query
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return []
        }
        let terms = queryTerms(from: normalizedQuery)
        let candidates = index.values.filter { document in
            if let scope = request.scope,
               (document.scope.type != scope.type || document.scope.id != scope.id) {
                return false
            }
            return true
        }

        return candidates
            .compactMap { document -> MemoryProviderQueryResult? in
                let content = (document.text + " " + (document.summary ?? "")).lowercased()
                let score = relevanceScore(content: content, normalizedQuery: normalizedQuery, terms: terms)
                guard score > 0 else {
                    return nil
                }
                return MemoryProviderQueryResult(
                    id: document.id,
                    score: score,
                    kind: document.kind,
                    memoryClass: document.memoryClass,
                    source: document.source,
                    createdAt: document.createdAt
                )
            }
            .sorted { $0.score > $1.score }
            .prefix(max(1, request.limit))
            .map { $0 }
    }

    func delete(id: String) async throws {
        index[id] = nil
    }

    func health() async -> Bool {
        true
    }

    private func queryTerms(from query: String) -> [String] {
        query
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 }
    }

    private func relevanceScore(content: String, normalizedQuery: String, terms: [String]) -> Double {
        if content.contains(normalizedQuery) {
            return 0.8
        }

        let uniqueTerms = Array(Set(terms))
        guard !uniqueTerms.isEmpty else {
            return 0
        }

        let matchedCount = uniqueTerms.reduce(into: 0) { result, term in
            if content.contains(term) {
                result += 1
            }
        }
        guard matchedCount > 0 else {
            return 0
        }

        let ratio = Double(matchedCount) / Double(uniqueTerms.count)
        return min(0.75, 0.4 + ratio * 0.35)
    }
}

actor HTTPMemoryProviderAdapter: MemoryProvider {
    let id: String = "http"
    let capabilities = MemoryProviderCapabilities(
        supportsSemanticSearch: true,
        supportsFullText: true,
        supportsDelete: true,
        providerOwnsEmbeddings: true
    )

    private let endpoint: URL
    private let timeoutMs: Int
    private let apiKeyEnv: String?

    init(endpoint: URL, timeoutMs: Int, apiKeyEnv: String?) {
        self.endpoint = endpoint
        self.timeoutMs = timeoutMs
        self.apiKeyEnv = apiKeyEnv
    }

    func upsert(document: MemoryProviderDocument) async throws {
        _ = try await send(path: "memory/upsert", payload: document)
    }

    func query(request: MemoryProviderQuery) async throws -> [MemoryProviderQueryResult] {
        let response = try await send(path: "memory/query", payload: request)
        guard let data = response.dataValue else {
            throw MemoryProviderError.invalidResponse
        }
        return try JSONDecoder().decode([MemoryProviderQueryResult].self, from: data)
    }

    func delete(id: String) async throws {
        struct DeletePayload: Codable {
            let id: String
        }
        _ = try await send(path: "memory/delete", payload: DeletePayload(id: id))
    }

    func health() async -> Bool {
        do {
            let response = try await send(path: "memory/health", payload: EmptyPayload())
            return response.statusCode == 200
        } catch {
            return false
        }
    }

    private func send(path: String, payload: some Codable) async throws -> (statusCode: Int, dataValue: Data?) {
        var url = endpoint
        if !url.absoluteString.hasSuffix("/") {
            url = URL(string: endpoint.absoluteString + "/") ?? endpoint
        }
        let target = url.appendingPathComponent(path)
        var request = URLRequest(url: target)
        request.httpMethod = "POST"
        request.timeoutInterval = TimeInterval(max(250, timeoutMs)) / 1_000
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        if let apiKeyEnv,
           let key = ProcessInfo.processInfo.environment[apiKeyEnv],
           !key.isEmpty {
            request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MemoryProviderError.transportFailure
        }
        if httpResponse.statusCode >= 400 {
            throw MemoryProviderError.transportFailure
        }
        return (httpResponse.statusCode, data)
    }

    private struct EmptyPayload: Codable {}
}

actor MCPMemoryProviderAdapter: MemoryProvider {
    let id: String
    let capabilities = MemoryProviderCapabilities(
        supportsSemanticSearch: true,
        supportsFullText: true,
        supportsDelete: true,
        providerOwnsEmbeddings: true
    )

    private let server: String
    private let tools: CoreConfig.Memory.Provider.MCPTools
    private let registry: MCPClientRegistry

    init(server: String, tools: CoreConfig.Memory.Provider.MCPTools, registry: MCPClientRegistry) {
        self.server = server
        self.tools = tools
        self.registry = registry
        id = "mcp:\(server)"
    }

    func upsert(document: MemoryProviderDocument) async throws {
        let payload = encodeJSONValue(document)
        _ = try await registry.callTool(
            serverID: server,
            name: tools.upsert,
            arguments: ["document": payload]
        )
    }

    func query(request: MemoryProviderQuery) async throws -> [MemoryProviderQueryResult] {
        try await registry.decodeJSONTextResult(
            serverID: server,
            toolName: tools.query,
            arguments: ["request": encodeJSONValue(request)],
            as: [MemoryProviderQueryResult].self
        )
    }

    func delete(id: String) async throws {
        _ = try await registry.callTool(
            serverID: server,
            name: tools.delete,
            arguments: ["id": .string(id)]
        )
    }

    func health() async -> Bool {
        do {
            let result = try await registry.callTool(
                serverID: server,
                name: tools.health,
                arguments: [:]
            )
            if result.isError == true {
                return false
            }
            let flattened = MCPClientRegistry.flattenText(from: result.content)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return flattened.isEmpty || flattened == "ok" || flattened == "true"
        } catch {
            return false
        }
    }

    private func encodeJSONValue<T: Encodable>(_ value: T) -> JSONValue {
        guard let data = try? JSONEncoder().encode(value),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data)
        else {
            return .null
        }
        return json
    }
}

enum MemoryProviderRegistry {
    static func makeProvider(config: CoreConfig, mcpRegistry: MCPClientRegistry, logger: Logger) -> (any MemoryProvider)? {
        let memory = config.memory
        switch memory.provider.mode {
        case .local:
            logger.info("Memory provider: using built-in local provider")
            return SQLiteFallbackProvider()
        case .http:
            guard
                let endpointRaw = memory.provider.endpoint,
                !endpointRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                let endpoint = parseEndpoint(endpointRaw)
            else {
                logger.warning("Memory provider mode is http but endpoint is missing. Falling back to local provider.")
                return SQLiteFallbackProvider()
            }
            logger.info("Memory provider: using remote HTTP endpoint \(endpoint.absoluteString)")
            return HTTPMemoryProviderAdapter(
                endpoint: endpoint,
                timeoutMs: memory.provider.timeoutMs,
                apiKeyEnv: memory.provider.apiKeyEnv
            )
        case .mcp:
            guard let server = memory.provider.mcpServer,
                  !server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                logger.warning("Memory provider mode is mcp but mcpServer is missing. Falling back to local provider.")
                return SQLiteFallbackProvider()
            }
            logger.info("Memory provider: using remote MCP server \(server)")
            return MCPMemoryProviderAdapter(
                server: server,
                tools: memory.provider.mcpTools,
                registry: mcpRegistry
            )
        }
    }

    private static func parseEndpoint(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if let url = URL(string: trimmed),
           url.scheme != nil {
            return url
        }
        return URL(string: "http://\(trimmed)")
    }
}
