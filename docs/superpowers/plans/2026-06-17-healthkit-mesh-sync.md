# HealthKit Mesh Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add read-only HealthKit ingestion in `Apps/Client/`, sync raw user-approved records to the Sloppy backend in foreground and background, and expose the synced data to agents through backend-controlled health query tools.

**Architecture:** The implementation is a vertical slice across client, API, persistence, and agent-access layers. `Apps/Client/Sources/SloppyClientCore` gains HealthKit authorization, record mapping, checkpointed sync, and settings persistence; the backend gains typed health API models, SQLite-backed storage, ingestion/query/purge service methods, and mesh-facing health tools that query backend-owned health records rather than the device directly.

**Tech Stack:** Swift 6.2, Swift Testing, HealthKit, BackgroundTasks, SwiftPM, XcodeGen project config in `Apps/Client/project.yml`, SQLite via existing `CSQLite3` store, Sloppy built-in `CoreTool` registry.

## Global Constraints

- `read-only` against HealthKit
- raw-ingest oriented rather than summary-only
- background-sync capable
- fully opt-in with granular controls
- mesh-accessible through a backend plugin rather than direct client RPC
- Do not write data back to HealthKit
- Do not make the agent query HealthKit directly on-device
- Maintain separation: transport -> routing -> service -> runtime -> persistence
- Use Swift Testing (`@Test`, `#expect`)
- `Apps/Client/` deployment targets remain `macOS 15.0`, `iOS 18.6`, `visionOS 2.0`
- HealthKit-specific code must compile-gate unsupported platforms instead of breaking `SloppyClient-macOS`

## File Structure

- Modify `Sources/Protocols/APIModels.swift`: backend health ingest/query/purge DTOs.
- Modify `Sources/sloppy/Stores/PersistenceStore.swift`: health record persistence protocol methods and persisted record shapes.
- Modify `Sources/sloppy/Storage/schema.sql`: health record, sync upload, and audit tables.
- Modify `Sources/sloppy/CorePersistenceFactory.swift`: in-memory store support for health records and protocol conformance.
- Modify `Sources/sloppy/SQLiteStore.swift`: SQLite implementation of health persistence.
- Create `Sources/sloppy/CoreService+HealthSync.swift`: backend health ingest, query, purge, and status methods.
- Create `Sources/sloppy/Gateway/Routers/HealthSyncAPIRouter.swift`: HTTP routes for health sync.
- Modify `Sources/sloppy/Gateway/Routers/CoreRouter+HTTPRoutes.swift`: register `HealthSyncAPIRouter`.
- Create `Sources/sloppy/Tools/AgentTools/Health/HealthRecordsQueryTool.swift`: mesh-facing raw record retrieval tool.
- Create `Sources/sloppy/Tools/AgentTools/Health/HealthRecordsSummaryTool.swift`: mesh-facing summary query tool.
- Modify `Sources/sloppy/Tools/ToolRegistry.swift`: register built-in health tools.
- Create `Tests/sloppyTests/HealthSyncPersistenceTests.swift`: persistence tests.
- Create `Tests/sloppyTests/HealthSyncAPIRouterTests.swift`: router and service tests.
- Create `Tests/sloppyTests/HealthQueryToolsTests.swift`: agent tool tests.
- Create `Apps/Client/Sources/SloppyClientCore/HealthSyncModels.swift`: client-local health settings and transport models.
- Create `Apps/Client/Sources/SloppyClientCore/HealthKitAuthorizationService.swift`: HealthKit permission helper.
- Create `Apps/Client/Sources/SloppyClientCore/HealthKitRecordMapper.swift`: `HKSample` to `HealthRecord` mapper.
- Create `Apps/Client/Sources/SloppyClientCore/HealthKitSyncService.swift`: incremental fetch + upload orchestration.
- Create `Apps/Client/Sources/SloppyClientCore/HealthSyncScheduler.swift`: app lifecycle and background task sync scheduling.
- Modify `Apps/Client/Sources/SloppyClientCore/BackendServices.swift`: add health sync API service.
- Modify `Apps/Client/Sources/SloppyClientCore/SloppyAPIClient.swift`: expose health sync client methods.
- Modify `Apps/Client/Sources/SloppyClientCore/ClientSettings.swift`: persist health sync preferences and status.
- Create `Apps/Client/Sources/SloppyFeatureSettings/sections/HealthSyncSection.swift`: Health Sync settings UI.
- Modify `Apps/Client/Sources/SloppyFeatureSettings/ServerConfigListView.swift` or `SettingsScreen.swift`: insert `HealthSyncSection`.
- Modify `Apps/Client/Package.swift`: add conditional `HealthKit` / `BackgroundTasks` imports only through source code; no package dependency needed, but update target file references if the module list changes.
- Modify `Apps/Client/project.yml`: add background task identifiers and HealthKit entitlements/usage descriptions where supported.
- Modify `Apps/Client/SupportingFiles/iOS/Info.plist`: add HealthKit usage strings and BG task registration keys if they are not fully expressed through XcodeGen properties.
- Modify `Apps/Client/SupportingFiles/iOS/SloppyClient-iOS.entitlements`: HealthKit entitlement.
- Modify `Apps/Client/SupportingFiles/iOS/SloppyClient-iPadOS.entitlements`: HealthKit entitlement.
- Modify `Apps/Client/SupportingFiles/visionOS/Info.plist` and `Apps/Client/SupportingFiles/visionOS/SloppyClient-visionOS.entitlements` only if the chosen HealthKit feature set is supported on visionOS; otherwise show the feature as unavailable there.
- Create `Apps/Client/Tests/SloppyClientCoreTests/HealthSyncModelsTests.swift`
- Create `Apps/Client/Tests/SloppyClientCoreTests/HealthKitRecordMapperTests.swift`
- Create `Apps/Client/Tests/SloppyClientCoreTests/HealthKitSyncServiceTests.swift`

---

### Task 1: Add Typed Health Sync API Models

**Files:**
- Modify: `Sources/Protocols/APIModels.swift`
- Create: `Apps/Client/Sources/SloppyClientCore/HealthSyncModels.swift`
- Test: `Tests/ProtocolsTests/HealthSyncAPIModelsTests.swift`
- Test: `Apps/Client/Tests/SloppyClientCoreTests/HealthSyncModelsTests.swift`

**Interfaces:**
- Consumes: existing `JSONValue` and protocol model style in `Sources/Protocols/APIModels.swift`
- Produces: `APIHealthRecordBatchUpsertRequest`, `APIHealthRecordBatchUpsertResponse`, `APIHealthRecordQueryRequest`, `APIHealthRecordQueryResponse`, `APIHealthRemoteDeleteRequest`, `APIHealthSyncStatusRecord`, client-local mirrors `HealthRecord`, `HealthRecordPayload`, `HealthSyncPreferences`

- [ ] **Step 1: Write the failing protocol model tests**

Create `Tests/ProtocolsTests/HealthSyncAPIModelsTests.swift` with:

```swift
import Foundation
import Testing
@testable import Protocols

@Test
func healthRecordBatchRequestRoundTrips() throws {
    let request = APIHealthRecordBatchUpsertRequest(
        ownerId: "user-1",
        deviceId: "iphone-1",
        records: [
            APIHealthRecord(
                recordId: "hk-step-1",
                sampleType: "step_count",
                sampleKind: "quantity",
                startDate: Date(timeIntervalSince1970: 10),
                endDate: Date(timeIntervalSince1970: 20),
                recordedAt: Date(timeIntervalSince1970: 20),
                unit: "count",
                valuePayload: .quantity(value: 42),
                metadata: ["sourceRevision": "1"],
                sourceBundleId: "com.apple.Health",
                sourceName: "Health",
                deviceModel: "iPhone",
                syncVersion: 1,
                isDeleted: false
            )
        ],
        uploadedAt: Date(timeIntervalSince1970: 30)
    )

    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(APIHealthRecordBatchUpsertRequest.self, from: data)

    #expect(decoded == request)
}

@Test
func healthQueryRequestRoundTrips() throws {
    let request = APIHealthRecordQueryRequest(
        ownerId: "user-1",
        deviceIds: ["iphone-1"],
        sampleTypes: ["step_count", "heart_rate"],
        startDate: Date(timeIntervalSince1970: 100),
        endDate: Date(timeIntervalSince1970: 200),
        limit: 50,
        includeDeleted: false
    )

    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(APIHealthRecordQueryRequest.self, from: data)

    #expect(decoded == request)
}
```

- [ ] **Step 2: Write the failing client model tests**

Create `Apps/Client/Tests/SloppyClientCoreTests/HealthSyncModelsTests.swift` with:

```swift
import Foundation
import Testing
@testable import SloppyClientCore

@Test
func healthSyncPreferencesDefaultToOptedOut() {
    let prefs = HealthSyncPreferences()

    #expect(prefs.isEnabled == false)
    #expect(prefs.backgroundSyncEnabled == false)
    #expect(prefs.enabledSampleTypes.isEmpty)
}

@Test
func healthRecordRoundTrips() throws {
    let record = HealthRecord(
        recordId: "hk-sleep-1",
        sampleType: "sleep_analysis",
        sampleKind: .category,
        startDate: Date(timeIntervalSince1970: 100),
        endDate: Date(timeIntervalSince1970: 200),
        recordedAt: Date(timeIntervalSince1970: 200),
        unit: nil,
        valuePayload: .category(value: "asleep_core"),
        metadata: ["hkSource": "watch"],
        sourceBundleId: "com.apple.health.123",
        sourceName: "Apple Watch",
        deviceModel: "Watch",
        syncVersion: 1,
        isDeleted: false
    )

    let data = try JSONEncoder().encode(record)
    let decoded = try JSONDecoder().decode(HealthRecord.self, from: data)

    #expect(decoded == record)
}
```

- [ ] **Step 3: Run the narrow tests and verify they fail**

Run:

```bash
swift test --filter HealthSyncAPIModelsTests
cd Apps/Client && swift test --filter HealthSyncModelsTests
```

Expected: compile failures because the health sync types do not exist yet.

- [ ] **Step 4: Add the shared backend DTOs in `Sources/Protocols/APIModels.swift`**

Add a dedicated `// MARK: - Health Sync API` section with:

```swift
public enum APIHealthRecordPayload: Codable, Sendable, Equatable {
    case quantity(value: Double)
    case category(value: String)
    case workout(activityType: String, totalEnergyBurned: Double?, totalDistance: Double?)
    case correlation(values: [String: Double])
    case raw(json: [String: JSONValue])
}

public struct APIHealthRecord: Codable, Sendable, Equatable {
    public var recordId: String
    public var sampleType: String
    public var sampleKind: String
    public var startDate: Date
    public var endDate: Date
    public var recordedAt: Date
    public var unit: String?
    public var valuePayload: APIHealthRecordPayload
    public var metadata: [String: String]
    public var sourceBundleId: String?
    public var sourceName: String?
    public var deviceModel: String?
    public var syncVersion: Int
    public var isDeleted: Bool
}

public struct APIHealthRecordBatchUpsertRequest: Codable, Sendable, Equatable {
    public var ownerId: String
    public var deviceId: String
    public var records: [APIHealthRecord]
    public var uploadedAt: Date
}

public struct APIHealthRecordBatchUpsertResponse: Codable, Sendable, Equatable {
    public var acceptedCount: Int
    public var duplicateCount: Int
    public var rejectedCount: Int
}

public struct APIHealthRecordQueryRequest: Codable, Sendable, Equatable {
    public var ownerId: String
    public var deviceIds: [String]
    public var sampleTypes: [String]
    public var startDate: Date?
    public var endDate: Date?
    public var limit: Int
    public var includeDeleted: Bool
}

public struct APIHealthRecordQueryResponse: Codable, Sendable, Equatable {
    public var records: [APIHealthRecord]
}

public struct APIHealthRemoteDeleteRequest: Codable, Sendable, Equatable {
    public var ownerId: String
    public var deviceId: String?
    public var sampleTypes: [String]
}

public struct APIHealthRemoteDeleteResponse: Codable, Sendable, Equatable {
    public var deletedCount: Int
}

public struct APIHealthSyncStatusRecord: Codable, Sendable, Equatable {
    public var ownerId: String
    public var deviceId: String
    public var lastUploadAt: Date?
    public var lastSuccessfulSyncAt: Date?
    public var enabledSampleTypes: [String]
    public var lastError: String?
}
```

- [ ] **Step 5: Add matching client-local models in `Apps/Client/Sources/SloppyClientCore/HealthSyncModels.swift`**

Create:

```swift
import Foundation

public enum HealthRecordKind: String, Codable, Sendable, Equatable {
    case quantity
    case category
    case workout
    case correlation
    case raw
}

public enum HealthRecordPayload: Codable, Sendable, Equatable {
    case quantity(value: Double)
    case category(value: String)
    case workout(activityType: String, totalEnergyBurned: Double?, totalDistance: Double?)
    case correlation(values: [String: Double])
    case raw(json: [String: String])
}

public struct HealthRecord: Codable, Sendable, Equatable {
    public var recordId: String
    public var sampleType: String
    public var sampleKind: HealthRecordKind
    public var startDate: Date
    public var endDate: Date
    public var recordedAt: Date
    public var unit: String?
    public var valuePayload: HealthRecordPayload
    public var metadata: [String: String]
    public var sourceBundleId: String?
    public var sourceName: String?
    public var deviceModel: String?
    public var syncVersion: Int
    public var isDeleted: Bool
}

public struct HealthRecordBatchUpsertRequest: Codable, Sendable, Equatable {
    public var ownerId: String
    public var deviceId: String
    public var records: [HealthRecord]
    public var uploadedAt: Date
}

public struct HealthRecordBatchUpsertResponse: Codable, Sendable, Equatable {
    public var acceptedCount: Int
    public var duplicateCount: Int
    public var rejectedCount: Int
}

public struct HealthRemoteDeleteRequest: Codable, Sendable, Equatable {
    public var ownerId: String
    public var deviceId: String?
    public var sampleTypes: [String]
}

public struct HealthRemoteDeleteResponse: Codable, Sendable, Equatable {
    public var deletedCount: Int
}

public struct HealthSyncPreferences: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var backgroundSyncEnabled: Bool
    public var enabledSampleTypes: Set<String>
    public var lastSuccessfulSyncAt: Date?
    public var lastError: String?

    public init(
        isEnabled: Bool = false,
        backgroundSyncEnabled: Bool = false,
        enabledSampleTypes: Set<String> = [],
        lastSuccessfulSyncAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.backgroundSyncEnabled = backgroundSyncEnabled
        self.enabledSampleTypes = enabledSampleTypes
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.lastError = lastError
    }
}
```

- [ ] **Step 6: Re-run the narrow tests**

Run:

```bash
swift test --filter HealthSyncAPIModelsTests
cd Apps/Client && swift test --filter HealthSyncModelsTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/Protocols/APIModels.swift Tests/ProtocolsTests/HealthSyncAPIModelsTests.swift Apps/Client/Sources/SloppyClientCore/HealthSyncModels.swift Apps/Client/Tests/SloppyClientCoreTests/HealthSyncModelsTests.swift
git commit -m "feat: add health sync api models"
```

### Task 2: Add Backend Health Persistence

**Files:**
- Modify: `Sources/sloppy/Stores/PersistenceStore.swift`
- Modify: `Sources/sloppy/Storage/schema.sql`
- Modify: `Sources/sloppy/CorePersistenceFactory.swift`
- Modify: `Sources/sloppy/SQLiteStore.swift`
- Test: `Tests/sloppyTests/HealthSyncPersistenceTests.swift`

**Interfaces:**
- Consumes: `APIHealthRecord`, `APIHealthSyncStatusRecord` from Task 1
- Produces: persistence methods `upsertHealthRecords`, `queryHealthRecords`, `purgeHealthRecords`, `saveHealthSyncStatus`, `loadHealthSyncStatus`

- [ ] **Step 1: Write the failing persistence tests**

Create `Tests/sloppyTests/HealthSyncPersistenceTests.swift` with:

```swift
import Foundation
import Testing
@testable import Protocols
@testable import sloppy

@Test
func sqliteHealthRecordUpsertAndQueryRoundTrips() async throws {
    let store = try makeSQLiteStore()
    let record = APIHealthRecord(
        recordId: "hk-step-1",
        sampleType: "step_count",
        sampleKind: "quantity",
        startDate: Date(timeIntervalSince1970: 100),
        endDate: Date(timeIntervalSince1970: 110),
        recordedAt: Date(timeIntervalSince1970: 110),
        unit: "count",
        valuePayload: .quantity(value: 100),
        metadata: [:],
        sourceBundleId: "com.apple.Health",
        sourceName: "Health",
        deviceModel: "iPhone",
        syncVersion: 1,
        isDeleted: false
    )

    await store.upsertHealthRecords(ownerId: "user-1", deviceId: "iphone-1", records: [record], uploadedAt: Date(timeIntervalSince1970: 120))
    let loaded = await store.queryHealthRecords(ownerId: "user-1", deviceIds: ["iphone-1"], sampleTypes: ["step_count"], startDate: nil, endDate: nil, limit: 10, includeDeleted: false)

    #expect(loaded == [record])
}

@Test
func sqliteHealthPurgeRemovesMatchingRecords() async throws {
    let store = try makeSQLiteStore()
    let record = APIHealthRecord(
        recordId: "hk-heart-1",
        sampleType: "heart_rate",
        sampleKind: "quantity",
        startDate: Date(timeIntervalSince1970: 200),
        endDate: Date(timeIntervalSince1970: 205),
        recordedAt: Date(timeIntervalSince1970: 205),
        unit: "count/min",
        valuePayload: .quantity(value: 75),
        metadata: [:],
        sourceBundleId: nil,
        sourceName: nil,
        deviceModel: nil,
        syncVersion: 1,
        isDeleted: false
    )

    await store.upsertHealthRecords(ownerId: "user-1", deviceId: "iphone-1", records: [record], uploadedAt: Date())
    await store.purgeHealthRecords(ownerId: "user-1", deviceId: "iphone-1", sampleTypes: ["heart_rate"])
    let loaded = await store.queryHealthRecords(ownerId: "user-1", deviceIds: ["iphone-1"], sampleTypes: ["heart_rate"], startDate: nil, endDate: nil, limit: 10, includeDeleted: true)

    #expect(loaded.isEmpty)
}

private func makeSQLiteStore() throws -> SQLiteStore {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-health-sync-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let dbPath = root.appendingPathComponent("health.sqlite").path
    let schemaURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/sloppy/Storage/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL)
    return SQLiteStore(path: dbPath, schemaSQL: schemaSQL)
}
```

- [ ] **Step 2: Run the failing persistence tests**

Run:

```bash
swift test --filter HealthSyncPersistenceTests
```

Expected: compile failures because the store methods do not exist yet.

- [ ] **Step 3: Extend `PersistenceStore` with health persistence methods**

Add:

```swift
func upsertHealthRecords(
    ownerId: String,
    deviceId: String,
    records: [APIHealthRecord],
    uploadedAt: Date
) async

func queryHealthRecords(
    ownerId: String,
    deviceIds: [String],
    sampleTypes: [String],
    startDate: Date?,
    endDate: Date?,
    limit: Int,
    includeDeleted: Bool
) async -> [APIHealthRecord]

func purgeHealthRecords(
    ownerId: String,
    deviceId: String?,
    sampleTypes: [String]
) async

func saveHealthSyncStatus(_ status: APIHealthSyncStatusRecord) async
func loadHealthSyncStatus(ownerId: String, deviceId: String) async -> APIHealthSyncStatusRecord?
```

- [ ] **Step 4: Add schema and in-memory support**

Append to `Sources/sloppy/Storage/schema.sql`:

```sql
CREATE TABLE IF NOT EXISTS health_records (
    owner_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    record_id TEXT NOT NULL PRIMARY KEY,
    sample_type TEXT NOT NULL,
    sample_kind TEXT NOT NULL,
    start_date REAL NOT NULL,
    end_date REAL NOT NULL,
    recorded_at REAL NOT NULL,
    unit TEXT,
    value_payload_json TEXT NOT NULL,
    metadata_json TEXT NOT NULL,
    source_bundle_id TEXT,
    source_name TEXT,
    device_model TEXT,
    sync_version INTEGER NOT NULL,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    uploaded_at REAL NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_health_records_owner_type_time
ON health_records(owner_id, sample_type, start_date DESC);

CREATE TABLE IF NOT EXISTS health_sync_status (
    owner_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    last_upload_at REAL,
    last_successful_sync_at REAL,
    enabled_sample_types_json TEXT NOT NULL,
    last_error TEXT,
    PRIMARY KEY (owner_id, device_id)
);
```

In `CorePersistenceFactory.swift`, add in-memory dictionaries and implementations that mirror the new protocol methods.

- [ ] **Step 5: Implement SQLite storage**

In `Sources/sloppy/SQLiteStore.swift`, add helpers shaped like:

```swift
public func upsertHealthRecords(
    ownerId: String,
    deviceId: String,
    records: [APIHealthRecord],
    uploadedAt: Date
) async {
    guard !records.isEmpty else { return }
    // Encode payload and metadata to JSON, INSERT OR REPLACE rows, keep uploaded_at for audit.
}

public func queryHealthRecords(
    ownerId: String,
    deviceIds: [String],
    sampleTypes: [String],
    startDate: Date?,
    endDate: Date?,
    limit: Int,
    includeDeleted: Bool
) async -> [APIHealthRecord] {
    // Build a bounded query filtering by owner/type/device/time and decode rows back to APIHealthRecord.
}
```

- [ ] **Step 6: Re-run the persistence tests**

Run:

```bash
swift test --filter HealthSyncPersistenceTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/sloppy/Stores/PersistenceStore.swift Sources/sloppy/Storage/schema.sql Sources/sloppy/CorePersistenceFactory.swift Sources/sloppy/SQLiteStore.swift Tests/sloppyTests/HealthSyncPersistenceTests.swift
git commit -m "feat: persist synced health records"
```

### Task 3: Add Backend Health Sync Service and HTTP Routes

**Files:**
- Create: `Sources/sloppy/CoreService+HealthSync.swift`
- Create: `Sources/sloppy/Gateway/Routers/HealthSyncAPIRouter.swift`
- Modify: `Sources/sloppy/Gateway/Routers/CoreRouter+HTTPRoutes.swift`
- Test: `Tests/sloppyTests/HealthSyncAPIRouterTests.swift`

**Interfaces:**
- Consumes: persistence methods from Task 2 and DTOs from Task 1
- Produces: `CoreService.ingestHealthRecords(_:)`, `CoreService.queryHealthRecords(_:)`, `CoreService.deleteRemoteHealthRecords(_:)`, `CoreService.getHealthSyncStatus(ownerId:deviceId:)`

- [ ] **Step 1: Write failing router tests**

Create `Tests/sloppyTests/HealthSyncAPIRouterTests.swift` with:

```swift
import Foundation
import Testing
@testable import Protocols
@testable import sloppy

@Test
func healthRecordBatchEndpointStoresRecords() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let request = APIHealthRecordBatchUpsertRequest(
        ownerId: "user-1",
        deviceId: "iphone-1",
        records: [
            APIHealthRecord(
                recordId: "hk-step-1",
                sampleType: "step_count",
                sampleKind: "quantity",
                startDate: Date(timeIntervalSince1970: 10),
                endDate: Date(timeIntervalSince1970: 20),
                recordedAt: Date(timeIntervalSince1970: 20),
                unit: "count",
                valuePayload: .quantity(value: 50),
                metadata: [:],
                sourceBundleId: nil,
                sourceName: nil,
                deviceModel: nil,
                syncVersion: 1,
                isDeleted: false
            )
        ],
        uploadedAt: Date(timeIntervalSince1970: 30)
    )

    let response = await router.handle(method: "PUT", path: "/v1/health-sync/records", body: try encoder.encode(request))
    let decoded = try decoder.decode(APIHealthRecordBatchUpsertResponse.self, from: response.body)

    #expect(decoded.acceptedCount == 1)
}

@Test
func healthPurgeEndpointDeletesRecords() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let deleteRequest = APIHealthRemoteDeleteRequest(
        ownerId: "user-1",
        deviceId: "iphone-1",
        sampleTypes: ["step_count"]
    )

    let response = await router.handle(method: "POST", path: "/v1/health-sync/purge", body: try encoder.encode(deleteRequest))

    #expect(response.status == 200)
}
```

- [ ] **Step 2: Run the router tests and verify failure**

Run:

```bash
swift test --filter HealthSyncAPIRouterTests
```

Expected: missing service methods and router registration.

- [ ] **Step 3: Implement backend health service methods**

Create `Sources/sloppy/CoreService+HealthSync.swift`:

```swift
import Foundation
import Protocols

public extension CoreService {
    func ingestHealthRecords(_ request: APIHealthRecordBatchUpsertRequest) async throws -> APIHealthRecordBatchUpsertResponse {
        await store.upsertHealthRecords(
            ownerId: request.ownerId,
            deviceId: request.deviceId,
            records: request.records,
            uploadedAt: request.uploadedAt
        )

        await store.saveHealthSyncStatus(APIHealthSyncStatusRecord(
            ownerId: request.ownerId,
            deviceId: request.deviceId,
            lastUploadAt: request.uploadedAt,
            lastSuccessfulSyncAt: request.uploadedAt,
            enabledSampleTypes: Array(Set(request.records.map(\.sampleType))).sorted(),
            lastError: nil
        ))

        return APIHealthRecordBatchUpsertResponse(
            acceptedCount: request.records.count,
            duplicateCount: 0,
            rejectedCount: 0
        )
    }

    func queryHealthRecords(_ request: APIHealthRecordQueryRequest) async throws -> APIHealthRecordQueryResponse {
        let records = await store.queryHealthRecords(
            ownerId: request.ownerId,
            deviceIds: request.deviceIds,
            sampleTypes: request.sampleTypes,
            startDate: request.startDate,
            endDate: request.endDate,
            limit: request.limit,
            includeDeleted: request.includeDeleted
        )
        return APIHealthRecordQueryResponse(records: records)
    }
}
```

- [ ] **Step 4: Add HTTP router and register it**

Create `Sources/sloppy/Gateway/Routers/HealthSyncAPIRouter.swift`:

```swift
import Foundation
import NIOHTTP1
import Protocols

struct HealthSyncAPIRouter: APIRouter {
    let service: CoreService

    func registerRoutes(on router: HTTPRouter) {
        router.put("/v1/health-sync/records", metadata: RouteMetadata(summary: "Upload a batch of health records", tags: ["Health Sync"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: APIHealthRecordBatchUpsertRequest.self) else {
                return CoreRouter.error(status: .badRequest, message: "Invalid health sync payload")
            }
            return CoreRouter.encodable(status: .ok, payload: try await service.ingestHealthRecords(payload))
        }

        router.post("/v1/health-sync/query", metadata: RouteMetadata(summary: "Query stored health records", tags: ["Health Sync"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: APIHealthRecordQueryRequest.self) else {
                return CoreRouter.error(status: .badRequest, message: "Invalid health query payload")
            }
            return CoreRouter.encodable(status: .ok, payload: try await service.queryHealthRecords(payload))
        }
    }
}
```

Then register it in `Sources/sloppy/Gateway/Routers/CoreRouter+HTTPRoutes.swift` alongside other routers.

- [ ] **Step 5: Re-run the router tests**

Run:

```bash
swift test --filter HealthSyncAPIRouterTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/sloppy/CoreService+HealthSync.swift Sources/sloppy/Gateway/Routers/HealthSyncAPIRouter.swift Sources/sloppy/Gateway/Routers/CoreRouter+HTTPRoutes.swift Tests/sloppyTests/HealthSyncAPIRouterTests.swift
git commit -m "feat: add backend health sync api"
```

### Task 4: Add Mesh-Facing Backend Health Tools

**Files:**
- Create: `Sources/sloppy/Tools/AgentTools/Health/HealthRecordsQueryTool.swift`
- Create: `Sources/sloppy/Tools/AgentTools/Health/HealthRecordsSummaryTool.swift`
- Modify: `Sources/sloppy/Tools/ToolRegistry.swift`
- Test: `Tests/sloppyTests/HealthQueryToolsTests.swift`

**Interfaces:**
- Consumes: `CoreService.queryHealthRecords(_:)` from Task 3 through `ToolContext.store`/service helpers
- Produces: tool ids `health.records.query` and `health.records.summary`

- [ ] **Step 1: Write failing tool tests**

Create `Tests/sloppyTests/HealthQueryToolsTests.swift` with:

```swift
import Foundation
import Logging
import PluginSDK
import Testing
@testable import AgentRuntime
@testable import Protocols
@testable import sloppy

@Test
func healthRecordsQueryToolReturnsMatchingRawRecords() async throws {
    let store = InMemoryPersistenceStore()
    await store.upsertHealthRecords(
        ownerId: "user-1",
        deviceId: "iphone-1",
        records: [
            APIHealthRecord(
                recordId: "hk-step-1",
                sampleType: "step_count",
                sampleKind: "quantity",
                startDate: Date(timeIntervalSince1970: 100),
                endDate: Date(timeIntervalSince1970: 110),
                recordedAt: Date(timeIntervalSince1970: 110),
                unit: "count",
                valuePayload: .quantity(value: 123),
                metadata: [:],
                sourceBundleId: nil,
                sourceName: nil,
                deviceModel: nil,
                syncVersion: 1,
                isDeleted: false
            )
        ],
        uploadedAt: Date()
    )

    let tool = HealthRecordsQueryTool()
    let context = makeToolContext(store: store)
    let output = await tool.invoke(arguments: [
        "ownerId": .string("user-1"),
        "sampleTypes": .array([.string("step_count")]),
        "limit": .number(10)
    ], context: context)

    #expect(output.ok == true)
    #expect(output.data?.description.contains("hk-step-1") == true)
}

private func makeToolContext(store: any PersistenceStore) -> ToolContext {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("health-tool-tests-\(UUID().uuidString)", isDirectory: true)
    return ToolContext(
        agentID: "agent-1",
        sessionID: "session-1",
        policy: AgentToolsPolicy(),
        workspaceRootURL: rootURL,
        memoryStore: InMemoryMemoryStore(),
        sessionStore: AgentSessionFileStore(agentsRootURL: rootURL),
        agentCatalogStore: AgentCatalogFileStore(agentsRootURL: rootURL),
        agentSkillsStore: nil,
        processRegistry: SessionProcessRegistry(),
        channelSessionStore: ChannelSessionFileStore(rootURL: rootURL),
        store: store,
        searchProviderService: SearchProviderService(config: CoreConfig.default.searchTools),
        mcpRegistry: MCPClientRegistry(),
        logger: Logger(label: "health-tool-tests"),
        projectService: nil,
        configService: nil,
        skillsService: nil,
        lspManager: nil,
        applyAgentMarkdown: nil,
        delegateSubagent: nil
    )
}
```

- [ ] **Step 2: Run the tool tests and verify failure**

Run:

```bash
swift test --filter HealthQueryToolsTests
```

Expected: compile failure because the health tools do not exist yet.

- [ ] **Step 3: Implement the raw query tool**

Create `Sources/sloppy/Tools/AgentTools/Health/HealthRecordsQueryTool.swift`:

```swift
import Foundation
import Protocols

struct HealthRecordsQueryTool: CoreTool {
    let name = "health.records.query"
    let domain = "health"
    let title = "Query synced health records"
    let description = "Returns raw synced health records for an owner filtered by sample type and time window."

    var parameters: [String: ToolParameter] {
        [
            ToolParameter.string("ownerId", description: "Owner identifier"),
            ToolParameter.array("sampleTypes", itemType: .string, description: "Health sample type filters"),
            ToolParameter.number("limit", description: "Max returned records", required: false)
        ]
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let ownerId = arguments["ownerId"]?.asString ?? ""
        let sampleTypes = arguments["sampleTypes"]?.asArray?.compactMap(\.asString) ?? []
        let limit = Int(arguments["limit"]?.asNumber ?? 25)
        let records = await context.store.queryHealthRecords(
            ownerId: ownerId,
            deviceIds: [],
            sampleTypes: sampleTypes,
            startDate: nil,
            endDate: nil,
            limit: limit,
            includeDeleted: false
        )
        let payload = try? JSONValueCoder.encode(records)
        return toolSuccess(tool: name, data: payload ?? .array([]))
    }
}
```

- [ ] **Step 4: Implement the summary tool and register both tools**

Create `HealthRecordsSummaryTool.swift`:

```swift
import Foundation
import Protocols

struct HealthRecordsSummaryTool: CoreTool {
    let name = "health.records.summary"
    let domain = "health"
    let title = "Summarize synced health records"
    let description = "Returns a compact summary grouped by sample type over a time window."

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let ownerId = arguments["ownerId"]?.asString ?? ""
        let sampleTypes = arguments["sampleTypes"]?.asArray?.compactMap(\.asString) ?? []
        let records = await context.store.queryHealthRecords(
            ownerId: ownerId,
            deviceIds: [],
            sampleTypes: sampleTypes,
            startDate: nil,
            endDate: nil,
            limit: 500,
            includeDeleted: false
        )
        let counts = Dictionary(grouping: records, by: \.sampleType).mapValues(\.count)
        return toolSuccess(tool: name, data: .object(counts.mapValues(JSONValue.number)))
    }
}
```

Register both in `Sources/sloppy/Tools/ToolRegistry.swift`.

- [ ] **Step 5: Re-run the tool tests**

Run:

```bash
swift test --filter HealthQueryToolsTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/sloppy/Tools/AgentTools/Health/HealthRecordsQueryTool.swift Sources/sloppy/Tools/AgentTools/Health/HealthRecordsSummaryTool.swift Sources/sloppy/Tools/ToolRegistry.swift Tests/sloppyTests/HealthQueryToolsTests.swift
git commit -m "feat: expose synced health records to agents"
```

### Task 5: Add Client HealthKit Authorization, Mapping, and Manual Sync

**Files:**
- Modify: `Apps/Client/Sources/SloppyClientCore/ClientSettings.swift`
- Modify: `Apps/Client/Sources/SloppyClientCore/BackendServices.swift`
- Modify: `Apps/Client/Sources/SloppyClientCore/SloppyAPIClient.swift`
- Create: `Apps/Client/Sources/SloppyClientCore/HealthKitAuthorizationService.swift`
- Create: `Apps/Client/Sources/SloppyClientCore/HealthKitRecordMapper.swift`
- Create: `Apps/Client/Sources/SloppyClientCore/HealthKitSyncService.swift`
- Test: `Apps/Client/Tests/SloppyClientCoreTests/HealthKitRecordMapperTests.swift`
- Test: `Apps/Client/Tests/SloppyClientCoreTests/HealthKitSyncServiceTests.swift`

**Interfaces:**
- Consumes: `HealthRecord` and `HealthSyncPreferences` from Task 1, backend `/v1/health-sync/*` routes from Task 3
- Produces: `HealthKitAuthorizationService.requestAuthorization(for:)`, `HealthKitRecordMapper.map(sample:)`, `HealthKitSyncService.syncNow()`

- [ ] **Step 1: Write failing mapper and sync tests**

Create `Apps/Client/Tests/SloppyClientCoreTests/HealthKitRecordMapperTests.swift`:

```swift
import Foundation
import Testing
@testable import SloppyClientCore

private struct StubHealthSample: Sendable {
    var id: String
    var sampleType: String
    var startDate: Date
    var endDate: Date
    var value: Double
    var unit: String

    static func quantity(
        id: String,
        sampleType: String,
        startDate: Date,
        endDate: Date,
        value: Double,
        unit: String
    ) -> StubHealthSample {
        StubHealthSample(
            id: id,
            sampleType: sampleType,
            startDate: startDate,
            endDate: endDate,
            value: value,
            unit: unit
        )
    }
}

@Test
func quantitySampleProducesQuantityHealthRecord() throws {
    let sample = StubHealthSample.quantity(
        id: "step-1",
        sampleType: "step_count",
        startDate: Date(timeIntervalSince1970: 10),
        endDate: Date(timeIntervalSince1970: 20),
        value: 321,
        unit: "count"
    )

    let record = try HealthKitRecordMapper().map(sample: sample)

    #expect(record.sampleType == "step_count")
    #expect(record.sampleKind == .quantity)
}
```

Create `Apps/Client/Tests/SloppyClientCoreTests/HealthKitSyncServiceTests.swift`:

```swift
import Foundation
import Testing
@testable import SloppyClientCore

private actor MockHealthSyncAPIService: HealthSyncAPIUploading {
    var uploadedRecords: [HealthRecord] = []

    func upload(ownerId: String, deviceId: String, records: [HealthRecord]) async throws {
        uploadedRecords = records
    }
}

private struct StubHealthAuthorizationService: HealthAuthorizationServicing {
    let granted: Bool

    func requestAuthorization(for sampleTypes: Set<String>) async throws -> Bool {
        granted
    }
}

private struct StubHealthQueryEngine: HealthQueryEngine {
    let records: [HealthRecord]

    func fetchIncrementalRecords(sampleTypes: Set<String>) async throws -> [HealthRecord] {
        records.filter { sampleTypes.contains($0.sampleType) }
    }
}

@Test
func syncNowUploadsMappedRecordsAndUpdatesLastSyncTime() async throws {
    let api = MockHealthSyncAPIService()
    let settings = ClientSettings()
    settings.healthSyncPreferences = HealthSyncPreferences(
        isEnabled: true,
        backgroundSyncEnabled: false,
        enabledSampleTypes: ["step_count"]
    )

    let service = HealthKitSyncService(
        authorizationService: StubHealthAuthorizationService(granted: true),
        queryEngine: StubHealthQueryEngine(records: [
            HealthRecord(
                recordId: "step-1",
                sampleType: "step_count",
                sampleKind: .quantity,
                startDate: Date(timeIntervalSince1970: 10),
                endDate: Date(timeIntervalSince1970: 20),
                recordedAt: Date(timeIntervalSince1970: 20),
                unit: "count",
                valuePayload: .quantity(value: 42),
                metadata: [:],
                sourceBundleId: nil,
                sourceName: nil,
                deviceModel: nil,
                syncVersion: 1,
                isDeleted: false
            )
        ]),
        apiService: api,
        settings: settings,
        ownerIdProvider: { "user-1" },
        deviceIdProvider: { "iphone-1" }
    )

    try await service.syncNow()

    #expect(api.uploadedRecords.count == 1)
    #expect(settings.healthSyncPreferences.lastSuccessfulSyncAt != nil)
}
```

- [ ] **Step 2: Run the failing client tests**

Run:

```bash
cd Apps/Client && swift test --filter HealthKitRecordMapperTests
cd Apps/Client && swift test --filter HealthKitSyncServiceTests
```

Expected: compile failure because the health services do not exist.

- [ ] **Step 3: Extend `ClientSettings` and API client surface**

Add to `ClientSettings.swift`:

```swift
private enum Keys {
    static let healthSyncPreferences = "client_health_sync_preferences"
}

public var healthSyncPreferences: HealthSyncPreferences {
    didSet {
        if let data = try? JSONEncoder().encode(healthSyncPreferences) {
            UserDefaults.standard.set(data, forKey: Keys.healthSyncPreferences)
        }
    }
}
```

Add to `BackendServices.swift`:

```swift
public actor HealthSyncAPIService {
    private let http: BackendHTTPClient

    public init(http: BackendHTTPClient) {
        self.http = http
    }

    public func upload(ownerId: String, deviceId: String, records: [HealthRecord]) async throws {
        let request = HealthRecordBatchUpsertRequest(ownerId: ownerId, deviceId: deviceId, records: records, uploadedAt: Date())
        _ = try await http.put("/v1/health-sync/records", body: request) as HealthRecordBatchUpsertResponse
    }

    public func purge(ownerId: String, deviceId: String?) async throws {
        let request = HealthRemoteDeleteRequest(ownerId: ownerId, deviceId: deviceId, sampleTypes: [])
        _ = try await http.post("/v1/health-sync/purge", body: request) as HealthRemoteDeleteResponse
    }
}
```

Expose it from `SloppyAPIClient`.

- [ ] **Step 4: Implement HealthKit authorization and record mapping**

Create `HealthKitAuthorizationService.swift`:

```swift
import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

public actor HealthKitAuthorizationService {
    #if canImport(HealthKit)
    private let store = HKHealthStore()
    #endif

    public func requestAuthorization(for sampleTypes: Set<String>) async throws -> Bool {
        #if canImport(HealthKit)
        let objectTypes = Set(sampleTypes.compactMap(Self.objectType(for:)))
        guard !objectTypes.isEmpty else { return false }
        try await store.requestAuthorization(toShare: [], read: objectTypes)
        return true
        #else
        return false
        #endif
    }
}
```

Create `HealthKitRecordMapper.swift` with platform-gated mapping entry points and a test-only protocol for stub samples.

- [ ] **Step 5: Implement manual sync orchestration**

Create `HealthKitSyncService.swift`:

```swift
import Foundation

public protocol HealthAuthorizationServicing: Sendable {
    func requestAuthorization(for sampleTypes: Set<String>) async throws -> Bool
}

public protocol HealthQueryEngine: Sendable {
    func fetchIncrementalRecords(sampleTypes: Set<String>) async throws -> [HealthRecord]
}

public protocol HealthSyncAPIUploading: Sendable {
    func upload(ownerId: String, deviceId: String, records: [HealthRecord]) async throws
}

public actor HealthKitSyncService {
    private let authorizationService: any HealthAuthorizationServicing
    private let queryEngine: any HealthQueryEngine
    private let apiService: any HealthSyncAPIUploading
    private let settings: ClientSettings
    private let ownerIdProvider: @Sendable () -> String
    private let deviceIdProvider: @Sendable () -> String

    public func syncNow() async throws {
        let prefs = settings.healthSyncPreferences
        guard prefs.isEnabled, !prefs.enabledSampleTypes.isEmpty else { return }
        _ = try await authorizationService.requestAuthorization(for: prefs.enabledSampleTypes)
        let records = try await queryEngine.fetchIncrementalRecords(sampleTypes: prefs.enabledSampleTypes)
        try await apiService.upload(ownerId: ownerIdProvider(), deviceId: deviceIdProvider(), records: records)
        settings.healthSyncPreferences.lastSuccessfulSyncAt = Date()
        settings.healthSyncPreferences.lastError = nil
    }
}
```

- [ ] **Step 6: Re-run the client tests**

Run:

```bash
cd Apps/Client && swift test --filter HealthKitRecordMapperTests
cd Apps/Client && swift test --filter HealthKitSyncServiceTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Apps/Client/Sources/SloppyClientCore/ClientSettings.swift Apps/Client/Sources/SloppyClientCore/BackendServices.swift Apps/Client/Sources/SloppyClientCore/SloppyAPIClient.swift Apps/Client/Sources/SloppyClientCore/HealthKitAuthorizationService.swift Apps/Client/Sources/SloppyClientCore/HealthKitRecordMapper.swift Apps/Client/Sources/SloppyClientCore/HealthKitSyncService.swift Apps/Client/Tests/SloppyClientCoreTests/HealthKitRecordMapperTests.swift Apps/Client/Tests/SloppyClientCoreTests/HealthKitSyncServiceTests.swift
git commit -m "feat: add client healthkit sync core"
```

### Task 6: Add Client Settings UI and Background Sync Wiring

**Files:**
- Create: `Apps/Client/Sources/SloppyFeatureSettings/sections/HealthSyncSection.swift`
- Modify: `Apps/Client/Sources/SloppyFeatureSettings/SettingsScreen.swift`
- Create: `Apps/Client/Sources/SloppyClientCore/HealthSyncScheduler.swift`
- Modify: `Apps/Client/project.yml`
- Modify: `Apps/Client/SupportingFiles/iOS/Info.plist`
- Modify: `Apps/Client/SupportingFiles/iOS/SloppyClient-iOS.entitlements`
- Modify: `Apps/Client/SupportingFiles/iOS/SloppyClient-iPadOS.entitlements`
- Modify: `Apps/Client/SupportingFiles/visionOS/Info.plist`
- Modify: `Apps/Client/SupportingFiles/visionOS/SloppyClient-visionOS.entitlements`
- Test: `Apps/Client/Tests/SloppyClientCoreTests/HealthSyncSchedulerTests.swift`

**Interfaces:**
- Consumes: `HealthKitSyncService.syncNow()` from Task 5 and `ClientSettings.healthSyncPreferences`
- Produces: `HealthSyncSection`, `HealthSyncScheduler.registerBackgroundTasks()`, background task identifier `team.sloppy.client.health-sync`

- [ ] **Step 1: Write failing scheduler test**

Create `Apps/Client/Tests/SloppyClientCoreTests/HealthSyncSchedulerTests.swift`:

```swift
import Foundation
import Testing
@testable import SloppyClientCore

private struct StubHealthKitSyncService: HealthSyncRunning {
    func syncNow() async throws {}
}

@Test
func schedulerSkipsBackgroundSubmissionWhenFeatureIsDisabled() async throws {
    let settings = ClientSettings()
    settings.healthSyncPreferences = HealthSyncPreferences(isEnabled: false, backgroundSyncEnabled: false, enabledSampleTypes: [])
    let scheduler = HealthSyncScheduler(settings: settings, syncService: StubHealthKitSyncService())

    let submitted = await scheduler.scheduleIfNeeded()

    #expect(submitted == false)
}
```

- [ ] **Step 2: Run the failing scheduler test**

Run:

```bash
cd Apps/Client && swift test --filter HealthSyncSchedulerTests
```

Expected: compile failure because the scheduler does not exist yet.

- [ ] **Step 3: Implement background scheduler**

Create `HealthSyncScheduler.swift`:

```swift
import Foundation
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

public protocol HealthSyncRunning: Sendable {
    func syncNow() async throws
}

public actor HealthSyncScheduler {
    public static let taskIdentifier = "team.sloppy.client.health-sync"

    private let settings: ClientSettings
    private let syncService: any HealthSyncRunning

    public init(settings: ClientSettings, syncService: any HealthSyncRunning) {
        self.settings = settings
        self.syncService = syncService
    }

    public func scheduleIfNeeded() async -> Bool {
        let prefs = settings.healthSyncPreferences
        guard prefs.isEnabled, prefs.backgroundSyncEnabled else { return false }
        #if canImport(BackgroundTasks)
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = true
        try? BGTaskScheduler.shared.submit(request)
        return true
        #else
        return false
        #endif
    }
}
```

- [ ] **Step 4: Add the Health Sync settings section**

Create `Apps/Client/Sources/SloppyFeatureSettings/sections/HealthSyncSection.swift`:

```swift
import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct HealthSyncSection: View {
    let settings: ClientSettings
    let syncNow: @Sendable () -> Void
    let deleteRemoteData: @Sendable () -> Void

    var body: some View {
        SettingsSectionCard("Health Sync") {
            VStack(alignment: .leading, spacing: 0) {
                SettingsToggleRow(
                    title: "Enable Health Sync",
                    value: Binding(
                        get: { settings.healthSyncPreferences.isEnabled },
                        set: { settings.healthSyncPreferences.isEnabled = $0 }
                    )
                )
                SettingsDivider()
                SettingsToggleRow(
                    title: "Background Sync",
                    value: Binding(
                        get: { settings.healthSyncPreferences.backgroundSyncEnabled },
                        set: { settings.healthSyncPreferences.backgroundSyncEnabled = $0 }
                    )
                )
                SettingsDivider()
                Button("SYNC NOW") { syncNow() }
                Button("DELETE REMOTE HEALTH DATA") { deleteRemoteData() }
            }
        }
    }
}
```

Wire it into `SettingsScreen.swift` below `ClientSettingsSection(settings: settings)`.

- [ ] **Step 5: Add platform configuration**

Update `Apps/Client/project.yml` iOS target properties:

```yaml
info:
  properties:
    NSHealthShareUsageDescription: Sloppy reads the health data categories you explicitly enable so your agents can answer health questions using synced context.
    BGTaskSchedulerPermittedIdentifiers:
      - team.sloppy.client.health-sync
entitlements:
  properties:
    com.apple.developer.healthkit: true
```

Keep macOS compiling by not enabling HealthKit there unless support is confirmed. If visionOS support is not available for the chosen types, leave the entitlements untouched and render the UI as unavailable on visionOS.

- [ ] **Step 6: Re-run the narrow client tests and build**

Run:

```bash
cd Apps/Client && swift test --filter HealthSyncSchedulerTests
cd Apps/Client && swift test --filter HealthKitSyncServiceTests
cd Apps/Client && swift build
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Apps/Client/Sources/SloppyFeatureSettings/sections/HealthSyncSection.swift Apps/Client/Sources/SloppyFeatureSettings/SettingsScreen.swift Apps/Client/Sources/SloppyClientCore/HealthSyncScheduler.swift Apps/Client/project.yml Apps/Client/SupportingFiles/iOS/Info.plist Apps/Client/SupportingFiles/iOS/SloppyClient-iOS.entitlements Apps/Client/SupportingFiles/iOS/SloppyClient-iPadOS.entitlements Apps/Client/SupportingFiles/visionOS/Info.plist Apps/Client/SupportingFiles/visionOS/SloppyClient-visionOS.entitlements Apps/Client/Tests/SloppyClientCoreTests/HealthSyncSchedulerTests.swift
git commit -m "feat: add health sync settings and background scheduling"
```

## Verification

Run the smallest relevant verifications after each task, then finish with:

```bash
swift test --filter HealthSyncAPIModelsTests
swift test --filter HealthSyncPersistenceTests
swift test --filter HealthSyncAPIRouterTests
swift test --filter HealthQueryToolsTests
cd Apps/Client && swift test --filter HealthSyncModelsTests
cd Apps/Client && swift test --filter HealthKitRecordMapperTests
cd Apps/Client && swift test --filter HealthKitSyncServiceTests
cd Apps/Client && swift test --filter HealthSyncSchedulerTests
cd Apps/Client && swift build
```

If the full backend slice is ready, also run:

```bash
swift test --parallel
swift build -c release --product sloppy
```

## Spec Coverage Check

- HealthKit is read-only: Tasks 5-6 only request read authorization and never define write flows.
- Raw ingest rather than summaries: Tasks 1-3 and 5 persist and upload raw `HealthRecord` rows.
- Background sync: Task 6 adds scheduler and background task registration.
- Full opt-in with granular controls: Tasks 1, 5, and 6 define preferences and UI toggles.
- Mesh/backend access instead of direct client RPC: Tasks 3-4 expose backend-owned routes and agent tools.
- Remote deletion: Tasks 2-3 define purge storage and API support; Task 6 exposes the user control.

## Notes

- Treat health owner identity as explicit app/backend state. Do not infer it from model text or channel phrasing.
- Keep HealthKit-specific code behind `#if canImport(HealthKit)` and platform availability checks.
- If `visionOS` support for the needed HealthKit types is not available, keep the module compiling and show a disabled section with a clear message instead of forcing entitlements.
