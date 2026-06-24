# Widget Artifacts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Core-backed artifact browsing and bounded generated widgets that can be previewed in Dashboard and placed on the SloppySafari start page.

**Architecture:** Core becomes the source of truth for artifact metadata and widget bundle records. Dashboard and SloppySafari consume the same artifact APIs, rendering widget content only inside fixed-size sandboxed iframe surfaces. Widget generation is exposed as a Core endpoint that creates a validated artifact bundle under `.sloppy/artifacts/widgets/<artifact-id>/`.

**Tech Stack:** Swift 6.2, SwiftPM, Swift Testing, SQLite, React 19, TypeScript/JS, Vite, Safari WebExtension JavaScript.

## Global Constraints

- Widget bundle path: `.sloppy/artifacts/widgets/<artifact-id>/`.
- Widget bundle files: `manifest.json`, `index.html`, optional `assets/...`.
- Supported widget sizes: `small` 160 x 120, `medium` 320 x 180, `large` 320 x 320.
- Widgets render in sandboxed iframes; host controls size, loading, borders, and errors.
- Initial widgets are self-contained; no live data connectors, arbitrary host API access, or privileged browser actions.
- Existing `GET /v1/artifacts/:artifactId/content` remains backward-compatible.
- Preserve unrelated dirty worktree changes.

---

## File Structure

- Modify `Sources/Protocols/APIModels.swift`: public artifact metadata, widget metadata, widget generation request/response models.
- Modify `Sources/sloppy/Stores/PersistenceStore.swift`: expand `PersistedArtifactRecord` and persistence protocol signatures.
- Modify `Sources/sloppy/CorePersistenceFactory.swift`: in-memory artifact metadata behavior.
- Modify `Sources/sloppy/SQLiteStore.swift`: artifact metadata persistence and schema-compatible reads.
- Modify `Sources/sloppy/Storage/schema.sql`: artifact metadata columns.
- Create `Sources/sloppy/Artifacts/WidgetArtifactService.swift`: widget size validation, bundle path helpers, manifest writing, HTML validation.
- Modify `Sources/sloppy/CoreService+Visor.swift` or create `Sources/sloppy/CoreService+Artifacts.swift`: service methods for list/detail/content/widget/generate.
- Modify `Sources/sloppy/Gateway/Routers/ArtifactsAPIRouter.swift`: new artifact endpoints.
- Modify `Tests/sloppyTests/CoreRouterTests.swift`: Core artifact API tests.
- Modify `Dashboard/src/shared/api/coreApi.ts`: artifact API client methods.
- Modify `Dashboard/src/app/routing/dashboardRouteAdapter.ts` and `Dashboard/src/App.tsx`: `artifacts` top-level route/sidebar.
- Create `Dashboard/src/features/artifacts/ArtifactsView.tsx`: gallery/list view.
- Create `Dashboard/src/features/artifacts/artifacts.css` or extend the existing global feature stylesheet used by `App.tsx`.
- Modify `Apps/SloppySafari/Extension/Resources/panel.js`: artifact list/generate message bridge.
- Modify `Apps/SloppySafari/Extension/Resources/contentScript.js`: sidebar Artifacts item, Customize widget section, mixed start grid rendering.
- Modify `Apps/SloppySafari/Extension/Resources/panel.css`: artifact/sidebar/grid/widget styles.
- Modify `Apps/SloppySafari/Extension/Tests/contentSelection.test.mjs`, `panelPayload.test.mjs`, and `manifest.test.mjs`: extension behavior tests.

---

### Task 1: Core Artifact Metadata API

**Files:**
- Modify: `Sources/Protocols/APIModels.swift`
- Modify: `Sources/sloppy/Stores/PersistenceStore.swift`
- Modify: `Sources/sloppy/CorePersistenceFactory.swift`
- Modify: `Sources/sloppy/SQLiteStore.swift`
- Modify: `Sources/sloppy/Storage/schema.sql`
- Modify: `Sources/sloppy/CoreService+Visor.swift`
- Modify: `Sources/sloppy/Gateway/Routers/ArtifactsAPIRouter.swift`
- Test: `Tests/sloppyTests/CoreRouterTests.swift`

**Interfaces:**
- Produces: `ArtifactRecord`, `ArtifactWidgetMetadata`, `ArtifactListResponse`, `ArtifactDetailResponse`.
- Produces: `CoreService.listArtifacts() async -> ArtifactListResponse`.
- Produces: `CoreService.getArtifact(id:) async -> ArtifactDetailResponse?`.
- Produces: `PersistenceStore.persistArtifact(record: PersistedArtifactRecord) async`.
- Consumes: existing `ArtifactContentResponse` and existing artifact content lookup.

- [ ] **Step 1: Write failing model and router tests**

Add tests near `artifactContentNotFound` in `Tests/sloppyTests/CoreRouterTests.swift`:

```swift
@Test
func artifactListIncludesPersistedMetadata() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config)
    await service.store.persistArtifact(
        record: PersistedArtifactRecord(
            id: "artifact-list-test",
            title: "Clock Widget",
            kind: "widget",
            mediaType: "text/html",
            content: "<!doctype html><html><body>Clock</body></html>",
            previewText: "Clock",
            widgetSize: "small",
            widgetWidth: 160,
            widgetHeight: 120,
            widgetEntry: "index.html",
            bundlePath: ".sloppy/artifacts/widgets/artifact-list-test",
            createdAt: Date(timeIntervalSince1970: 1)
        )
    )

    let router = CoreRouter(service: service)
    let response = await router.handle(method: "GET", path: "/v1/artifacts", body: nil)
    #expect(response.status == 200)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let payload = try decoder.decode(ArtifactListResponse.self, from: response.body)
    let artifact = try #require(payload.artifacts.first(where: { $0.id == "artifact-list-test" }))
    #expect(artifact.title == "Clock Widget")
    #expect(artifact.kind == "widget")
    #expect(artifact.widget?.size == "small")
    #expect(artifact.widget?.width == 160)
    #expect(artifact.widget?.height == 120)
}

@Test
func artifactDetailReturnsPersistedMetadata() async throws {
    let service = CoreService(config: .test)
    await service.store.persistArtifact(
        record: PersistedArtifactRecord(
            id: "artifact-detail-test",
            title: "Sticky",
            kind: "widget",
            mediaType: "text/html",
            content: "<!doctype html><html><body>Sticky</body></html>",
            previewText: "Sticky",
            widgetSize: "medium",
            widgetWidth: 320,
            widgetHeight: 180,
            widgetEntry: "index.html",
            bundlePath: ".sloppy/artifacts/widgets/artifact-detail-test",
            createdAt: Date(timeIntervalSince1970: 2)
        )
    )

    let router = CoreRouter(service: service)
    let response = await router.handle(method: "GET", path: "/v1/artifacts/artifact-detail-test", body: nil)
    #expect(response.status == 200)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let payload = try decoder.decode(ArtifactDetailResponse.self, from: response.body)
    #expect(payload.artifact.id == "artifact-detail-test")
    #expect(payload.artifact.widget?.entry == "index.html")
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter artifactListIncludesPersistedMetadata
swift test --filter artifactDetailReturnsPersistedMetadata
```

Expected: compile failure for missing artifact models and new persistence initializer.

- [ ] **Step 3: Add protocol models**

In `Sources/Protocols/APIModels.swift` near `ArtifactContentResponse`, add:

```swift
public struct ArtifactWidgetMetadata: Codable, Sendable, Equatable {
    public var size: String
    public var width: Int
    public var height: Int
    public var entry: String

    public init(size: String, width: Int, height: Int, entry: String) {
        self.size = size
        self.width = width
        self.height = height
        self.entry = entry
    }
}

public struct ArtifactRecord: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var kind: String
    public var mediaType: String
    public var createdAt: Date
    public var previewText: String?
    public var widget: ArtifactWidgetMetadata?

    public init(
        id: String,
        title: String,
        kind: String,
        mediaType: String,
        createdAt: Date,
        previewText: String? = nil,
        widget: ArtifactWidgetMetadata? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.mediaType = mediaType
        self.createdAt = createdAt
        self.previewText = previewText
        self.widget = widget
    }
}

public struct ArtifactListResponse: Codable, Sendable, Equatable {
    public var artifacts: [ArtifactRecord]

    public init(artifacts: [ArtifactRecord]) {
        self.artifacts = artifacts
    }
}

public struct ArtifactDetailResponse: Codable, Sendable, Equatable {
    public var artifact: ArtifactRecord

    public init(artifact: ArtifactRecord) {
        self.artifact = artifact
    }
}
```

- [ ] **Step 4: Expand persistence record and protocol**

Replace `PersistedArtifactRecord` in `Sources/sloppy/Stores/PersistenceStore.swift` with:

```swift
public struct PersistedArtifactRecord: Sendable, Equatable {
    public var id: String
    public var title: String
    public var kind: String
    public var mediaType: String
    public var content: String
    public var previewText: String?
    public var widgetSize: String?
    public var widgetWidth: Int?
    public var widgetHeight: Int?
    public var widgetEntry: String?
    public var bundlePath: String?
    public var createdAt: Date

    public init(
        id: String,
        title: String? = nil,
        kind: String = "document",
        mediaType: String = "text/plain",
        content: String,
        previewText: String? = nil,
        widgetSize: String? = nil,
        widgetWidth: Int? = nil,
        widgetHeight: Int? = nil,
        widgetEntry: String? = nil,
        bundlePath: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.title = title ?? id
        self.kind = kind
        self.mediaType = mediaType
        self.content = content
        self.previewText = previewText
        self.widgetSize = widgetSize
        self.widgetWidth = widgetWidth
        self.widgetHeight = widgetHeight
        self.widgetEntry = widgetEntry
        self.bundlePath = bundlePath
        self.createdAt = createdAt
    }
}
```

In the protocol, add:

```swift
func persistArtifact(record: PersistedArtifactRecord) async
func persistedArtifact(id: String) async -> PersistedArtifactRecord?
```

Keep the existing `persistArtifact(id:content:)` method as a compatibility wrapper.

- [ ] **Step 5: Implement in-memory and SQLite persistence**

Update in-memory persistence so `persistArtifact(id:content:)` calls:

```swift
await persistArtifact(
    record: PersistedArtifactRecord(
        id: id,
        title: id,
        kind: "document",
        mediaType: "text/plain",
        content: content,
        previewText: String(content.prefix(160)),
        createdAt: Date()
    )
)
```

Update `schema.sql` artifact table with nullable metadata columns:

```sql
ALTER TABLE artifacts ADD COLUMN title TEXT;
ALTER TABLE artifacts ADD COLUMN kind TEXT;
ALTER TABLE artifacts ADD COLUMN media_type TEXT;
ALTER TABLE artifacts ADD COLUMN preview_text TEXT;
ALTER TABLE artifacts ADD COLUMN widget_size TEXT;
ALTER TABLE artifacts ADD COLUMN widget_width INTEGER;
ALTER TABLE artifacts ADD COLUMN widget_height INTEGER;
ALTER TABLE artifacts ADD COLUMN widget_entry TEXT;
ALTER TABLE artifacts ADD COLUMN bundle_path TEXT;
```

If the schema uses `CREATE TABLE IF NOT EXISTS artifacts`, add these columns to the create statement and add idempotent migration logic in `SQLiteStore` using the repo's existing column migration pattern.

- [ ] **Step 6: Add Core service mapping**

Add service methods:

```swift
public func listArtifacts() async -> ArtifactListResponse {
    let records = await store.listPersistedArtifacts()
    return ArtifactListResponse(artifacts: records.map(Self.artifactRecord(from:)))
}

public func getArtifact(id: String) async -> ArtifactDetailResponse? {
    guard let record = await store.persistedArtifact(id: id) else {
        return nil
    }
    return ArtifactDetailResponse(artifact: Self.artifactRecord(from: record))
}

private static func artifactRecord(from record: PersistedArtifactRecord) -> ArtifactRecord {
    let widget: ArtifactWidgetMetadata?
    if let size = record.widgetSize,
       let width = record.widgetWidth,
       let height = record.widgetHeight,
       let entry = record.widgetEntry {
        widget = ArtifactWidgetMetadata(size: size, width: width, height: height, entry: entry)
    } else {
        widget = nil
    }
    return ArtifactRecord(
        id: record.id,
        title: record.title,
        kind: record.kind,
        mediaType: record.mediaType,
        createdAt: record.createdAt,
        previewText: record.previewText,
        widget: widget
    )
}
```

- [ ] **Step 7: Add router endpoints**

In `ArtifactsAPIRouter.configure`, before the content route:

```swift
router.get("/v1/artifacts", metadata: RouteMetadata(summary: "List artifacts", description: "Returns local artifact metadata", tags: ["Artifacts"])) { _ in
    let response = await service.listArtifacts()
    return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
}

router.get("/v1/artifacts/:artifactId", metadata: RouteMetadata(summary: "Get artifact", description: "Returns metadata for a specific artifact", tags: ["Artifacts"])) { request in
    let artifactId = request.pathParam("artifactId") ?? ""
    guard let response = await service.getArtifact(id: artifactId) else {
        return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": ErrorCode.artifactNotFound])
    }
    return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
}
```

- [ ] **Step 8: Run tests and commit**

Run:

```bash
swift test --filter artifactListIncludesPersistedMetadata
swift test --filter artifactDetailReturnsPersistedMetadata
swift test --filter artifactContentNotFound
```

Expected: all pass.

Commit:

```bash
git add Sources/Protocols/APIModels.swift Sources/sloppy/Stores/PersistenceStore.swift Sources/sloppy/CorePersistenceFactory.swift Sources/sloppy/SQLiteStore.swift Sources/sloppy/Storage/schema.sql Sources/sloppy/CoreService+Visor.swift Sources/sloppy/Gateway/Routers/ArtifactsAPIRouter.swift Tests/sloppyTests/CoreRouterTests.swift
git commit -m "feat: add artifact metadata api"
```

---

### Task 2: Widget Bundle Creation And Preview API

**Files:**
- Create: `Sources/sloppy/Artifacts/WidgetArtifactService.swift`
- Modify: `Sources/Protocols/APIModels.swift`
- Modify: `Sources/sloppy/CoreService+Artifacts.swift` or `Sources/sloppy/CoreService+Visor.swift`
- Modify: `Sources/sloppy/Gateway/Routers/ArtifactsAPIRouter.swift`
- Test: `Tests/sloppyTests/CoreRouterTests.swift`

**Interfaces:**
- Consumes: Task 1 `ArtifactRecord` and persistence methods.
- Produces: `WidgetArtifactGenerateRequest`, `WidgetArtifactGenerateResponse`, `WidgetArtifactContentResponse`.
- Produces: `CoreService.generateWidgetArtifact(_:) async throws -> WidgetArtifactGenerateResponse`.
- Produces: `CoreService.getWidgetArtifact(id:) async -> WidgetArtifactContentResponse?`.

- [ ] **Step 1: Add failing tests**

Add:

```swift
@Test
func widgetGenerationRejectsInvalidSize() async throws {
    let service = CoreService(config: .test)
    let router = CoreRouter(service: service)
    let body = try JSONEncoder().encode(WidgetArtifactGenerateRequest(prompt: "Make a clock", size: "huge"))

    let response = await router.handle(method: "POST", path: "/v1/artifacts/widgets/generate", body: body)
    #expect(response.status == 400)
}

@Test
func widgetGenerationCreatesWidgetArtifactBundle() async throws {
    let service = CoreService(config: .test)
    let router = CoreRouter(service: service)
    let body = try JSONEncoder().encode(WidgetArtifactGenerateRequest(prompt: "Make a tiny clock", size: "small"))

    let response = await router.handle(method: "POST", path: "/v1/artifacts/widgets/generate", body: body)
    #expect(response.status == 201)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let payload = try decoder.decode(WidgetArtifactGenerateResponse.self, from: response.body)
    #expect(payload.artifact.kind == "widget")
    #expect(payload.artifact.widget?.size == "small")

    let widgetResponse = await router.handle(method: "GET", path: "/v1/artifacts/\(payload.artifact.id)/widget", body: nil)
    #expect(widgetResponse.status == 200)
    let widget = try decoder.decode(WidgetArtifactContentResponse.self, from: widgetResponse.body)
    #expect(widget.html.contains("<!doctype html>"))
    #expect(widget.width == 160)
    #expect(widget.height == 120)
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter widgetGenerationRejectsInvalidSize
swift test --filter widgetGenerationCreatesWidgetArtifactBundle
```

Expected: compile failure for missing request/response models.

- [ ] **Step 3: Add request/response models**

In `APIModels.swift`:

```swift
public struct WidgetArtifactGenerateRequest: Codable, Sendable, Equatable {
    public var prompt: String
    public var size: String

    public init(prompt: String, size: String) {
        self.prompt = prompt
        self.size = size
    }
}

public struct WidgetArtifactGenerateResponse: Codable, Sendable, Equatable {
    public var artifact: ArtifactRecord
    public var sessionId: String?

    public init(artifact: ArtifactRecord, sessionId: String? = nil) {
        self.artifact = artifact
        self.sessionId = sessionId
    }
}

public struct WidgetArtifactContentResponse: Codable, Sendable, Equatable {
    public var id: String
    public var html: String
    public var width: Int
    public var height: Int

    public init(id: String, html: String, width: Int, height: Int) {
        self.id = id
        self.html = html
        self.width = width
        self.height = height
    }
}
```

- [ ] **Step 4: Add widget service**

Create `Sources/sloppy/Artifacts/WidgetArtifactService.swift`:

```swift
import Foundation

struct WidgetArtifactService {
    struct Size: Sendable, Equatable {
        let name: String
        let width: Int
        let height: Int
    }

    enum WidgetError: Error, Equatable {
        case invalidSize
        case invalidPrompt
        case invalidHTML
    }

    static func size(named value: String) throws -> Size {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "small": return Size(name: "small", width: 160, height: 120)
        case "medium": return Size(name: "medium", width: 320, height: 180)
        case "large": return Size(name: "large", width: 320, height: 320)
        default: throw WidgetError.invalidSize
        }
    }

    static func fallbackHTML(prompt: String, size: Size) throws -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WidgetError.invalidPrompt }
        let escaped = trimmed
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body { width: \(size.width)px; height: \(size.height)px; margin: 0; overflow: hidden; background: #202124; color: #f5f5f5; font: 14px -apple-system, BlinkMacSystemFont, sans-serif; }
            body { display: grid; place-items: center; padding: 12px; box-sizing: border-box; }
            strong { display: block; font-size: 15px; margin-bottom: 6px; }
            p { margin: 0; color: #b7b7b7; line-height: 1.35; }
          </style>
        </head>
        <body><main><strong>Widget draft</strong><p>\(escaped)</p></main></body>
        </html>
        """
    }

    static func validate(html: String) throws {
        let lower = html.lowercased()
        guard lower.contains("<!doctype html>") || lower.contains("<html") else {
            throw WidgetError.invalidHTML
        }
    }
}
```

- [ ] **Step 5: Add service and route implementation**

Implement a synchronous MVP generation path using `fallbackHTML`. The later agent-backed implementation can replace the HTML source without changing the API.

```swift
public func generateWidgetArtifact(_ request: WidgetArtifactGenerateRequest) async throws -> WidgetArtifactGenerateResponse {
    let size = try WidgetArtifactService.size(named: request.size)
    let html = try WidgetArtifactService.fallbackHTML(prompt: request.prompt, size: size)
    try WidgetArtifactService.validate(html: html)
    let id = UUID().uuidString
    let record = PersistedArtifactRecord(
        id: id,
        title: String(request.prompt.prefix(48)),
        kind: "widget",
        mediaType: "text/html",
        content: html,
        previewText: String(request.prompt.prefix(160)),
        widgetSize: size.name,
        widgetWidth: size.width,
        widgetHeight: size.height,
        widgetEntry: "index.html",
        bundlePath: ".sloppy/artifacts/widgets/\(id)",
        createdAt: Date()
    )
    await store.persistArtifact(record: record)
    return WidgetArtifactGenerateResponse(artifact: Self.artifactRecord(from: record))
}

public func getWidgetArtifact(id: String) async -> WidgetArtifactContentResponse? {
    guard let record = await store.persistedArtifact(id: id),
          record.kind == "widget",
          let width = record.widgetWidth,
          let height = record.widgetHeight
    else {
        return nil
    }
    return WidgetArtifactContentResponse(id: id, html: record.content, width: width, height: height)
}
```

Add routes:

```swift
router.get("/v1/artifacts/:artifactId/widget", metadata: RouteMetadata(summary: "Get widget artifact", description: "Returns renderable widget HTML and fixed dimensions", tags: ["Artifacts"])) { request in
    let artifactId = request.pathParam("artifactId") ?? ""
    guard let response = await service.getWidgetArtifact(id: artifactId) else {
        return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": ErrorCode.artifactNotFound])
    }
    return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
}

router.post("/v1/artifacts/widgets/generate", metadata: RouteMetadata(summary: "Generate widget artifact", description: "Creates a bounded widget artifact from a user description", tags: ["Artifacts"])) { request in
    guard let body = request.body,
          let payload = CoreRouter.decode(body, as: WidgetArtifactGenerateRequest.self)
    else {
        return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
    }
    do {
        let response = try await service.generateWidgetArtifact(payload)
        return CoreRouter.encodable(status: HTTPStatus.created, payload: response)
    } catch WidgetArtifactService.WidgetError.invalidSize,
            WidgetArtifactService.WidgetError.invalidPrompt,
            WidgetArtifactService.WidgetError.invalidHTML {
        return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
    } catch {
        return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.artifactNotFound])
    }
}
```

- [ ] **Step 6: Run tests and commit**

Run:

```bash
swift test --filter widgetGenerationRejectsInvalidSize
swift test --filter widgetGenerationCreatesWidgetArtifactBundle
swift test --filter artifactListIncludesPersistedMetadata
```

Expected: all pass.

Commit:

```bash
git add Sources/Protocols/APIModels.swift Sources/sloppy/Artifacts/WidgetArtifactService.swift Sources/sloppy/CoreService+Artifacts.swift Sources/sloppy/CoreService+Visor.swift Sources/sloppy/Gateway/Routers/ArtifactsAPIRouter.swift Tests/sloppyTests/CoreRouterTests.swift
git commit -m "feat: add widget artifact generation"
```

---

### Task 3: Dashboard Artifacts Tab

**Files:**
- Modify: `Dashboard/src/shared/api/coreApi.ts`
- Modify: `Dashboard/src/app/routing/dashboardRouteAdapter.ts`
- Modify: `Dashboard/src/App.tsx`
- Create: `Dashboard/src/features/artifacts/ArtifactsView.tsx`
- Create: `Dashboard/src/features/artifacts/artifacts.css`

**Interfaces:**
- Consumes: `GET /v1/artifacts` and `GET /v1/artifacts/:id/widget`.
- Produces: Dashboard `/artifacts` route and sidebar item.
- Produces: `coreApi.fetchArtifacts()` and `coreApi.fetchWidgetArtifact(id)`.

- [ ] **Step 1: Add API client methods**

In `coreApi.ts` next to `fetchArtifact`, add:

```ts
    fetchArtifacts: async () => {
      const response = await requestJson<AnyRecord>({
        path: "/v1/artifacts"
      });
      if (!response.ok || !Array.isArray((response.data as AnyRecord)?.artifacts)) {
        return [];
      }
      return (response.data as AnyRecord).artifacts as AnyRecord[];
    },

    fetchWidgetArtifact: async (id) => {
      const response = await requestJson<AnyRecord>({
        path: `/v1/artifacts/${encodeURIComponent(id)}/widget`
      });
      if (!response.ok) {
        return null;
      }
      return response.data;
    },
```

- [ ] **Step 2: Add route and sidebar item**

In `dashboardRouteAdapter.ts`, add `"artifacts"` to `TOP_LEVEL_SECTIONS`.

In `App.tsx`, import:

```ts
import { ArtifactsView } from "./features/artifacts/ArtifactsView";
import "./features/artifacts/artifacts.css";
```

Add sidebar item after Projects:

```tsx
{
  id: "artifacts",
  label: { icon: "widgets", title: "Artifacts" },
  content: <ArtifactsView coreApi={dependencies.coreApi} />
},
```

- [ ] **Step 3: Create ArtifactsView**

Create `Dashboard/src/features/artifacts/ArtifactsView.tsx`:

```tsx
import { useEffect, useMemo, useState } from "react";

type AnyRecord = Record<string, any>;

interface ArtifactsViewProps {
  coreApi: {
    fetchArtifacts: () => Promise<AnyRecord[]>;
    fetchWidgetArtifact: (id: string) => Promise<AnyRecord | null>;
  };
}

export function ArtifactsView({ coreApi }: ArtifactsViewProps) {
  const [artifacts, setArtifacts] = useState<AnyRecord[]>([]);
  const [filter, setFilter] = useState("all");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError("");
    coreApi.fetchArtifacts()
      .then((items) => {
        if (!cancelled) setArtifacts(items);
      })
      .catch((err) => {
        if (!cancelled) setError(err?.message || "Artifacts are unavailable.");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [coreApi]);

  const visibleArtifacts = useMemo(() => {
    if (filter === "widgets") {
      return artifacts.filter((artifact) => artifact?.kind === "widget");
    }
    return artifacts;
  }, [artifacts, filter]);

  return (
    <section className="artifacts-view">
      <header className="artifacts-header">
        <h1>Artifacts</h1>
        <div className="artifacts-filters" role="tablist" aria-label="Artifact filters">
          <button type="button" className={filter === "all" ? "active" : ""} onClick={() => setFilter("all")}>All</button>
          <button type="button" className={filter === "widgets" ? "active" : ""} onClick={() => setFilter("widgets")}>Widgets</button>
        </div>
      </header>
      {loading ? <p className="placeholder-text">Loading artifacts...</p> : null}
      {error ? <p className="app-status-text">{error}</p> : null}
      {!loading && !error && visibleArtifacts.length === 0 ? (
        <p className="placeholder-text">No artifacts yet.</p>
      ) : null}
      <div className="artifacts-grid">
        {visibleArtifacts.map((artifact) => (
          <ArtifactCard key={artifact.id} artifact={artifact} coreApi={coreApi} />
        ))}
      </div>
    </section>
  );
}

function ArtifactCard({ artifact, coreApi }: { artifact: AnyRecord; coreApi: ArtifactsViewProps["coreApi"] }) {
  const [widget, setWidget] = useState<AnyRecord | null>(null);

  useEffect(() => {
    let cancelled = false;
    if (artifact?.kind !== "widget" || !artifact?.id) {
      setWidget(null);
      return () => {
        cancelled = true;
      };
    }
    coreApi.fetchWidgetArtifact(String(artifact.id)).then((payload) => {
      if (!cancelled) setWidget(payload);
    });
    return () => {
      cancelled = true;
    };
  }, [artifact?.id, artifact?.kind, coreApi]);

  const width = Number(widget?.width || artifact?.widget?.width || 160);
  const height = Number(widget?.height || artifact?.widget?.height || 120);

  return (
    <article className="artifact-card">
      <div className="artifact-preview" style={{ width, height }}>
        {widget?.html ? (
          <iframe title={artifact.title || artifact.id} sandbox="" srcDoc={String(widget.html)} />
        ) : (
          <span>{artifact.kind === "widget" ? "Widget" : "Artifact"}</span>
        )}
      </div>
      <strong>{artifact.title || artifact.id}</strong>
      <span>{artifact.kind || "artifact"}</span>
    </article>
  );
}
```

- [ ] **Step 4: Add CSS**

Create `Dashboard/src/features/artifacts/artifacts.css`:

```css
.artifacts-view {
  display: flex;
  flex-direction: column;
  gap: 18px;
  min-height: 100%;
  padding: 24px;
}

.artifacts-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
}

.artifacts-header h1 {
  margin: 0;
  font-size: 20px;
}

.artifacts-filters {
  display: flex;
  gap: 8px;
}

.artifacts-filters button {
  border: 1px solid rgba(255, 255, 255, 0.12);
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.05);
  color: inherit;
  padding: 7px 12px;
}

.artifacts-filters button.active {
  background: rgba(190, 255, 0, 0.16);
  border-color: rgba(190, 255, 0, 0.38);
}

.artifacts-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
  gap: 18px;
}

.artifact-card {
  display: flex;
  flex-direction: column;
  gap: 8px;
  min-width: 0;
}

.artifact-preview {
  display: grid;
  place-items: center;
  overflow: hidden;
  border: 1px solid rgba(255, 255, 255, 0.12);
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.05);
}

.artifact-preview iframe {
  width: 100%;
  height: 100%;
  border: 0;
}
```

- [ ] **Step 5: Verify and commit**

Run:

```bash
cd Dashboard && npm run typecheck
cd Dashboard && npm run build
```

Expected: both pass.

Commit:

```bash
git add Dashboard/src/shared/api/coreApi.ts Dashboard/src/app/routing/dashboardRouteAdapter.ts Dashboard/src/App.tsx Dashboard/src/features/artifacts/ArtifactsView.tsx Dashboard/src/features/artifacts/artifacts.css
git commit -m "feat: add dashboard artifacts view"
```

---

### Task 4: SloppySafari Artifact Sidebar And Widget Grid

**Files:**
- Modify: `Apps/SloppySafari/Extension/Resources/panel.js`
- Modify: `Apps/SloppySafari/Extension/Resources/contentScript.js`
- Modify: `Apps/SloppySafari/Extension/Resources/panel.css`
- Test: `Apps/SloppySafari/Extension/Tests/contentSelection.test.mjs`
- Test: `Apps/SloppySafari/Extension/Tests/panelPayload.test.mjs`

**Interfaces:**
- Consumes: Core artifact endpoints through `panel.js`.
- Produces extension messages: `sloppy.artifacts.list`, `sloppy.artifacts.widget`, `sloppy.artifacts.widget.generate`.
- Produces settings fields: `startPageItems: [{ kind: "shortcut" | "widget", ... }]`.

- [ ] **Step 1: Add failing extension tests**

Add tests in `contentSelection.test.mjs`:

```js
test("sidebar includes artifacts item and inline artifact list", async () => {
  const panel = await renderPanelForTest({ startPageEnabled: true });
  assert.match(panel.innerHTML, /data-sloppy-sidebar-artifacts/);
  assert.match(panel.innerHTML, /data-sloppy-sidebar-artifact-list/);
});

test("start page grid renders shortcuts and widget artifacts", async () => {
  const panel = await renderPanelForTest({
    startPageEnabled: true,
    startPageShortcuts: [{ title: "GitHub", url: "https://github.com/" }],
    startPageItems: [
      { kind: "shortcut", title: "GitHub", url: "https://github.com/" },
      { kind: "widget", artifactId: "widget-1", title: "Clock", size: "small", width: 160, height: 120 }
    ]
  });

  assert.match(panel.innerHTML, /data-sloppy-start-shortcut="https:\/\/github\.com\/"/);
  assert.match(panel.innerHTML, /data-sloppy-start-widget="widget-1"/);
  assert.match(panel.innerHTML, /sandbox=""/);
});

test("customize includes describe widget controls", async () => {
  const panel = await renderPanelForTest({ startPageEnabled: true });
  assert.match(panel.innerHTML, /data-sloppy-describe-widget/);
  assert.match(panel.innerHTML, /data-sloppy-widget-size/);
  assert.match(panel.innerHTML, /data-sloppy-generate-widget/);
});
```

Adapt helper names to the existing test helpers in the file if they differ.

- [ ] **Step 2: Add panel bridge**

In `panel.js`, add message cases:

```js
if (message?.type === "sloppy.artifacts.list") {
  const response = await coreFetch(settings, "/v1/artifacts");
  return response?.artifacts || [];
}

if (message?.type === "sloppy.artifacts.widget") {
  const id = String(message.artifactId || "").trim();
  if (!id) return null;
  return coreFetch(settings, `/v1/artifacts/${encodeURIComponent(id)}/widget`);
}

if (message?.type === "sloppy.artifacts.widget.generate") {
  return coreFetch(settings, "/v1/artifacts/widgets/generate", {
    method: "POST",
    body: JSON.stringify({ prompt: message.prompt || "", size: message.size || "small" })
  });
}
```

Place these in the same message dispatch area used for sessions.

- [ ] **Step 3: Add sidebar and Customize controls**

In `contentScript.js`, add sidebar markup after Sessions:

```html
<button class="sloppy-sidebar-item" type="button" data-sloppy-sidebar-artifacts>${icon("artifacts")}<span>${escapeHTML(t("artifacts"))}</span></button>
<div class="sloppy-sidebar-artifact-list" data-sloppy-sidebar-artifact-list hidden></div>
```

Add Customize controls after shortcut editor:

```html
<div class="sloppy-widget-generator">
  <label>${escapeHTML(t("describeWidget"))}<textarea data-sloppy-describe-widget rows="3"></textarea></label>
  <label>${escapeHTML(t("widgetSize"))}
    <select data-sloppy-widget-size>
      <option value="small">Small 160 x 120</option>
      <option value="medium">Medium 320 x 180</option>
      <option value="large">Large 320 x 320</option>
    </select>
  </label>
  <button class="sloppy-settings-save" type="button" data-sloppy-generate-widget>${escapeHTML(t("generateWidget"))}</button>
  <div class="sloppy-widget-picker" data-sloppy-widget-picker></div>
</div>
```

- [ ] **Step 4: Add render/load functions**

Add:

```js
async function loadArtifacts(frame) {
  const list = frame.querySelector("[data-sloppy-sidebar-artifact-list]");
  if (!list) return;
  list.hidden = false;
  list.innerHTML = `<p class="sloppy-session-empty">${escapeHTML(t("loadingArtifacts"))}</p>`;
  const artifacts = await browser.runtime.sendMessage({ type: "sloppy.artifacts.list" }).catch(() => []);
  state.artifacts = Array.isArray(artifacts) ? artifacts : [];
  renderArtifactList(frame);
}

function renderArtifactList(frame) {
  const list = frame.querySelector("[data-sloppy-sidebar-artifact-list]");
  if (!list) return;
  if (!state.artifacts?.length) {
    list.innerHTML = `<p class="sloppy-session-empty">${escapeHTML(t("noArtifacts"))}</p>`;
    return;
  }
  list.innerHTML = state.artifacts.map((artifact) => `
    <button class="sloppy-session-row" type="button" data-sloppy-select-artifact="${escapeHTML(artifact.id)}">
      <strong>${escapeHTML(artifact.title || artifact.id)}</strong>
      <span>${escapeHTML(artifact.kind || "artifact")}</span>
    </button>
  `).join("");
}

function renderStartPageItems(frame) {
  const settings = state.settings || {};
  const items = settings.startPageItems?.length
    ? settings.startPageItems
    : (settings.startPageShortcuts || []).map((shortcut) => ({ kind: "shortcut", ...shortcut }));
  renderStartPageShortcuts(frame, items);
}
```

Update `renderStartPageSurface` to call `renderStartPageItems(frame)`.

Update `renderStartPageShortcuts` to branch on `item.kind === "widget"` and render:

```js
<article class="sloppy-start-widget" data-sloppy-start-widget="${escapeHTML(item.artifactId)}" style="width:${Number(item.width || 160)}px;height:${Number(item.height || 120)}px">
  <iframe title="${escapeHTML(item.title || "Widget")}" sandbox="" srcdoc="${escapeHTML(item.html || "")}"></iframe>
</article>
```

- [ ] **Step 5: Wire events**

In `wirePanel(frame)`:

```js
frame.querySelector("[data-sloppy-sidebar-artifacts]")?.addEventListener("click", () => {
  void loadArtifacts(frame);
});

frame.querySelector("[data-sloppy-generate-widget]")?.addEventListener("click", async () => {
  const prompt = frame.querySelector("[data-sloppy-describe-widget]")?.value || "";
  const size = frame.querySelector("[data-sloppy-widget-size]")?.value || "small";
  const response = await browser.runtime.sendMessage({ type: "sloppy.artifacts.widget.generate", prompt, size }).catch((error) => ({ error: error.message }));
  if (response?.artifact) {
    state.artifacts = [response.artifact, ...(state.artifacts || [])];
    renderArtifactList(frame);
    renderWidgetPicker(frame);
  }
});
```

- [ ] **Step 6: Add CSS**

In `panel.css`:

```css
.sloppy-sidebar-artifact-list {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.sloppy-widget-generator,
.sloppy-widget-picker {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.sloppy-start-widget {
  overflow: hidden;
  border: 1px solid rgba(255, 255, 255, 0.14);
  border-radius: 8px;
  background: rgba(24, 24, 24, 0.72);
}

.sloppy-start-widget iframe {
  width: 100%;
  height: 100%;
  border: 0;
}
```

- [ ] **Step 7: Verify and commit**

Run:

```bash
cd Apps/SloppySafari/Extension && npm test
```

Expected: all extension tests pass.

Commit:

```bash
git add Apps/SloppySafari/Extension/Resources/panel.js Apps/SloppySafari/Extension/Resources/contentScript.js Apps/SloppySafari/Extension/Resources/panel.css Apps/SloppySafari/Extension/Tests/contentSelection.test.mjs Apps/SloppySafari/Extension/Tests/panelPayload.test.mjs
git commit -m "feat: add safari artifact widgets"
```

---

### Task 5: End-To-End Verification And Polish

**Files:**
- Modify only files touched by Tasks 1-4 if verification finds issues.

**Interfaces:**
- Consumes all previous task APIs and UI.
- Produces final verified feature branch/main state.

- [ ] **Step 1: Run focused Core verification**

Run:

```bash
swift test --filter Artifact
swift test --filter CoreRouterTests
```

Expected: tests pass. If `CoreRouterTests` is too broad/slow locally, capture the specific failure and run the artifact-focused filters from Tasks 1-2.

- [ ] **Step 2: Run Dashboard verification**

Run:

```bash
cd Dashboard && npm run typecheck
cd Dashboard && npm run build
```

Expected: both pass.

- [ ] **Step 3: Run SloppySafari verification**

Run:

```bash
cd Apps/SloppySafari/Extension && npm test
```

Expected: all tests pass.

- [ ] **Step 4: Inspect final diff**

Run:

```bash
git status --short
git diff --stat HEAD
```

Expected: no unstaged implementation changes except known unrelated pre-existing files: `Vendor/AdaMCP` and `docs/superpowers/plans/2026-06-24-sloppy-safari-start-page.md`.

- [ ] **Step 5: Final commit if polish changes were needed**

If Step 1-4 required fixes:

```bash
git add <only-files-changed-for-widget-artifacts>
git commit -m "fix: polish widget artifacts"
```

If no fixes were needed, do not create an empty commit.

---

## Self-Review

Spec coverage:

- Widget storage contract is covered by Task 2.
- Artifact metadata and listing endpoints are covered by Task 1.
- Widget generation endpoint is covered by Task 2.
- Dashboard Artifacts tab is covered by Task 3.
- SloppySafari sidebar Artifacts item, Customize widget controls, and start grid rendering are covered by Task 4.
- Verification commands are covered by Task 5.

Placeholder scan:

- The plan contains no placeholder markers or unnamed implementation areas.

Type consistency:

- `ArtifactRecord`, `ArtifactWidgetMetadata`, `ArtifactListResponse`, `ArtifactDetailResponse`, `WidgetArtifactGenerateRequest`, `WidgetArtifactGenerateResponse`, and `WidgetArtifactContentResponse` are introduced before use.
- Dashboard and SloppySafari consume the same `/v1/artifacts` and `/v1/artifacts/:id/widget` endpoints.
