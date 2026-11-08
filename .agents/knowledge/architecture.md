# Architecture navigation

Keep request flow `CoreHTTPServer → CoreRouter → CoreService → AgentRuntime → SQLiteStore`.
`Sources/Protocols` is the bottom dependency for shared wire/runtime models. Provider and
plugin contracts belong in `PluginSDK`; reusable computer-control daemon logic belongs in
`Sources/NodeCore`, with process wiring in `Sources/Node`.

`Sources/sloppy/CoreService*.swift` splits domain facades. Routers live under
`Sources/sloppy/Gateway/Routers`; tools under `Sources/sloppy/Tools/AgentTools` implement
`CoreTool` and register through `ToolRegistry`. Preserve typed 4xx errors at HTTP boundaries.

Runtime orchestration lives in `Sources/AgentRuntime`; product composition, provider
sessions, MCP/ACP, Swarm, Visor and tools live under `Sources/sloppy`. Never infer agent
state, progress or completion from natural-language fragments. Use typed events, explicit
API fields, tool-call records, planner intents and persisted metadata.

For SQLite changes update `Sources/sloppy/Storage/schema.sql`, append the next transactional
migration in `SQLiteStore+Migrations.swift`, extend `PersistenceStore`, and preserve the
in-memory fallback. Do not add new migrations to baseline migration functions.

Dashboard routing is owned by `Dashboard/src/app/routing/`; the shared API surface is
`Dashboard/src/shared/api/coreApi.ts`. Feature components belong under `features/`, larger
route views under `views/`. Use the existing custom dropdown pattern, never a native select.

Apple networking/models belong in `Apps/Client/Sources/SloppyClientCore`, shared UI in
`SloppyClientUI`, and screens in the owning `SloppyFeature*` target. Read `Apps/docs/adr/`
before changing client architecture. Runtime inspection uses AdaMCP when available.

`ClientNative/` is a separate SwiftUI client and desktop companion (macOS/iOS/visionOS 26),
with its own manifest and tests. Shared `Packages/Sloppy*` source can affect it even when
the AdaEngine client in `Apps/Client` is unchanged. Run owning package suites as well as
root/downstream tests; dependency package test targets are not run by the root suite.
