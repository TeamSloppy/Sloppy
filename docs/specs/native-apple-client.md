# Native Apple Client Spec

## 1. Document Status
- Version: `0.2`
- Date: `2026-06-28`
- Status: `Implementation-aligned (build + smoke verified)`
- Owners: `Apps/Client`, `SloppySDK`, `Dashboard`
- Primary code areas: `Apps/Client`, `Sources/SloppySDK`, `Sources/Protocols`

> **Workspace:** `Apps/Client` is the canonical Apple client package. The top-level `ClientNative/` directory is an older snapshot without AdaEngine/AdaMCP and must not be used for new work.

## 2. Product Context
The native Apple client gives operators mobile and macOS access to the same Sloppy runtime used by Dashboard and CLI. Its purpose is to keep agents reachable from a phone or native desktop environment while reusing HTTP/WebSocket APIs and shared protocol models from the core service.

The app is built on **AdaEngine + AdaUI** as a standalone SwiftPM workspace. Runtime integration is HTTP plus WebSocket against a running Sloppy core (`sloppy run`).

## 3. Goals
1. Provide a native control surface for runtime overview, projects, tasks, channels, and agent chat.
2. Reuse shared protocol models (`Protocols` / `SloppySDK` at the repo root; `SloppyClientCore` inside the client package) instead of duplicating API contracts.
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
| API client | `SloppyClientCore.SloppyAPIClient` (app) or root `SloppySDK.SloppyClient` (library integrators). |
| Native session | Local UI state around a remote Sloppy agent/channel session. |
| Operator action | Mobile-safe mutation such as send message, approve tool/task, answer clarification, or change task status. |
| Offline state | Cached read-only snapshots shown when the core is unreachable. |

## 6. Module Map (`Apps/Client`)
| Module | Responsibility |
| --- | --- |
| `SloppyClient` | App entry (`SloppyClientApp`), shell routing, splash, connection setup |
| `SloppyClientCore` | Settings, `SloppyAPIClient`, WebSocket managers, deep links, models |
| `SloppyClientUI` | Theme, icons, shared visual primitives |
| `SloppyFeatureChat` | Chat screen, composer, session picker |
| `SloppyFeatureAgents` | Agent list/detail |
| `SloppyFeatureProjects` | Project list/detail |
| `SloppyFeatureOverview` | Runtime overview |
| `SloppyFeatureSettings` | Client + server config editing |

## 7. Functional Requirements

### FR-1: Connection setup
- User can configure the Sloppy core base URL.
- Client validates connectivity with a health/config request.
- Connection errors distinguish unreachable host, incompatible version, and authentication failure where applicable.

**Status:** Implemented — splash reconnect, manual host/port, local network discovery, `sloppy://connect` deep links.

### FR-2: Runtime overview
- Client can show core status, bulletins, channels/sessions, and recent activity at a glance.
- Runtime status should be refreshable manually and eventually by background refresh where platform allows.

**Status:** Partial — overview/projects/agents screens exist; polish and parity still in progress.

### FR-3: Project and task access
- Client can list projects, inspect project detail, view task board/list, and open task detail.
- Mobile-safe task actions include status update, approval/rejection, clarification answer, and comment where supported.

**Status:** Partial — project surfaces scaffolded; task approval flows not complete on mobile.

### FR-4: Chat and channels
- Client can open an agent or channel session, send a message, and display assistant responses.
- Streaming should be used when available; polling/reload is acceptable fallback.
- Input requests and tool approvals must be visible and actionable.

**Status:** Implemented — chat UI, session streaming over WebSocket, composer.

### FR-5: Notifications
- Client should surface important operator-required events: approvals, clarifications, failures, and completed tasks.
- Notification deep links should open the relevant project/task/session when possible.

**Status:** Partial — in-app WebSocket banners work; APNs push is roadmap.

### FR-6: Shared models and compatibility
- API payloads are decoded using shared protocol/SDK types where possible.
- Unknown fields must be ignored for forward compatibility.
- Version mismatch should degrade gracefully with a clear unsupported-feature message.

**Status:** Implemented in `SloppyClientCore`; ongoing alignment with `Protocols`.

### FR-7: Security
- Stored core URLs and credentials must use platform-appropriate secure storage.
- Secrets and tokens must not appear in UI logs or crash reports.
- Destructive actions require confirmation on mobile.

**Status:** Partial — client settings persisted; hardening still in progress.

## 8. Public API Surface
The client should prioritize these endpoints (via `SloppyClientCore` / `SloppySDK`):
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
- `GET /v1/notifications/ws` (in-app banners)
- `GET /v1/agents/{agentId}/sessions/{sessionId}/ws` (session streaming)

## 9. Native UX
1. Home screen shows connection status and operator-required items.
2. Project screen prioritizes tasks and active conversations over configuration-heavy controls.
3. Chat screen clearly displays running/waiting/error state and pending actions.
4. Approval/clarification sheets summarize risk and context before the user acts.
5. Settings screen manages core endpoint, credentials, diagnostics, and cache reset.

## 10. Edge Cases
- Core URL changes while a stream is active; stream must close and reconnect against the new endpoint only after confirmation.
- Mobile app goes to background during an agent run; UI should recover by fetching latest session detail.
- A task notification may refer to a deleted/archived task; show a tombstone or fallback project view.
- API adds fields unknown to the installed app; decoder must not fail for additive changes.
- Destructive actions issued twice due to retry must be idempotent or show current state.

## 11. Acceptance Criteria
1. User can connect to a running local/remote core and see runtime/project summary.
2. User can open a task, approve/reject it, and see updated state after refresh.
3. User can send a chat message to an agent session and observe response progress or final result.
4. User can answer a clarification/input request from mobile.
5. App handles core offline state without losing last readable snapshot.

**Current smoke (2026-06-28):** criteria 1 and 3 pass on macOS with `sloppy` running on `localhost:25101`. Criteria 2, 4, 5 need explicit QA passes.

## 12. Build and Run

### Prerequisites
- macOS 15+
- Xcode 26.3 (Swift 6.2 toolchain)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for `.xcodeproj` generation
- Initialized submodules: `git submodule update --init --recursive`
- Running core for live data: `swift run sloppy run` (default `http://localhost:25101`)

### macOS — SwiftPM (fastest dev loop)
```bash
cd Apps/Client
swift package resolve
swift build
swift run SloppyClient
```

If build fails with `module compiled with Swift X cannot be imported by Swift Y`, clear stale artifacts:
```bash
rm -rf .build
swift build
```

### macOS — Xcode project
```bash
cd Apps/Client
xcodegen generate
xcodebuild -project SloppyClient.xcodeproj \
  -scheme SloppyClient-macOS \
  -destination 'platform=macOS' \
  -configuration Debug \
  -skipPackagePluginValidation \
  build
open ~/Library/Developer/Xcode/DerivedData/SloppyClient-*/Build/Products/Debug/SloppyClient-macOS.app
```

### iOS Simulator — SwiftPM Xcode scheme (recommended today)
Open `Apps/Client/Package.swift` in Xcode, select the **SloppyClient** scheme, choose an iPhone simulator, Run.

CLI equivalent:
```bash
cd Apps/Client
open Package.swift   # or: xed .
xcodebuild -scheme SloppyClient \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug \
  -skipPackagePluginValidation \
  build
```

This produces a simulator binary under DerivedData `Debug-iphonesimulator/SloppyClient`. Install/launch an `.app` bundle via Xcode Run, or reuse a previously installed simulator build:
```bash
xcrun simctl launch booted team.sloppy.client
```

### iOS — XcodeGen app target (signing / TestFlight path)
```bash
cd Apps/Client
xcodegen generate
xcodebuild -project SloppyClient.xcodeproj \
  -scheme SloppyClient-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug \
  -skipPackagePluginValidation \
  build
```

**Known issue (2026-06-28):** `SloppyClient-iOS` via generated `.xcodeproj` can fail building `AdaEngineMacros` for the simulator (`SwiftCompilerPlugin` not found). Use the SwiftPM **SloppyClient** scheme for simulator dev until macro host wiring is fixed upstream. macOS XcodeGen builds succeed.

### Tests
```bash
cd Apps/Client
swift test
swift test --filter SloppyClientCoreTests
swift test --filter SloppyFeatureChatTests
```

## 13. Live Inspection (DEBUG)
DEBUG builds embed **AdaMCP** at `http://127.0.0.1:2510/mcp` for UI/runtime inspection (`ui.get_tree`, `ui.hit_test`, `ui.tap_node`, screenshots). See `Apps/Client/README.md` and `AGENTS.md` (AdaMCP debugging flow).

Example (macOS, app running):
```bash
# Initialize MCP session, then call ui.get_tree / ui.hit_test / ui.tap_node
# Tools require MCP-Session-Id header on follow-up requests.
```

## 14. Verification Checklist

### Automated
| Command | Expected |
| --- | --- |
| `cd Apps/Client && swift build` | Build complete |
| `cd Apps/Client && swift test --filter SloppyClientCoreTests` | Core tests pass (sidebar rendering tests may fail — track separately) |
| `xcodebuild … SloppyClient-macOS … build` | BUILD SUCCEEDED |
| `xcodebuild -scheme SloppyClient -destination 'platform=iOS Simulator,…' build` | BUILD SUCCEEDED |

### Manual smoke (with `sloppy run`)
1. Launch macOS client (`swift run SloppyClient`).
2. Confirm auto-reconnect or connect to `http://localhost:25101`.
3. Open chat, send a message, observe streaming/final response.
4. Tap sidebar rows and header controls (settings, session picker).
5. Launch iOS simulator build; repeat connection + chat smoke.
6. Optional: inspect live UI via AdaMCP on port `2510`.

### Verified 2026-06-28
- macOS `swift build` + `swift run SloppyClient` — **pass** (connected to `localhost:25101`, WebSocket session + notifications active).
- macOS `xcodebuild SloppyClient-macOS` — **pass** (after DerivedData clean; use `-skipPackagePluginValidation`).
- iOS `xcodebuild -scheme SloppyClient` (SwiftPM) — **pass**.
- iOS `xcodebuild SloppyClient-iOS` (XcodeGen) — **fail** (`AdaEngineMacros` / SwiftSyntax host modules).
- iOS simulator launch of existing `team.sloppy.client` install — **pass**.
- AdaMCP `ui.hit_test` resolves sidebar `Button` nodes; `ui.tap_node` works for large containers, some leaf buttons return `ui_node_not_found` (track in AdaMCP/AdaUI).

## 15. Roadmap (not in v0.1)
- Task approval/reject/clarification flows on mobile
- Review/diff surfaces
- APNs registration and push deep links
- Replace `ClientNative/` references in local tooling with `Apps/Client`
- Fix XcodeGen iOS macro host build for CI parity

## 16. Related Docs
- [`Apps/Client/README.md`](../../Apps/Client/README.md)
- [`Apps/docs/current-state.md`](../../Apps/docs/current-state.md)
- [`Apps/docs/adr/0005-build-distribution-and-push.md`](../../Apps/docs/adr/0005-build-distribution-and-push.md)
- [`docs/guides/sdk.md`](../guides/sdk.md) — root `SloppySDK` for non-UI integrators
