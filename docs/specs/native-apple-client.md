# Native Apple Client Spec

## 1. Document Status
- Version: `0.1`
- Date: `2026-06-03`
- Status: `Draft for product and implementation alignment`
- Owners: `Apps/Client`, `SloppySDK`, `Dashboard`
- Primary code areas: `Apps/Client`, `Sources/SloppySDK/SloppyClient.swift`, `Sources/Protocols/*`

## 2. Product Context
The native Apple client gives operators mobile and macOS access to the same Sloppy runtime used by Dashboard and CLI. Its purpose is to keep agents reachable from a phone or native desktop environment while reusing the HTTP API and protocol models from the core service.

## 3. Goals
1. Provide a native control surface for runtime overview, projects, tasks, channels, and agent chat.
2. Reuse `SloppySDK` and shared protocol models instead of duplicating API contracts.
3. Support secure connection to a local or remote Sloppy core endpoint.
4. Make mobile interactions safe for long-running autonomous work: approve, clarify, route, and inspect before acting.
5. Preserve parity for critical operator actions even if advanced Dashboard-only analytics remain web-first.

## 4. Non-goals
1. Reimplementing the full Dashboard UI one-for-one.
2. Running the full Sloppy core service inside the mobile app.
3. Providing unrestricted local computer-control tools from iOS.
4. Supporting every plugin-specific configuration screen in the first native iteration.

## 5. Core Concepts
| Concept | Description |
| --- | --- |
| Core connection | Base URL and auth/session settings for a Sloppy runtime. |
| SDK client | Swift API wrapper that calls core HTTP endpoints and decodes shared models. |
| Native session | Local UI state around a remote Sloppy agent/channel session. |
| Operator action | Mobile-safe mutation such as send message, approve tool/task, answer clarification, or change task status. |
| Offline state | Cached read-only snapshots shown when the core is unreachable. |

## 6. Functional Requirements

### FR-1: Connection setup
- User can configure the Sloppy core base URL.
- Client validates connectivity with a health/config request.
- Connection errors distinguish unreachable host, incompatible version, and authentication failure where applicable.

### FR-2: Runtime overview
- Client can show core status, bulletins, channels/sessions, and recent activity at a glance.
- Runtime status should be refreshable manually and eventually by background refresh where platform allows.

### FR-3: Project and task access
- Client can list projects, inspect project detail, view task board/list, and open task detail.
- Mobile-safe task actions include status update, approval/rejection, clarification answer, and comment where supported.

### FR-4: Chat and channels
- Client can open an agent or channel session, send a message, and display assistant responses.
- Streaming should be used when available; polling/reload is acceptable fallback.
- Input requests and tool approvals must be visible and actionable.

### FR-5: Notifications
- Client should surface important operator-required events: approvals, clarifications, failures, and completed tasks.
- Notification deep links should open the relevant project/task/session when possible.

### FR-6: Shared models and compatibility
- API payloads are decoded using shared protocol/SDK types where possible.
- Unknown fields must be ignored for forward compatibility.
- Version mismatch should degrade gracefully with a clear unsupported-feature message.

### FR-7: Security
- Stored core URLs and credentials must use platform-appropriate secure storage.
- Secrets and tokens must not appear in UI logs or crash reports.
- Destructive actions require confirmation on mobile.

## 7. Public API Surface
The client should prioritize these endpoints through `SloppySDK`:
- `GET /health`
- `GET /v1/config`
- `GET /v1/bulletins`
- `GET /v1/projects`
- `GET /v1/projects/{projectId}`
- `GET /v1/projects/{projectId}/tasks/{taskId}`
- `PATCH /v1/projects/{projectId}/tasks/{taskId}`
- `POST /v1/projects/{projectId}/tasks/{taskId}/approve`
- `POST /v1/projects/{projectId}/tasks/{taskId}/reject`
- `GET /v1/agents`
- `GET /v1/agents/{agentId}/sessions`
- `POST /v1/agents/{agentId}/sessions/{sessionId}/messages`
- `GET /v1/agents/{agentId}/sessions/{sessionId}/stream`
- `POST /v1/agents/{agentId}/sessions/{sessionId}/input-requests/{requestId}/answer`

## 8. Native UX
1. Home screen shows connection status and operator-required items.
2. Project screen prioritizes tasks and active conversations over configuration-heavy controls.
3. Chat screen clearly displays running/waiting/error state and pending actions.
4. Approval/clarification sheets summarize risk and context before the user acts.
5. Settings screen manages core endpoint, credentials, diagnostics, and cache reset.

## 9. Edge Cases
- Core URL changes while a stream is active; stream must close and reconnect against the new endpoint only after confirmation.
- Mobile app goes to background during an agent run; UI should recover by fetching latest session detail.
- A task notification may refer to a deleted/archived task; show a tombstone or fallback project view.
- API adds fields unknown to the installed app; decoder must not fail for additive changes.
- Destructive actions issued twice due to retry must be idempotent or show current state.

## 10. Acceptance Criteria
1. User can connect to a running local/remote core and see runtime/project summary.
2. User can open a task, approve/reject it, and see updated state after refresh.
3. User can send a chat message to an agent session and observe response progress or final result.
4. User can answer a clarification/input request from mobile.
5. App handles core offline state without losing last readable snapshot.

## 11. Tests / Verification
- SDK: request construction, decoding compatibility, error mapping.
- Client: connection setup, task action flows, session/chat state, notification deep-link routing.
- Manual: run `sloppy run`, connect the native client, perform one task approval and one agent chat round trip.
