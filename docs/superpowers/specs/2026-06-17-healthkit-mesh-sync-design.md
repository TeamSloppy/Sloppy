# HealthKit Mesh Sync Design

Date: 2026-06-17
Status: Draft
Owner: Codex + user

## Goal

Add Apple HealthKit support to `Apps/Client/` so the Sloppy Apple client can read user-approved HealthKit data, sync raw records to the Sloppy backend in the background, and expose that data to agents through the existing mesh/plugin architecture.

The first version is:

- `read-only` against HealthKit
- raw-ingest oriented rather than summary-only
- background-sync capable
- fully opt-in with granular controls
- mesh-accessible through a backend plugin rather than direct client RPC

## Non-Goals

- Writing data back to HealthKit
- Making the agent query HealthKit directly on-device
- Requiring the client app to remain foregrounded for health access
- Shipping a fixed analytics/insights layer before raw ingest works

## Product Requirements

- Users can enable HealthKit integration from the Apple client.
- Users can choose which health categories or sample types are eligible for sync.
- The client requests HealthKit authorization only for enabled read scopes.
- The client syncs permitted raw data to the backend even when the app is not actively open, subject to Apple background execution limits.
- Agents access synced health data through Sloppy mesh via a backend-side plugin surface.
- Users can inspect sync status, manually trigger sync, re-authorize access, and delete previously uploaded health data.
- The system keeps auditability around upload, query, and deletion flows.

## High-Level Architecture

### Client

`Apps/Client/Sources/SloppyClientCore` gains a dedicated health subsystem:

- `HealthKitAuthorizationService`
- `HealthKitSyncService`
- `HealthSyncSettingsStore`
- `HealthRecordMapper`
- `HealthSyncScheduler`

Responsibilities:

- map app settings to requested `HKObjectType` read permissions
- read raw samples through anchored/incremental queries
- keep per-type sync checkpoints
- package records into a transport-safe payload
- submit batches to backend ingestion endpoints
- handle retries and background scheduling

The client remains the only component that talks to HealthKit APIs.

### Backend

The backend gains a dedicated health ingestion and retrieval surface:

- ingest batched raw health records
- persist normalized raw records and deletions
- maintain audit metadata per user, device, and upload
- expose retrieval/query operations through a plugin-oriented service
- support purge/delete workflows

### Mesh Integration

Agents do not talk to HealthKit and do not query the client directly.

Instead, a backend health plugin becomes the mesh-visible source of truth for agent access. That plugin exposes health retrieval in a controlled way, scoped by owner/user and governed by plugin policy and auditing.

## Data Model

The transport shape should preserve raw semantics while remaining stable across Apple platforms.

Primary transport record: `HealthRecord`

Suggested fields:

- `recordId`: stable dedupe key
- `ownerId`: Sloppy-side user or account identity
- `deviceId`: client/device identity
- `sampleType`: canonical HealthKit type identifier
- `sampleKind`: quantity, category, workout, correlation, series, clinical, or other supported kind
- `sourceBundleId`
- `sourceName`
- `startDate`
- `endDate`
- `recordedAt`
- `unit`
- `valuePayload`: typed payload for the concrete sample kind
- `metadata`
- `device`
- `syncVersion`
- `isDeleted`

For simple quantity samples, `valuePayload` may contain a scalar value plus unit metadata.

For richer sample kinds like sleep, workout, category, and correlation data, use typed payload variants rather than flattening everything into strings. This keeps downstream querying and interpretation stable.

## Sync Model

### Incremental Sync

The client uses incremental HealthKit reads with a per-type checkpoint strategy.

Each enabled type stores:

- authorization state
- last successful anchor/checkpoint
- last sync attempt time
- last successful sync time
- last error summary

This allows the client to:

- avoid full re-imports
- recover after app restarts
- retry failed uploads safely
- fetch missed samples after background gaps

### Delivery

The client uploads records in small batches with idempotent semantics.

The backend must support:

- upsert by `recordId`
- duplicate upload tolerance
- tombstone handling for deleted health records
- partial retry without corrupting state

### Background Execution

The client should attempt sync:

- on app launch
- on return to foreground
- on explicit `Sync now`
- via `BGProcessingTask` or equivalent platform background scheduling
- when HealthKit observer-style change notifications are available

This pipeline is explicitly eventually consistent. The design should not assume Apple background delivery is immediate or guaranteed.

## Client UX

Add a `Health Sync Settings` surface in the Apple client.

Expected controls:

- integration enabled toggle
- list of supported health categories/types with per-category or per-type opt-in
- authorization status display
- background sync enabled/status indicator
- last successful sync timestamp
- latest error state
- `Sync now`
- `Reauthorize`
- `Delete remote health data`

Behavior:

- enabling new categories should request additional HealthKit read scopes
- disabling categories should stop future sync for those types
- disabling integration should stop future background uploads
- deleting remote data should also clear local sync checkpoints once deletion is acknowledged or intentionally reset

## Privacy and Control Model

This feature is explicit opt-in and granular by design.

Rules:

- no health sync happens until the user enables it
- requested HealthKit scopes must be derived only from enabled categories
- agent access must be routed through backend/plugin policy, not ad hoc
- every ingest and query path should carry audit context
- the user must be able to remove previously uploaded health data

Deletion flow:

1. User triggers `Delete remote health data`.
2. Client calls backend purge endpoint scoped to the current owner/device.
3. Backend deletes or tombstones the matching remote records and logs the action.
4. Client clears local checkpoints and local health sync status.

## Backend Plugin Surface

Expose health data to agents through a dedicated backend plugin namespace.

Minimum capabilities:

- ingest batched records
- purge records by owner/device/type/range
- query raw records by type and time window
- summarize records for agent use when needed
- inspect sync status and audit trail

The default agent-facing path should be retrieval by constrained filters, not unrestricted full-dataset dumping.

Example query dimensions:

- owner
- device
- sample types
- time range
- record limit
- source filters
- deleted inclusion/exclusion

## Storage Considerations

Storage must preserve raw history while staying queryable.

Requirements:

- idempotent raw record upsert
- indexed filtering by owner, sample type, and time window
- ability to represent deletions/tombstones
- provenance retention for source and device
- compatibility with future summarization or embedding pipelines if health context later feeds memory systems

The storage format should remain backend-internal. Agents should consume the plugin interface, not direct table structure.

## Failure Handling

Client-side:

- permission denial must surface clearly in settings
- unsupported sample types should be skipped with structured logging
- transient network failures should retry with backoff
- corrupt checkpoint state should degrade safely by resetting only the affected type

Backend-side:

- malformed records should fail validation with stable errors
- batch ingestion should report item-level issues where practical
- purge operations should be auditable and idempotent

## Testing Strategy

### Client Tests

- authorization scope derivation from settings
- mapping `HKSample` variants into `HealthRecord`
- checkpoint persistence and recovery
- batch payload generation
- background scheduling wiring where unit-testable

### Backend Tests

- ingest idempotency
- tombstone handling
- purge by scope
- query filtering by type/time/owner
- plugin exposure rules and audit coverage

### Integration Tests

- end-to-end flow from client sync payload to backend retrieval
- repeated delivery of the same batch
- newly enabled sample type begins syncing incrementally
- remote deletion removes future agent visibility

## Phased Implementation

### Phase 1

- client-side HealthKit permission and settings model
- client raw sample mapping and manual sync path
- backend ingest API and persistence
- backend plugin query path

### Phase 2

- background scheduling and observer-driven sync
- deletion/purge flow
- audit/status surfaces

### Phase 3

- richer retrieval helpers and summarization
- expanded sample-type coverage
- operational tooling around sync health

## Open Implementation Decisions

These are intentionally left for the implementation plan rather than the design itself:

- exact backend table/schema layout
- exact API route names and DTO placement
- exact first-wave set of HealthKit sample types
- how settings are represented in client persistence
- whether per-type toggles are shown directly or grouped into product-friendly categories

## Recommended Path

Implement the feature as a backend-synced, plugin-exposed health pipeline:

- HealthKit read-only on device
- raw records uploaded incrementally
- background sync for eventual freshness
- backend persistence as the mesh-accessible source
- granular user controls and remote deletion from day one

This is the most reliable fit for the requirement that agents access health context through Sloppy mesh without depending on an always-running foreground client.
