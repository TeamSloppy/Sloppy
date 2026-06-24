# Dashboard Memory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Dashboard Memory section that lists all agent-written memory, shows a relationship graph, and imports dropped text files into global/project/agent memory through Visor.

**Architecture:** Add general memory APIs in CoreService and the HTTP routers, keeping existing agent/project APIs as compatibility wrappers. Add a shadow Visor import operation that validates an explicit target scope, runs with Visor model settings, records `memory.save` tool results, and returns structured created/skipped rows. Refactor the Dashboard memory UI into shared feature components used by the new top-level `/memory` route and the existing project/agent memory tabs.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftPM, React 19, TypeScript, Vite, `vis-network/standalone`, existing Core API client.

## Global Constraints

- Use Swift Testing macros (`@Test`, `#expect`).
- Preserve existing Dashboard formatting: 2-space indent, semicolons, double quotes.
- Do not use native `<select>` elements for new dropdown/select UI; use the existing custom `.actor-team-search` pattern if a dropdown is needed.
- Do not infer behavior from natural-language model output; import results must come from structured tool call records.
- `memory.save` calls must always use an explicit scope.
- Text imports must reject empty content and oversized content in both UI and backend.
- Do not introduce new frameworks.
- Keep existing agent and project memory routes backward-compatible.

---

## File Structure

Create:

- `Dashboard/src/features/memory/MemoryView.tsx`: top-level `/memory` route view with global scope.
- `Dashboard/src/features/memory/MemoryBrowser.tsx`: shared list/graph/search/pagination shell.
- `Dashboard/src/features/memory/MemoryGraph.tsx`: shared `vis-network` renderer and graph settings.
- `Dashboard/src/features/memory/MemoryImportDropzone.tsx`: shared drag/drop and file picker.
- `Dashboard/src/features/memory/memoryModel.ts`: shared types, normalizers, labels, date helpers.
- `Dashboard/src/styles/memory.css`: shared memory UI styles.
- `Tests/sloppyTests/MemoryAPITests.swift`: general memory list/graph/import router tests.

Modify:

- `Sources/Protocols/APIModels.swift`: add general memory API request/response DTOs.
- `Sources/sloppy/CoreService+Agents.swift`: extract general memory list/graph helpers and keep agent/project wrappers.
- `Sources/sloppy/CoreService+MemoryCheckpoint.swift`: add Visor-powered memory import helper alongside checkpoint logic.
- `Sources/sloppy/Gateway/Routers/SystemAPIRouter.swift`: register `/v1/memories`, `/v1/memories/graph`, `/v1/memories/import`.
- `Dashboard/src/shared/api/coreApi.ts`: add general memory client methods.
- `Dashboard/src/api.ts`: re-export general memory client methods.
- `Dashboard/src/app/routing/dashboardRouteAdapter.ts`: add `memory` top-level section.
- `Dashboard/src/App.tsx`: add sidebar item and render `MemoryView`.
- `Dashboard/src/styles/index.css`: import `memory.css`.
- `Dashboard/src/features/agents/components/AgentMemoriesTab.tsx`: delegate to shared memory browser/importer.
- `Dashboard/src/views/Projects/ProjectMemoryTab.tsx`: delegate to shared memory browser/importer.

---

### Task 1: General Memory List And Graph API

**Files:**
- Modify: `Sources/Protocols/APIModels.swift`
- Modify: `Sources/sloppy/CoreService+Agents.swift`
- Modify: `Sources/sloppy/Gateway/Routers/SystemAPIRouter.swift`
- Test: `Tests/sloppyTests/MemoryAPITests.swift`

**Interfaces:**
- Produces: `MemoryListResponse`, `MemoryGraphResponse`, `MemoryScopeQuery`, `CoreService.listMemories(search:filter:scope:limit:offset:)`, `CoreService.memoryGraph(search:filter:scope:)`.
- Consumes: existing `MemoryStore.entries(filter:)`, `MemoryStore.edges(for:)`, `AgentMemoryItem`, `AgentMemoryFilter`.

- [ ] **Step 1: Write failing router tests**

Create `Tests/sloppyTests/MemoryAPITests.swift`:

```swift
import Foundation
import Testing
import Protocols
@testable import sloppy

@Test
func globalMemoryEndpointListsAllVisibleMemory() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)

    _ = await service.memoryStore.save(
        entry: MemoryWriteRequest(
            note: "Global durable fact",
            kind: .fact,
            memoryClass: .semantic,
            scope: .init(type: .global, id: "shared")
        )
    )
    _ = await service.memoryStore.save(
        entry: MemoryWriteRequest(
            note: "Agent durable fact",
            kind: .preference,
            memoryClass: .semantic,
            scope: .agent("agent-a")
        )
    )

    let response = await router.handle(method: "GET", path: "/v1/memories?limit=10&offset=0", body: nil)

    #expect(response.status == 200)
    let page = try JSONDecoder.sloppy.decode(MemoryListResponse.self, from: response.body)
    #expect(page.total == 2)
    #expect(page.items.map(\.note).contains("Global durable fact"))
    #expect(page.items.map(\.note).contains("Agent durable fact"))
}

@Test
func memoryEndpointFiltersByScopeTypeAndId() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)

    _ = await service.memoryStore.save(
        entry: MemoryWriteRequest(note: "Shared fact", scope: .init(type: .global, id: "shared"))
    )
    _ = await service.memoryStore.save(
        entry: MemoryWriteRequest(note: "Project fact", scope: .project("sloppy"))
    )

    let response = await router.handle(
        method: "GET",
        path: "/v1/memories?scopeType=project&scopeId=sloppy",
        body: nil
    )

    #expect(response.status == 200)
    let page = try JSONDecoder.sloppy.decode(MemoryListResponse.self, from: response.body)
    #expect(page.total == 1)
    #expect(page.items.first?.note == "Project fact")
}

@Test
func memoryGraphEndpointReturnsLinkedNodesAndEdges() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)

    let first = await service.memoryStore.save(
        entry: MemoryWriteRequest(note: "First linked fact", scope: .init(type: .global, id: "shared"))
    )
    let second = await service.memoryStore.save(
        entry: MemoryWriteRequest(note: "Second linked fact", scope: .init(type: .global, id: "shared"))
    )
    _ = await service.memoryStore.link(
        MemoryEdgeWriteRequest(
            fromMemoryId: first.id,
            toMemoryId: second.id,
            relation: .about,
            weight: 0.7,
            provenance: "test"
        )
    )

    let response = await router.handle(method: "GET", path: "/v1/memories/graph?search=linked", body: nil)

    #expect(response.status == 200)
    let graph = try JSONDecoder.sloppy.decode(MemoryGraphResponse.self, from: response.body)
    #expect(graph.nodes.count == 2)
    #expect(graph.edges.count == 1)
    #expect(graph.edges.first?.relation == .about)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter MemoryAPITests
```

Expected: compile failure because `MemoryListResponse`, `MemoryGraphResponse`, and `/v1/memories` routes do not exist.

- [ ] **Step 3: Add protocol DTOs**

In `Sources/Protocols/APIModels.swift`, near existing agent/project memory models, add:

```swift
public struct MemoryScopeQuery: Codable, Sendable, Equatable {
    public var type: MemoryScopeType?
    public var id: String?

    public init(type: MemoryScopeType? = nil, id: String? = nil) {
        self.type = type
        self.id = id
    }

    public var scope: MemoryScope? {
        guard let type, let id, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        switch type {
        case .global:
            return MemoryScope(type: .global, id: normalizedID)
        case .project:
            return .project(normalizedID)
        case .agent:
            return .agent(normalizedID)
        case .channel:
            return .channel(normalizedID)
        }
    }
}

public struct MemoryListResponse: Codable, Sendable, Equatable {
    public var scope: MemoryScope?
    public var items: [AgentMemoryItem]
    public var total: Int
    public var limit: Int
    public var offset: Int

    public init(scope: MemoryScope?, items: [AgentMemoryItem], total: Int, limit: Int, offset: Int) {
        self.scope = scope
        self.items = items
        self.total = total
        self.limit = limit
        self.offset = offset
    }
}

public struct MemoryGraphResponse: Codable, Sendable, Equatable {
    public var scope: MemoryScope?
    public var nodes: [AgentMemoryItem]
    public var edges: [AgentMemoryEdgeRecord]
    public var seedIds: [String]
    public var truncated: Bool

    public init(
        scope: MemoryScope?,
        nodes: [AgentMemoryItem],
        edges: [AgentMemoryEdgeRecord],
        seedIds: [String],
        truncated: Bool
    ) {
        self.scope = scope
        self.nodes = nodes
        self.edges = edges
        self.seedIds = seedIds
        self.truncated = truncated
    }
}
```

- [ ] **Step 4: Add CoreService general list/graph methods**

In `Sources/sloppy/CoreService+Agents.swift`, add:

```swift
    public func listMemories(
        search: String?,
        filter: AgentMemoryFilter,
        scope: MemoryScope?,
        limit: Int,
        offset: Int
    ) async throws -> MemoryListResponse {
        let boundedLimit = max(1, min(limit, 100))
        let boundedOffset = max(0, offset)
        let entries = await allMemoryEntries(scope: scope)
        let matching = filterAgentMemoryEntries(entries, search: search, filter: filter)
        let page = Array(matching.dropFirst(boundedOffset).prefix(boundedLimit))

        return MemoryListResponse(
            scope: scope,
            items: page.map { makeAgentMemoryItem(from: $0) },
            total: matching.count,
            limit: boundedLimit,
            offset: boundedOffset
        )
    }

    public func memoryGraph(
        search: String?,
        filter: AgentMemoryFilter,
        scope: MemoryScope?
    ) async throws -> MemoryGraphResponse {
        let allEntries = await allMemoryEntries(scope: scope)
        let matchingEntries = filterAgentMemoryEntries(allEntries, search: search, filter: filter)
        let seedEntries = Array(matchingEntries.prefix(Self.agentMemoryGraphSeedLimit))
        let seedIDs = seedEntries.map(\.id)
        var truncated = matchingEntries.count > Self.agentMemoryGraphSeedLimit

        guard !seedIDs.isEmpty else {
            return MemoryGraphResponse(scope: scope, nodes: [], edges: [], seedIds: [], truncated: false)
        }

        let edgeRecords = await memoryStore.edges(for: seedIDs)
        let entriesByID = Dictionary(uniqueKeysWithValues: allEntries.map { ($0.id, $0) })
        var neighborIDs: [String] = []
        var seenNeighborIDs = Set<String>()
        let seedIDSet = Set(seedIDs)

        for edge in edgeRecords {
            for candidateID in [edge.fromMemoryId, edge.toMemoryId] {
                guard !seedIDSet.contains(candidateID),
                      entriesByID[candidateID] != nil,
                      seenNeighborIDs.insert(candidateID).inserted
                else {
                    continue
                }
                neighborIDs.append(candidateID)
            }
        }

        if neighborIDs.count > Self.agentMemoryGraphNeighborLimit {
            neighborIDs = Array(neighborIDs.prefix(Self.agentMemoryGraphNeighborLimit))
            truncated = true
        }

        let includedNodeIDs = Set(seedIDs + neighborIDs)
        let includedNodes = seedEntries + neighborIDs.compactMap { entriesByID[$0] }
        let filteredEdges = edgeRecords
            .filter { includedNodeIDs.contains($0.fromMemoryId) && includedNodeIDs.contains($0.toMemoryId) }
            .map {
                AgentMemoryEdgeRecord(
                    fromMemoryId: $0.fromMemoryId,
                    toMemoryId: $0.toMemoryId,
                    relation: $0.relation,
                    weight: $0.weight,
                    provenance: $0.provenance,
                    createdAt: $0.createdAt
                )
            }

        return MemoryGraphResponse(
            scope: scope,
            nodes: includedNodes.map { makeAgentMemoryItem(from: $0) },
            edges: filteredEdges,
            seedIds: seedIDs,
            truncated: truncated
        )
    }

    func allMemoryEntries(scope: MemoryScope?) async -> [MemoryEntry] {
        let entries = await memoryStore.entries(
            filter: MemoryEntryFilter(scope: scope, includeDeleted: false, includeExpired: false)
        )
        return entries.sorted { $0.createdAt > $1.createdAt }
    }
```

- [ ] **Step 5: Register HTTP routes**

In `Sources/sloppy/Gateway/Routers/SystemAPIRouter.swift`, add route helpers near the existing system routes:

```swift
        router.get("/v1/memories", metadata: RouteMetadata(summary: "List memories", description: "Returns memory entries across scopes", tags: ["System"])) { request in
            let search = request.queryParam("search")
            let rawFilter = request.queryParam("filter")?.lowercased() ?? AgentMemoryFilter.all.rawValue
            guard let filter = AgentMemoryFilter(rawValue: rawFilter) else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            let scope = Self.memoryScopeQuery(from: request)
            let parsedLimit = Int(request.queryParam("limit") ?? "") ?? 20
            let limit = max(1, min(parsedLimit, 100))
            let offset = max(0, Int(request.queryParam("offset") ?? "") ?? 0)

            let response = try await service.listMemories(
                search: search,
                filter: filter,
                scope: scope,
                limit: limit,
                offset: offset
            )
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
        }

        router.get("/v1/memories/graph", metadata: RouteMetadata(summary: "Get memory graph", description: "Returns a graph representation of memory entries across scopes", tags: ["System"])) { request in
            let search = request.queryParam("search")
            let rawFilter = request.queryParam("filter")?.lowercased() ?? AgentMemoryFilter.all.rawValue
            guard let filter = AgentMemoryFilter(rawValue: rawFilter) else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            let response = try await service.memoryGraph(
                search: search,
                filter: filter,
                scope: Self.memoryScopeQuery(from: request)
            )
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
        }
```

Add this helper inside `SystemAPIRouter`:

```swift
    private static func memoryScopeQuery(from request: CoreHTTPRouter.Request) -> MemoryScope? {
        guard let rawType = request.queryParam("scopeType")?.lowercased(),
              let type = MemoryScopeType(rawValue: rawType),
              let rawID = request.queryParam("scopeId")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawID.isEmpty
        else {
            return nil
        }
        switch type {
        case .global:
            return MemoryScope(type: .global, id: rawID)
        case .project:
            return .project(rawID)
        case .agent:
            return .agent(rawID)
        case .channel:
            return .channel(rawID)
        }
    }
```

- [ ] **Step 6: Run tests to verify they pass**

Run:

```bash
swift test --filter MemoryAPITests
```

Expected: PASS for the three new tests.

- [ ] **Step 7: Commit**

```bash
git add Sources/Protocols/APIModels.swift Sources/sloppy/CoreService+Agents.swift Sources/sloppy/Gateway/Routers/SystemAPIRouter.swift Tests/sloppyTests/MemoryAPITests.swift
git commit -m "feat: add general memory read api"
```

---

### Task 2: Visor-Powered Text Memory Import API

**Files:**
- Modify: `Sources/Protocols/APIModels.swift`
- Modify: `Sources/sloppy/CoreService+MemoryCheckpoint.swift`
- Modify: `Sources/sloppy/Gateway/Routers/SystemAPIRouter.swift`
- Modify: `Sources/sloppy/Gateway/CoreRouter.swift`
- Test: `Tests/sloppyTests/MemoryAPITests.swift`

**Interfaces:**
- Consumes: `MemoryScope`, `MemorySaveTool`, `CoreService.invokeToolFromRuntime`, `runtime.postMessage`.
- Produces: `MemoryImportRequest`, `MemoryImportResponse`, `MemoryImportSkippedItem`, `CoreService.importMemoriesFromText(_:)`.

- [ ] **Step 1: Write failing import tests**

Append to `Tests/sloppyTests/MemoryAPITests.swift`:

```swift
@Test
func memoryImportRejectsEmptyContent() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let request = MemoryImportRequest(
        filename: "empty.txt",
        content: "   ",
        scope: MemoryScope(type: .global, id: "shared")
    )
    let body = try JSONEncoder.sloppy.encode(request)

    let response = await router.handle(method: "POST", path: "/v1/memories/import", body: body)

    #expect(response.status == 400)
}

@Test
func memoryImportRejectsUnknownProjectScope() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let request = MemoryImportRequest(
        filename: "project.txt",
        content: "The project uses Swift Testing.",
        scope: .project("missing-project")
    )
    let body = try JSONEncoder.sloppy.encode(request)

    let response = await router.handle(method: "POST", path: "/v1/memories/import", body: body)

    #expect(response.status == 404)
}

@Test
func memoryImportAcceptsGlobalScopeRequestShape() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let request = MemoryImportRequest(
        filename: "global.txt",
        content: "The user prefers compact operational dashboards.",
        scope: MemoryScope(type: .global, id: "shared")
    )
    let body = try JSONEncoder.sloppy.encode(request)

    let response = await router.handle(method: "POST", path: "/v1/memories/import", body: body)

    #expect(response.status == 200)
    let result = try JSONDecoder.sloppy.decode(MemoryImportResponse.self, from: response.body)
    #expect(result.ok)
    #expect(result.scope.type == .global)
    #expect(result.scope.id == "shared")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter MemoryAPITests
```

Expected: compile failure because import DTOs and endpoint do not exist.

- [ ] **Step 3: Add import DTOs**

In `Sources/Protocols/APIModels.swift`, near `MemoryListResponse`, add:

```swift
public struct MemoryImportRequest: Codable, Sendable, Equatable {
    public var filename: String
    public var content: String
    public var scope: MemoryScope

    public init(filename: String, content: String, scope: MemoryScope) {
        self.filename = filename
        self.content = content
        self.scope = scope
    }
}

public struct MemoryImportSkippedItem: Codable, Sendable, Equatable {
    public var reason: String
    public var summary: String

    public init(reason: String, summary: String) {
        self.reason = reason
        self.summary = summary
    }
}

public struct MemoryImportResponse: Codable, Sendable, Equatable {
    public var ok: Bool
    public var scope: MemoryScope
    public var created: [AgentMemoryItem]
    public var skipped: [MemoryImportSkippedItem]
    public var message: String

    public init(
        ok: Bool,
        scope: MemoryScope,
        created: [AgentMemoryItem],
        skipped: [MemoryImportSkippedItem],
        message: String
    ) {
        self.ok = ok
        self.scope = scope
        self.created = created
        self.skipped = skipped
        self.message = message
    }
}
```

- [ ] **Step 4: Add service validation and fallback response**

In `Sources/sloppy/CoreService+MemoryCheckpoint.swift`, add:

```swift
    static let memoryImportMaxCharacters = 120_000
    static let memoryImportMaxSaves = 12

    public enum MemoryImportError: Error, Sendable, Equatable {
        case emptyContent
        case contentTooLarge
        case invalidScope
        case projectNotFound
        case agentNotFound
    }

    public func importMemoriesFromText(_ request: MemoryImportRequest) async throws -> MemoryImportResponse {
        let filename = request.filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = request.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw MemoryImportError.emptyContent
        }
        guard content.unicodeScalars.count <= Self.memoryImportMaxCharacters else {
            throw MemoryImportError.contentTooLarge
        }
        try await validateMemoryImportScope(request.scope)

        let created = await runVisorMemoryImport(
            filename: filename.isEmpty ? "import.txt" : filename,
            content: content,
            scope: request.scope
        )
        let message = created.isEmpty
            ? "No durable memories were selected."
            : "Imported \(created.count) memories."
        return MemoryImportResponse(
            ok: true,
            scope: request.scope,
            created: created,
            skipped: created.isEmpty ? [MemoryImportSkippedItem(reason: "no_durable_memory", summary: "Visor did not select durable facts to save.")] : [],
            message: message
        )
    }

    private func validateMemoryImportScope(_ scope: MemoryScope) async throws {
        let id = scope.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            throw MemoryImportError.invalidScope
        }
        switch scope.type {
        case .global, .channel:
            return
        case .project:
            guard normalizedProjectID(id) != nil else {
                throw MemoryImportError.invalidScope
            }
            let project = try? await getProject(id: id)
            guard project != nil else {
                throw MemoryImportError.projectNotFound
            }
        case .agent:
            guard normalizedAgentID(id) != nil else {
                throw MemoryImportError.invalidScope
            }
            do {
                _ = try getAgent(id: id)
            } catch {
                throw MemoryImportError.agentNotFound
            }
        }
    }
```

- [ ] **Step 5: Add the shadow Visor import pass**

In the same file, add:

```swift
    private func runVisorMemoryImport(
        filename: String,
        content: String,
        scope: MemoryScope
    ) async -> [AgentMemoryItem] {
        let model = memoryImportModelOverride()
        let channelId = "visor:memory-import:\(UUID().uuidString.lowercased())"
        let recorder = MemoryImportActionRecorder()
        let bootstrap = Self.memoryImportBootstrap(filename: filename, content: content, scope: scope)

        await runtime.setChannelBootstrap(channelId: channelId, content: bootstrap)

        let toolInvoker: @Sendable (ToolInvocationRequest) async -> ToolInvocationResult = { request in
            guard ["visor.status", "memory.search", "memory.save"].contains(request.tool) else {
                return ToolInvocationResult(
                    tool: request.tool,
                    ok: false,
                    error: ToolErrorPayload(
                        code: "memory_import_tool_not_allowed",
                        message: "Only visor.status, memory.search, and memory.save are available during memory import.",
                        retryable: false
                    )
                )
            }
            let scopedRequest = Self.enforceMemoryImportScope(request, scope: scope)
            let result = await self.invokeToolFromRuntime(
                agentID: "visor",
                sessionID: channelId,
                request: scopedRequest,
                recordSessionEvents: false
            )
            await recorder.record(result)
            return result
        }

        _ = await runtime.postMessage(
            channelId: channelId,
            request: ChannelMessageRequest(
                userId: "memory_import",
                content: "Import the text into durable memory now. Use tools only; do not address the user.",
                model: model,
                reasoningEffort: nil
            ),
            onResponseChunk: { _ in true },
            toolInvoker: toolInvoker,
            observationHandler: nil
        )

        await runtime.discardEphemeralCheckpointChannel(channelId: channelId)
        let ids = await recorder.savedIDs()
        let entries = await memoryStore.entries(filter: MemoryEntryFilter(includeDeleted: false, includeExpired: false))
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }.map { makeAgentMemoryItem(from: $0) }
    }

    private func memoryImportModelOverride() -> String? {
        let autodream = currentConfig.visor.autodream.model?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let autodream, !autodream.isEmpty {
            return autodream
        }
        let visor = currentConfig.visor.model?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let visor, !visor.isEmpty {
            return visor
        }
        return nil
    }
```

Add recorder:

```swift
actor MemoryImportActionRecorder {
    private var ids: [String] = []

    func record(_ result: ToolInvocationResult) {
        guard result.tool == "memory.save", result.ok, let id = result.data?.asObject?["id"]?.asString else {
            return
        }
        ids.append(id)
    }

    func savedIDs() -> [String] {
        ids
    }
}
```

Add bootstrap and scope enforcement:

```swift
    static func memoryImportBootstrap(filename: String, content: String, scope: MemoryScope) -> String {
        """
        Internal Visor memory import. File: \(filename)

        Target memory scope:
        - scope_type: \(scope.type.rawValue)
        - scope_id: \(scope.id)

        Allowed tools only: `visor.status`, `memory.search`, `memory.save`.

        Before saving each memory, call `memory.search` in the target scope to avoid duplicates. Save at most \(memoryImportMaxSaves) durable, high-confidence entries.

        Use `memory.save` with:
        - `scope_type`: `\(scope.type.rawValue)`
        - `scope_id`: `\(scope.id)`
        - `source_type`: `dashboard_file_import`
        - `source_id`: `\(filename)`
        - `confidence`: 0.8 or higher only when the text clearly supports the memory
        - `metadata`: include `filename`

        Do not save secrets, credentials, tokens, private URLs, speculative guesses, transient task status, duplicate facts, or low-confidence statements.

        File content:
        \(truncatePrefix(content, maxScalars: memoryImportMaxCharacters))
        """
    }

    static func enforceMemoryImportScope(_ request: ToolInvocationRequest, scope: MemoryScope) -> ToolInvocationRequest {
        guard request.tool == "memory.save" || request.tool == "memory.search" else {
            return request
        }
        var arguments = request.arguments
        arguments["scope_type"] = .string(scope.type.rawValue)
        arguments["scope_id"] = .string(scope.id)
        arguments["scope"] = .object([
            "type": .string(scope.type.rawValue),
            "id": .string(scope.id),
            "projectId": scope.projectId.map(JSONValue.string) ?? .null,
            "agentId": scope.agentId.map(JSONValue.string) ?? .null,
            "channelId": scope.channelId.map(JSONValue.string) ?? .null,
        ])
        if request.tool == "memory.save" {
            var metadata = arguments["metadata"]?.asObject ?? [:]
            metadata["importScopeType"] = .string(scope.type.rawValue)
            metadata["importScopeId"] = .string(scope.id)
            arguments["metadata"] = .object(metadata)
        }
        return ToolInvocationRequest(tool: request.tool, arguments: arguments)
    }
```

- [ ] **Step 6: Register import route**

In `Sources/sloppy/Gateway/CoreRouter.swift`, add the import failure code near the other memory errors:

```swift
    static let memoryImportFailed = "memory_import_failed"
```

In `Sources/sloppy/Gateway/Routers/SystemAPIRouter.swift`, add:

```swift
        router.post("/v1/memories/import", metadata: RouteMetadata(summary: "Import text into memory", description: "Uses Visor to transform text into scoped memory entries", tags: ["System"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: MemoryImportRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            do {
                let response = try await service.importMemoriesFromText(payload)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch CoreService.MemoryImportError.emptyContent,
                    CoreService.MemoryImportError.contentTooLarge,
                    CoreService.MemoryImportError.invalidScope {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            } catch CoreService.MemoryImportError.projectNotFound {
                return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": ErrorCode.projectNotFound])
            } catch CoreService.MemoryImportError.agentNotFound {
                return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": ErrorCode.agentNotFound])
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.memoryImportFailed])
            }
        }
```

- [ ] **Step 7: Run tests to verify they pass**

Run:

```bash
swift test --filter MemoryAPITests
```

Expected: PASS. In the `.test` config, the import route may create zero entries if no model/tool loop runs; that is acceptable for the request-shape test.

- [ ] **Step 8: Commit**

```bash
git add Sources/Protocols/APIModels.swift Sources/sloppy/CoreService+MemoryCheckpoint.swift Sources/sloppy/Gateway/Routers/SystemAPIRouter.swift Sources/sloppy/Gateway/CoreRouter.swift Tests/sloppyTests/MemoryAPITests.swift
git commit -m "feat: import text into memory with visor"
```

---

### Task 3: Shared Dashboard Memory Browser

**Files:**
- Create: `Dashboard/src/features/memory/memoryModel.ts`
- Create: `Dashboard/src/features/memory/MemoryGraph.tsx`
- Create: `Dashboard/src/features/memory/MemoryBrowser.tsx`
- Create: `Dashboard/src/styles/memory.css`
- Modify: `Dashboard/src/styles/index.css`
- Modify: `Dashboard/src/shared/api/coreApi.ts`
- Modify: `Dashboard/src/api.ts`

**Interfaces:**
- Consumes: general and scoped memory API responses with `items`, `nodes`, `edges`, `seedIds`, `truncated`.
- Produces: `MemoryBrowser`, `MemoryScopePayload`, `fetchMemories`, `fetchMemoryGraph`.

- [ ] **Step 1: Add API client methods and run typecheck to fail**

In `Dashboard/src/shared/api/coreApi.ts`, add interface entries near existing agent/project memory methods:

```ts
  fetchMemories: (query?: AgentMemoryQuery & { scopeType?: string; scopeId?: string }) => Promise<AnyRecord | null>;
  fetchMemoryGraph: (query?: Pick<AgentMemoryQuery, "search" | "filter"> & { scopeType?: string; scopeId?: string }) => Promise<AnyRecord | null>;
```

Run:

```bash
cd Dashboard && npm run typecheck
```

Expected: FAIL because `createCoreApi` does not implement the new interface methods.

- [ ] **Step 2: Implement API client methods**

In `createCoreApi()`, add:

```ts
    fetchMemories: async (query = {}) => {
      const params = new URLSearchParams();
      if (typeof query.search === "string" && query.search.trim().length > 0) {
        params.set("search", query.search.trim());
      }
      if (typeof query.filter === "string" && query.filter.trim().length > 0) {
        params.set("filter", query.filter.trim());
      }
      if (typeof query.scopeType === "string" && query.scopeType.trim().length > 0) {
        params.set("scopeType", query.scopeType.trim());
      }
      if (typeof query.scopeId === "string" && query.scopeId.trim().length > 0) {
        params.set("scopeId", query.scopeId.trim());
      }
      if (Number.isFinite(query.limit)) {
        params.set("limit", String(query.limit));
      }
      if (Number.isFinite(query.offset)) {
        params.set("offset", String(query.offset));
      }

      const queryString = params.toString();
      const response = await requestJson<AnyRecord>({
        path: `/v1/memories${queryString ? `?${queryString}` : ""}`
      });
      if (!response.ok) {
        return null;
      }
      return response.data;
    },

    fetchMemoryGraph: async (query = {}) => {
      const params = new URLSearchParams();
      if (typeof query.search === "string" && query.search.trim().length > 0) {
        params.set("search", query.search.trim());
      }
      if (typeof query.filter === "string" && query.filter.trim().length > 0) {
        params.set("filter", query.filter.trim());
      }
      if (typeof query.scopeType === "string" && query.scopeType.trim().length > 0) {
        params.set("scopeType", query.scopeType.trim());
      }
      if (typeof query.scopeId === "string" && query.scopeId.trim().length > 0) {
        params.set("scopeId", query.scopeId.trim());
      }

      const queryString = params.toString();
      const response = await requestJson<AnyRecord>({
        path: `/v1/memories/graph${queryString ? `?${queryString}` : ""}`
      });
      if (!response.ok) {
        return null;
      }
      return response.data;
    },
```

In `Dashboard/src/api.ts`, export:

```ts
export const fetchMemories = coreApi.fetchMemories;
export const fetchMemoryGraph = coreApi.fetchMemoryGraph;
```

- [ ] **Step 3: Create shared memory model**

Create `Dashboard/src/features/memory/memoryModel.ts`:

```ts
export const PAGE_SIZE = 20;
export const GRAPH_SETTINGS_KEY = "sloppy:memory-graph-settings";

export type MemoryFilter = "all" | "persistent" | "temporary" | "todo";
export type MemoryViewMode = "list" | "graph";

export interface MemoryScopePayload {
  type: string;
  id: string;
  channelId?: string | null;
  projectId?: string | null;
  agentId?: string | null;
}

export interface MemorySourceInfo {
  type: string;
  id?: string | null;
}

export interface MemoryItem {
  id: string;
  note: string;
  summary?: string | null;
  kind: string;
  memoryClass: string;
  scope: MemoryScopePayload;
  source?: MemorySourceInfo | null;
  importance: number;
  confidence: number;
  createdAt: string;
  updatedAt: string;
  expiresAt?: string | null;
  derivedCategory: Exclude<MemoryFilter, "all">;
}

export interface MemoryEdgeRecord {
  fromMemoryId: string;
  toMemoryId: string;
  relation: string;
  weight: number;
  provenance?: string | null;
  createdAt: string;
}

export interface MemoryListResponse {
  scope?: MemoryScopePayload | null;
  items: MemoryItem[];
  total: number;
  limit: number;
  offset: number;
}

export interface MemoryGraphResponse {
  scope?: MemoryScopePayload | null;
  nodes: MemoryItem[];
  edges: MemoryEdgeRecord[];
  seedIds: string[];
  truncated: boolean;
}

export function asString(value: unknown, fallback = "") {
  const text = String(value ?? "").trim();
  return text || fallback;
}

export function asNumber(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function normalizeScope(raw: unknown): MemoryScopePayload {
  const item = raw && typeof raw === "object" ? (raw as Record<string, unknown>) : {};
  return {
    type: asString(item.type, "global"),
    id: asString(item.id, "shared"),
    channelId: asString(item.channelId ?? item.channel_id ?? "", "") || null,
    projectId: asString(item.projectId ?? item.project_id ?? "", "") || null,
    agentId: asString(item.agentId ?? item.agent_id ?? "", "") || null
  };
}

export function normalizeSource(raw: unknown): MemorySourceInfo | null {
  if (!raw || typeof raw !== "object") {
    return null;
  }
  const item = raw as Record<string, unknown>;
  const type = asString(item.type);
  if (!type) {
    return null;
  }
  return { type, id: asString(item.id, "") || null };
}

export function normalizeMemoryItem(raw: unknown, index = 0): MemoryItem | null {
  if (!raw || typeof raw !== "object") {
    return null;
  }
  const item = raw as Record<string, unknown>;
  const id = asString(item.id, `memory-${index + 1}`);
  const note = asString(item.note);
  if (!id || !note) {
    return null;
  }

  const derivedCategory = asString(item.derivedCategory ?? item.derived_category, "temporary");
  const normalizedCategory: Exclude<MemoryFilter, "all"> =
    derivedCategory === "persistent" || derivedCategory === "todo" ? derivedCategory : "temporary";

  return {
    id,
    note,
    summary: asString(item.summary, "") || null,
    kind: asString(item.kind, "fact"),
    memoryClass: asString(item.memoryClass ?? item.memory_class, "semantic"),
    scope: normalizeScope(item.scope),
    source: normalizeSource(item.source),
    importance: asNumber(item.importance, 0),
    confidence: asNumber(item.confidence, 0),
    createdAt: asString(item.createdAt ?? item.created_at, new Date(0).toISOString()),
    updatedAt: asString(item.updatedAt ?? item.updated_at, new Date(0).toISOString()),
    expiresAt: asString(item.expiresAt ?? item.expires_at, "") || null,
    derivedCategory: normalizedCategory
  };
}

export function normalizeListResponse(raw: unknown): MemoryListResponse {
  const item = raw && typeof raw === "object" ? (raw as Record<string, unknown>) : {};
  const items = Array.isArray(item.items)
    ? (item.items.map(normalizeMemoryItem).filter(Boolean) as MemoryItem[])
    : [];
  return {
    scope: item.scope ? normalizeScope(item.scope) : null,
    items,
    total: asNumber(item.total, items.length),
    limit: asNumber(item.limit, PAGE_SIZE),
    offset: asNumber(item.offset, 0)
  };
}

export function normalizeEdge(raw: unknown): MemoryEdgeRecord | null {
  if (!raw || typeof raw !== "object") {
    return null;
  }
  const item = raw as Record<string, unknown>;
  const fromMemoryId = asString(item.fromMemoryId ?? item.from_memory_id);
  const toMemoryId = asString(item.toMemoryId ?? item.to_memory_id);
  if (!fromMemoryId || !toMemoryId) {
    return null;
  }
  return {
    fromMemoryId,
    toMemoryId,
    relation: asString(item.relation, "about"),
    weight: asNumber(item.weight, 1),
    provenance: asString(item.provenance, "") || null,
    createdAt: asString(item.createdAt ?? item.created_at, new Date(0).toISOString())
  };
}

export function normalizeGraphResponse(raw: unknown): MemoryGraphResponse {
  const item = raw && typeof raw === "object" ? (raw as Record<string, unknown>) : {};
  return {
    scope: item.scope ? normalizeScope(item.scope) : null,
    nodes: Array.isArray(item.nodes)
      ? (item.nodes.map(normalizeMemoryItem).filter(Boolean) as MemoryItem[])
      : [],
    edges: Array.isArray(item.edges)
      ? (item.edges.map(normalizeEdge).filter(Boolean) as MemoryEdgeRecord[])
      : [],
    seedIds: Array.isArray(item.seedIds) ? item.seedIds.map((id) => String(id)) : [],
    truncated: Boolean(item.truncated)
  };
}

export function categoryLabel(value: MemoryFilter) {
  if (value === "persistent") return "Persistent";
  if (value === "temporary") return "Temporary";
  if (value === "todo") return "Todo";
  return "All";
}

export function formatRelativeDate(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "Unknown";
  }
  const deltaMs = Date.now() - date.getTime();
  const minutes = Math.max(0, Math.round(deltaMs / 60000));
  if (minutes < 1) return "Just now";
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.round(hours / 24);
  if (days < 30) return `${days}d ago`;
  const months = Math.round(days / 30);
  return `${months}mo ago`;
}
```

- [ ] **Step 4: Create shared graph component**

Create `Dashboard/src/features/memory/MemoryGraph.tsx` by moving the `vis-network` setup from `AgentMemoriesTab.tsx` into a component with this public API:

```tsx
import React, { useEffect, useRef } from "react";
import { Network, DataSet } from "vis-network/standalone";
import type { MemoryGraphResponse, MemoryItem } from "./memoryModel";

export interface MemoryGraphSettings {
  physics: boolean;
  nodeSize: number;
  edgeWidth: number;
  showLabels: boolean;
  showEdgeLabels: boolean;
  stabilize: boolean;
  layout: "physics" | "hierarchical";
}

export const DEFAULT_GRAPH_SETTINGS: MemoryGraphSettings = {
  physics: true,
  nodeSize: 28,
  edgeWidth: 2,
  showLabels: true,
  showEdgeLabels: true,
  stabilize: true,
  layout: "physics"
};

export function MemoryGraph({
  graphData,
  selectedMemoryId,
  settings,
  onSelectMemory
}: {
  graphData: MemoryGraphResponse;
  selectedMemoryId: string | null;
  settings: MemoryGraphSettings;
  onSelectMemory: (id: string | null) => void;
}) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const networkRef = useRef<Network | null>(null);

  useEffect(() => {
    if (!containerRef.current) {
      return;
    }

    const nodes = new DataSet(
      graphData.nodes.map((node: MemoryItem) => ({
        id: node.id,
        label: settings.showLabels ? (node.summary || node.note).slice(0, 42) : "",
        title: node.note,
        value: Math.max(1, node.importance * 10),
        color: selectedMemoryId === node.id ? "#d7fc70" : "#7aa2f7"
      }))
    );
    const edges = new DataSet(
      graphData.edges.map((edge) => ({
        from: edge.fromMemoryId,
        to: edge.toMemoryId,
        label: settings.showEdgeLabels ? edge.relation : "",
        width: Math.max(1, edge.weight * settings.edgeWidth),
        arrows: "to"
      }))
    );

    const network = new Network(
      containerRef.current,
      { nodes, edges },
      {
        physics: settings.physics,
        layout: settings.layout === "hierarchical" ? { hierarchical: { direction: "UD" } } : {},
        nodes: { shape: "dot", size: settings.nodeSize },
        edges: { color: "#444", smooth: true },
        interaction: { hover: true, navigationButtons: false }
      }
    );

    network.on("selectNode", (event) => {
      onSelectMemory(String(event.nodes[0] || "") || null);
    });
    network.on("deselectNode", () => onSelectMemory(null));
    if (settings.stabilize) {
      network.stabilize();
    }
    networkRef.current = network;

    return () => {
      network.destroy();
      networkRef.current = null;
    };
  }, [graphData, onSelectMemory, selectedMemoryId, settings]);

  return <div ref={containerRef} className="memory-graph-canvas" />;
}
```

- [ ] **Step 5: Create shared browser shell**

Create `Dashboard/src/features/memory/MemoryBrowser.tsx`:

```tsx
import React, { useCallback, useEffect, useMemo, useState } from "react";
import { LoadingSkeleton } from "../../components/LoadingSkeleton";
import {
  MemoryFilter,
  MemoryGraphResponse,
  MemoryItem,
  MemoryListResponse,
  PAGE_SIZE,
  categoryLabel,
  formatRelativeDate,
  normalizeGraphResponse,
  normalizeListResponse
} from "./memoryModel";
import { DEFAULT_GRAPH_SETTINGS, MemoryGraph, MemoryGraphSettings } from "./MemoryGraph";

const FILTERS: MemoryFilter[] = ["all", "persistent", "temporary", "todo"];

export function MemoryBrowser({
  title,
  subtitle,
  loadList,
  loadGraph,
  renderImportSlot
}: {
  title: string;
  subtitle: string;
  loadList: (query: { search: string; filter: MemoryFilter; limit: number; offset: number }) => Promise<unknown>;
  loadGraph: (query: { search: string; filter: MemoryFilter }) => Promise<unknown>;
  renderImportSlot?: (refresh: () => void) => React.ReactNode;
}) {
  const [search, setSearch] = useState("");
  const [filter, setFilter] = useState<MemoryFilter>("all");
  const [viewMode, setViewMode] = useState<"list" | "graph">("list");
  const [offset, setOffset] = useState(0);
  const [selectedMemoryId, setSelectedMemoryId] = useState<string | null>(null);
  const [listResponse, setListResponse] = useState<MemoryListResponse>({
    scope: null,
    items: [],
    total: 0,
    limit: PAGE_SIZE,
    offset: 0
  });
  const [graphResponse, setGraphResponse] = useState<MemoryGraphResponse>({
    scope: null,
    nodes: [],
    edges: [],
    seedIds: [],
    truncated: false
  });
  const [listLoading, setListLoading] = useState(false);
  const [graphLoading, setGraphLoading] = useState(false);
  const [statusText, setStatusText] = useState("Loading memories...");
  const [graphStatusText, setGraphStatusText] = useState("Loading memory graph...");
  const [graphSettings] = useState<MemoryGraphSettings>(DEFAULT_GRAPH_SETTINGS);

  const refreshList = useCallback(async () => {
    setListLoading(true);
    try {
      const raw = await loadList({ search, filter, limit: PAGE_SIZE, offset });
      const normalized = normalizeListResponse(raw);
      setListResponse(normalized);
      if (normalized.items.length === 0) {
        setStatusText(search.trim() ? "No memories match the current search." : "No memories stored.");
      } else {
        const from = normalized.offset + 1;
        const to = normalized.offset + normalized.items.length;
        setStatusText(`Showing ${from}-${to} of ${normalized.total} memories.`);
      }
    } catch {
      setListResponse({ scope: null, items: [], total: 0, limit: PAGE_SIZE, offset: 0 });
      setStatusText("Failed to load memories.");
    } finally {
      setListLoading(false);
    }
  }, [filter, loadList, offset, search]);

  const refreshGraph = useCallback(async () => {
    setGraphLoading(true);
    try {
      const raw = await loadGraph({ search, filter });
      const normalized = normalizeGraphResponse(raw);
      setGraphResponse(normalized);
      setGraphStatusText(
        normalized.nodes.length === 0
          ? "No graph nodes match the current filters."
          : `${normalized.nodes.length} nodes, ${normalized.edges.length} edges.`
      );
    } catch {
      setGraphResponse({ scope: null, nodes: [], edges: [], seedIds: [], truncated: false });
      setGraphStatusText("Failed to load memory graph.");
    } finally {
      setGraphLoading(false);
    }
  }, [filter, loadGraph, search]);

  const refresh = useCallback(() => {
    void refreshList();
    void refreshGraph();
  }, [refreshGraph, refreshList]);

  useEffect(() => {
    void refreshList();
  }, [refreshList]);

  useEffect(() => {
    if (viewMode === "graph") {
      void refreshGraph();
    }
  }, [refreshGraph, viewMode]);

  const selectedMemory = useMemo(
    () => listResponse.items.find((item) => item.id === selectedMemoryId) || graphResponse.nodes.find((item) => item.id === selectedMemoryId) || null,
    [graphResponse.nodes, listResponse.items, selectedMemoryId]
  );

  function renderCard(item: MemoryItem) {
    return (
      <button
        key={item.id}
        type="button"
        className={`agent-memory-card ${selectedMemoryId === item.id ? "selected" : ""}`}
        onClick={() => setSelectedMemoryId(item.id)}
      >
        <div className="agent-memory-card-head">
          <strong>{item.summary || item.kind}</strong>
          <span className="agent-memory-date">{formatRelativeDate(item.updatedAt || item.createdAt)}</span>
        </div>
        <p className="agent-memory-note">{item.note}</p>
        <div className="agent-memory-badges">
          <span className={`agent-memory-badge agent-memory-badge-${item.derivedCategory}`}>{categoryLabel(item.derivedCategory)}</span>
          <span className="agent-memory-badge agent-memory-badge-neutral">{item.kind}</span>
          <span className="agent-memory-badge agent-memory-badge-neutral">{item.memoryClass}</span>
          <span className="agent-memory-badge agent-memory-badge-neutral">{item.scope.type}</span>
        </div>
        <div className="agent-memory-card-foot">
          <span>Importance {item.importance.toFixed(2)}</span>
          <span>Confidence {item.confidence.toFixed(2)}</span>
        </div>
      </button>
    );
  }

  return (
    <section className="agent-memories-shell memory-browser">
      <div className="memory-browser-header">
        <div>
          <h2 className="memory-browser-title">{title}</h2>
          <p className="memory-browser-subtitle">{subtitle}</p>
        </div>
        {renderImportSlot ? renderImportSlot(refresh) : null}
      </div>

      <div className="memory-toolbar">
        <input
          className="memory-search-input"
          type="search"
          placeholder="Search memory"
          value={search}
          onChange={(event) => {
            setSearch(event.target.value);
            setOffset(0);
          }}
        />
        <div className="agent-memory-filter-row">
          {FILTERS.map((nextFilter) => (
            <button
              key={nextFilter}
              type="button"
              className={`agent-memory-segment ${filter === nextFilter ? "active" : ""}`}
              onClick={() => {
                setFilter(nextFilter);
                setOffset(0);
              }}
            >
              {categoryLabel(nextFilter)}
            </button>
          ))}
        </div>
        <div className="agent-memory-filter-row">
          <button type="button" className={`agent-memory-segment ${viewMode === "list" ? "active" : ""}`} onClick={() => setViewMode("list")}>
            List
          </button>
          <button type="button" className={`agent-memory-segment ${viewMode === "graph" ? "active" : ""}`} onClick={() => setViewMode("graph")}>
            Graph
          </button>
        </div>
      </div>

      <div className="agent-memories-body">
        <div className="agent-memories-main">
          {viewMode === "list" ? (
            <div className="agent-memory-list-shell">
              {listLoading ? <LoadingSkeleton label="Loading memory records..." variant="list" rows={5} /> : null}
              {!listLoading && listResponse.items.length === 0 ? <div className="agent-memories-empty">{statusText}</div> : null}
              {!listLoading && listResponse.items.length > 0 ? (
                <>
                  <div className="agent-memory-list">{listResponse.items.map(renderCard)}</div>
                  <div className="agent-memory-pagination">
                    <button type="button" className="secondary-button" disabled={offset <= 0} onClick={() => setOffset(Math.max(0, offset - PAGE_SIZE))}>
                      Previous
                    </button>
                    <span>{statusText}</span>
                    <button
                      type="button"
                      className="secondary-button"
                      disabled={offset + PAGE_SIZE >= listResponse.total}
                      onClick={() => setOffset(offset + PAGE_SIZE)}
                    >
                      Next
                    </button>
                  </div>
                </>
              ) : null}
            </div>
          ) : (
            <div className="agent-memory-graph-shell">
              {graphLoading ? <LoadingSkeleton label="Loading memory graph..." variant="graph" /> : null}
              {!graphLoading && graphResponse.nodes.length === 0 ? <div className="agent-memories-empty">{graphStatusText}</div> : null}
              {!graphLoading && graphResponse.nodes.length > 0 ? (
                <MemoryGraph
                  graphData={graphResponse}
                  selectedMemoryId={selectedMemoryId}
                  settings={graphSettings}
                  onSelectMemory={setSelectedMemoryId}
                />
              ) : null}
            </div>
          )}
        </div>
        <aside className="agent-memory-inspector">
          {selectedMemory ? (
            <>
              <h3>{selectedMemory.summary || selectedMemory.kind}</h3>
              <p>{selectedMemory.note}</p>
              <dl>
                <dt>Scope</dt>
                <dd>{selectedMemory.scope.type}:{selectedMemory.scope.id}</dd>
                <dt>Kind</dt>
                <dd>{selectedMemory.kind}</dd>
                <dt>Class</dt>
                <dd>{selectedMemory.memoryClass}</dd>
              </dl>
            </>
          ) : (
            <p className="placeholder-text">Select a memory to inspect it.</p>
          )}
        </aside>
      </div>
    </section>
  );
}
```

- [ ] **Step 6: Add shared styles**

Create `Dashboard/src/styles/memory.css`:

```css
.memory-page {
  min-height: 100%;
}

.memory-browser-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 16px;
}

.memory-browser-title {
  margin: 0;
  font-size: 20px;
  line-height: 1.2;
}

.memory-browser-subtitle {
  margin: 4px 0 0;
  color: var(--muted);
  font-size: 13px;
}

.memory-toolbar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 10px;
  margin-bottom: 14px;
}

.memory-search-input {
  min-width: min(100%, 280px);
  height: 36px;
}

.memory-graph-canvas {
  width: 100%;
  min-height: 520px;
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--surface);
}

.memory-import-dropzone {
  border: 1px dashed var(--border);
  border-radius: 8px;
  padding: 12px;
  color: var(--muted);
  background: color-mix(in srgb, var(--surface) 88%, transparent);
}

.memory-import-dropzone.dragging {
  border-color: var(--accent);
  color: var(--text);
}
```

In `Dashboard/src/styles/index.css`, add:

```css
@import "./memory.css";
```

- [ ] **Step 7: Run Dashboard typecheck**

Run:

```bash
cd Dashboard && npm run typecheck
```

Expected: PASS after completing the moved implementation.

- [ ] **Step 8: Commit**

```bash
git add Dashboard/src/features/memory Dashboard/src/styles/memory.css Dashboard/src/styles/index.css Dashboard/src/shared/api/coreApi.ts Dashboard/src/api.ts
git commit -m "feat: add shared dashboard memory browser"
```

---

### Task 4: Top-Level Memory Route

**Files:**
- Create: `Dashboard/src/features/memory/MemoryView.tsx`
- Modify: `Dashboard/src/app/routing/dashboardRouteAdapter.ts`
- Modify: `Dashboard/src/App.tsx`

**Interfaces:**
- Consumes: `MemoryBrowser`, `fetchMemories`, `fetchMemoryGraph`.
- Produces: `/memory` route and sidebar item.

- [ ] **Step 1: Update route parser test manually through typecheck failure**

In `Dashboard/src/app/routing/dashboardRouteAdapter.ts`, add `"memory"` to `TOP_LEVEL_SECTIONS` after `"overview"`:

```ts
export const TOP_LEVEL_SECTIONS = [
  "chats",
  "projects",
  "sessions",
  "overview",
  "memory",
  "actors",
  "agents",
  "visor",
  "usafe",
  "nodes",
  "config",
  "logs",
  "debug",
  "not_found"
] as const;
```

Run:

```bash
cd Dashboard && npm run typecheck
```

Expected: FAIL until `App.tsx` handles the new route in sidebar content.

- [ ] **Step 2: Create top-level MemoryView**

Create `Dashboard/src/features/memory/MemoryView.tsx`:

```tsx
import React from "react";
import { fetchMemories, fetchMemoryGraph } from "../../api";
import { MemoryBrowser } from "./MemoryBrowser";

export function MemoryView() {
  return (
    <main className="memory-page">
      <MemoryBrowser
        title="Memory"
        subtitle="Browse shared, project, agent, and channel memories."
        loadList={(query) => fetchMemories(query)}
        loadGraph={(query) => fetchMemoryGraph(query)}
      />
    </main>
  );
}
```

- [ ] **Step 3: Add sidebar item**

In `Dashboard/src/App.tsx`, import:

```ts
import { MemoryView } from "./features/memory/MemoryView";
```

Add the sidebar item after Overview:

```tsx
    {
      id: "memory",
      label: { icon: "psychology", title: "Memory" },
      content: <MemoryView />
    },
```

- [ ] **Step 4: Run Dashboard typecheck**

Run:

```bash
cd Dashboard && npm run typecheck
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Dashboard/src/features/memory/MemoryView.tsx Dashboard/src/app/routing/dashboardRouteAdapter.ts Dashboard/src/App.tsx
git commit -m "feat: add dashboard memory route"
```

---

### Task 5: Shared Drag And Drop Import Across Memory Tabs

**Files:**
- Modify: `Dashboard/src/shared/api/coreApi.ts`
- Modify: `Dashboard/src/api.ts`
- Create: `Dashboard/src/features/memory/MemoryImportDropzone.tsx`
- Modify: `Dashboard/src/features/memory/MemoryView.tsx`
- Modify: `Dashboard/src/features/agents/components/AgentMemoriesTab.tsx`
- Modify: `Dashboard/src/views/Projects/ProjectMemoryTab.tsx`
- Modify: `Dashboard/src/features/memory/MemoryBrowser.tsx`

**Interfaces:**
- Consumes: `POST /v1/memories/import`.
- Produces: `importMemoryFile(payload)`, `MemoryImportDropzone`, scoped imports for global/project/agent surfaces.

- [ ] **Step 1: Add API client import method and verify typecheck fails**

In `Dashboard/src/shared/api/coreApi.ts`, add interface entry:

```ts
  importMemoryFile: (payload: AnyRecord) => Promise<AnyRecord | null>;
```

Run:

```bash
cd Dashboard && npm run typecheck
```

Expected: FAIL because `createCoreApi` does not implement `importMemoryFile`.

- [ ] **Step 2: Implement API client import method**

In `createCoreApi()`, add:

```ts
    importMemoryFile: async (payload) => {
      const response = await requestJson<AnyRecord, AnyRecord>({
        path: "/v1/memories/import",
        method: "POST",
        body: payload
      });
      if (!response.ok) {
        return null;
      }
      return response.data;
    },
```

In `Dashboard/src/api.ts`, add:

```ts
export const importMemoryFile = coreApi.importMemoryFile;
```

- [ ] **Step 3: Create dropzone component**

Create `Dashboard/src/features/memory/MemoryImportDropzone.tsx`:

```tsx
import React, { useRef, useState } from "react";
import { importMemoryFile } from "../../api";
import type { MemoryScopePayload } from "./memoryModel";

const MAX_TEXT_FILE_BYTES = 512 * 1024;

function isTextFile(file: File) {
  if (file.type.startsWith("text/")) {
    return true;
  }
  return /\.(txt|md|markdown|json|csv|log)$/i.test(file.name);
}

export function MemoryImportDropzone({
  scope,
  onImported
}: {
  scope: MemoryScopePayload;
  onImported: () => void;
}) {
  const inputRef = useRef<HTMLInputElement | null>(null);
  const [dragging, setDragging] = useState(false);
  const [status, setStatus] = useState("");
  const [busy, setBusy] = useState(false);

  async function importFile(file: File) {
    if (!isTextFile(file)) {
      setStatus("Unsupported file type.");
      return;
    }
    if (file.size <= 0) {
      setStatus("File is empty.");
      return;
    }
    if (file.size > MAX_TEXT_FILE_BYTES) {
      setStatus("File is too large.");
      return;
    }

    setBusy(true);
    setStatus("Importing...");
    try {
      const content = await file.text();
      const response = await importMemoryFile({
        filename: file.name,
        content,
        scope
      });
      if (!response) {
        setStatus("Import failed.");
        return;
      }
      const created = Array.isArray(response.created) ? response.created.length : 0;
      const skipped = Array.isArray(response.skipped) ? response.skipped.length : 0;
      setStatus(`Imported ${created}; skipped ${skipped}.`);
      onImported();
    } catch {
      setStatus("Import failed.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div
      className={`memory-import-dropzone ${dragging ? "dragging" : ""}`}
      onDragEnter={(event) => {
        event.preventDefault();
        setDragging(true);
      }}
      onDragOver={(event) => event.preventDefault()}
      onDragLeave={() => setDragging(false)}
      onDrop={(event) => {
        event.preventDefault();
        setDragging(false);
        const file = event.dataTransfer.files[0];
        if (file) {
          void importFile(file);
        }
      }}
    >
      <input
        ref={inputRef}
        type="file"
        accept=".txt,.md,.markdown,.json,.csv,.log,text/*"
        style={{ display: "none" }}
        onChange={(event) => {
          const file = event.target.files?.[0];
          if (file) {
            void importFile(file);
          }
          event.target.value = "";
        }}
      />
      <button type="button" className="secondary-button" disabled={busy} onClick={() => inputRef.current?.click()}>
        <span className="material-symbols-rounded" aria-hidden="true">upload_file</span>
        Import text
      </button>
      <span>{status || "Drop a text file here."}</span>
    </div>
  );
}
```

- [ ] **Step 4: Wire import slot into top-level MemoryView**

Modify `Dashboard/src/features/memory/MemoryView.tsx`:

```tsx
import { MemoryImportDropzone } from "./MemoryImportDropzone";

const GLOBAL_MEMORY_SCOPE = { type: "global", id: "shared" };

export function MemoryView() {
  return (
    <main className="memory-page">
      <MemoryBrowser
        title="Memory"
        subtitle="Browse shared, project, agent, and channel memories."
        loadList={(query) => fetchMemories(query)}
        loadGraph={(query) => fetchMemoryGraph(query)}
        renderImportSlot={(refresh) => (
          <MemoryImportDropzone scope={GLOBAL_MEMORY_SCOPE} onImported={refresh} />
        )}
      />
    </main>
  );
}
```

- [ ] **Step 5: Refactor agent memory tab to shared browser**

Replace the body of `Dashboard/src/features/agents/components/AgentMemoriesTab.tsx` with a thin wrapper:

```tsx
import React from "react";
import { fetchAgentMemories, fetchAgentMemoryGraph } from "../../../api";
import { MemoryBrowser } from "../../memory/MemoryBrowser";
import { MemoryImportDropzone } from "../../memory/MemoryImportDropzone";

export function AgentMemoriesTab({ agentId }: { agentId: string }) {
  const scope = { type: "agent", id: agentId, agentId };
  return (
    <MemoryBrowser
      title="Agent Memories"
      subtitle="Memory entries scoped to this agent."
      loadList={(query) => fetchAgentMemories(agentId, query)}
      loadGraph={(query) => fetchAgentMemoryGraph(agentId, query)}
      renderImportSlot={(refresh) => <MemoryImportDropzone scope={scope} onImported={refresh} />}
    />
  );
}
```

- [ ] **Step 6: Refactor project memory tab to shared browser**

Replace the body of `Dashboard/src/views/Projects/ProjectMemoryTab.tsx` with a thin wrapper:

```tsx
import React from "react";
import { fetchProjectMemories, fetchProjectMemoryGraph } from "../../api";
import { MemoryBrowser } from "../../features/memory/MemoryBrowser";
import { MemoryImportDropzone } from "../../features/memory/MemoryImportDropzone";

export function ProjectMemoryTab({ projectId }: { projectId: string }) {
  const scope = { type: "project", id: projectId, projectId };
  return (
    <MemoryBrowser
      title="Project Memory"
      subtitle="Memory entries scoped to this project."
      loadList={(query) => fetchProjectMemories(projectId, query)}
      loadGraph={(query) => fetchProjectMemoryGraph(projectId, query)}
      renderImportSlot={(refresh) => <MemoryImportDropzone scope={scope} onImported={refresh} />}
    />
  );
}
```

- [ ] **Step 7: Run Dashboard verification**

Run:

```bash
cd Dashboard && npm run typecheck
cd Dashboard && npm run build
```

Expected: both commands PASS.

- [ ] **Step 8: Commit**

```bash
git add Dashboard/src/shared/api/coreApi.ts Dashboard/src/api.ts Dashboard/src/features/memory Dashboard/src/features/agents/components/AgentMemoriesTab.tsx Dashboard/src/views/Projects/ProjectMemoryTab.tsx
git commit -m "feat: add scoped memory file imports"
```

---

### Task 6: Full Verification And Polish

**Files:**
- Modify only files touched by Tasks 1-5 if verification reveals issues.

**Interfaces:**
- Consumes all previous task outputs.
- Produces a verified feature branch ready for review.

- [ ] **Step 1: Run focused Swift tests**

Run:

```bash
swift test --filter MemoryAPITests
```

Expected: PASS.

- [ ] **Step 2: Run broader memory-related Swift tests**

Run:

```bash
swift test --filter Memory
```

Expected: PASS, or existing unrelated failures documented with exact failing test names.

- [ ] **Step 3: Run Dashboard checks**

Run:

```bash
cd Dashboard && npm run typecheck
cd Dashboard && npm run build
```

Expected: PASS.

- [ ] **Step 4: Inspect final diff**

Run:

```bash
git diff --stat
git diff --check
```

Expected: diff only contains memory API/UI/import work; `git diff --check` reports no whitespace errors.

- [ ] **Step 5: Commit final fixes if any**

If Step 1-4 required changes, commit them:

```bash
git add Sources Tests Dashboard
git commit -m "fix: polish dashboard memory import"
```

When Step 1-4 leave the worktree unchanged, skip this step.
