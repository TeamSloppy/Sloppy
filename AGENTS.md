# AGENTS.md

Guidance for coding agents working in this repository.
Project type: Swift Package (Swift 6.x) + React/Vite dashboard.

## Scope and stack
- Package manager: SwiftPM (`Package.swift`)
- Swift platform: macOS 14+
- Executables: `sloppy`, `SloppyNode`
- Libraries: `Protocols`, `PluginSDK`, `AgentRuntime`
- Dashboard: `Dashboard/` (`react`, `vite`)
- Persistence: SQLite (`sqlite3`)
- Test framework: Swift Testing (`import Testing`, `@Test`, `#expect`)

## Build, lint, test, run
Run from repo root unless noted.

### Resolve dependencies
- `swift package resolve`

### Build (Swift)
- `swift build`
- `swift build -c release`
- `swift build -c release --product sloppy`
- `swift build -c release --product SloppyNode`

### Test (Swift)
- Full suite: `swift test`
- Parallel suite: `swift test --parallel`
- List tests: `swift test list`

### Run a single Swift test (important)
- By exact name:
  - `swift test --filter CoreTests.postChannelMessageEndpoint`
- By test group:
  - `swift test --filter CoreTests`
  - `swift test --filter AgentRuntimeTests`
- Note: `swift test --list-tests` is deprecated; use `swift test list`.

### Run executables
- `swift run sloppy`
- `swift run SloppyNode`

Useful `sloppy` flags:
- `swift run sloppy --oneshot`
- `swift run sloppy --run-demo-request`
- `swift run sloppy --config-path sloppy.json`

### Dashboard commands (inside `Dashboard/`)
- `npm install`
- `npm run dev`
- `npm run build`
- `npm run preview`

### Lint/format status
No dedicated lint/format config is committed for SwiftLint, swift-format, ESLint, or Prettier.
When changing code, preserve local style and validate with:
- `swift test --parallel`
- `swift build -c release --product sloppy`
- `npm run build` (when dashboard files change)

## CI parity checklist
CI (`.github/workflows/ci.yml`) runs:
- `swift test --parallel`
- `swift build -c release --product sloppy`
- `swift build -c release --product SloppyNode`
- `npm install` + `npm run build` in `Dashboard/`
Keep local changes green for the same command set.

## Code style guide

### Swift: imports and formatting
- Use 4-space indentation and no tabs.
- Keep imports minimal; place `Foundation` first when used.
- Follow existing multiline style and trailing commas.
- Keep files focused; extract helpers instead of large monolith methods.

### Swift: types and naming
- `UpperCamelCase` for types; `lowerCamelCase` for vars/functions.
- Prefer `struct` for DTO/protocol models; use `actor` for shared mutable state.
- Mark cross-target API explicitly with `public`.
- Add `Sendable` where values cross concurrency boundaries.
- Use enums for constrained state/actions (`RouteAction`, `WorkerMode`, etc.).
- For API-compatible values, use explicit raw values (snake_case when needed).

### Swift: error handling and resilience
- Use `throws` for recoverable boundary failures.
- In router/http boundaries, convert invalid payloads to stable 4xx responses.
- Prefer graceful fallback over crashing in runtime services.
- Avoid force unwraps and `fatalError` in production paths.
- Log operational failures with context and continue when safe.

### Swift: concurrency and architecture
- Prefer actor isolation to locking.
- Keep orchestration async end-to-end (`async`/`await`).
- Do not bypass actor boundaries with shared mutable globals.
- Maintain separation: transport (`CoreHTTPServer`) -> routing (`CoreRouter`) -> service (`CoreService`) -> runtime (`AgentRuntime`) -> persistence (`SQLiteStore`).

### Tests
- Use Swift Testing macros (`@Test`, `#expect`).
- Write behavior-focused tests with clear arrange/act/assert flow.
- Keep tests deterministic and isolated.
- For endpoint logic, test via router/service with realistic payloads.

### Dashboard (React)
- Use function components and hooks.
- Use named exports for components/utilities.
- Keep state local; derive computed values with `useMemo` when useful.
- Use `async/await` and handle non-OK responses explicitly.
- Match existing JS formatting: 2-space indent, semicolons, double quotes.
- For dropdown/select UI, always use the custom `.actor-team-search` dropdown pattern (see `ActorsView.tsx` and `actors.css`) — never use native `<select>` elements.

## Module map

### Swift targets
- `Sources/Protocols`
  - Shared domain and wire models (`APIModels`, `RuntimeModels`, JSON helpers, envelopes).
  - Base dependency for all runtime-facing modules.
- `Sources/PluginSDK`
  - Plugin contracts (`GatewayPlugin`, `ToolPlugin`, `MemoryPlugin`, `ModelProviderPlugin`).
  - AnyLanguageModel bridge implementation.
- `Sources/AgentRuntime`
  - Runtime actors and orchestration core.
  - Includes channel/worker/branch runtimes, compactor, visor, event bus, memory store, and `RuntimeSystem` facade.
- `Sources/sloppy`
  - Main backend executable and HTTP API server.
  - Includes config loading, router, service layer, NIO transport, and SQLite persistence.
- `Sources/Node` (product: `SloppyNode`)
  - Node daemon executable for process execution.

### Tests
- `Tests/ProtocolsTests`: protocol/model coding and compatibility.
- `Tests/AgentRuntimeTests`: routing and runtime flow.
- `Tests/CoreTests`: API/router/config behaviors.

### Client app (SloppyClient)
- `Apps/Client/`: Apple client app built with AdaEngine/AdaUI (iOS, iPadOS, macOS, visionOS).
- Project generated via `project.yml` (XcodeGen).
- Depends on `SloppyClientCore`, `SloppyClientUI`, feature modules, and `AdaMCPPlugin`.

### Debugging the client with AdaMCP
The client embeds `AdaMCP` (`Vendor/AdaMCP`) — an MCP server that exposes the live AdaEngine runtime for inspection.
When debugging UI or runtime issues in the client, use the `XcodeBuildMCP` and `AdaMCP` MCP servers:
- `XcodeBuildMCP` — build, run, and read Xcode logs/diagnostics.
- `AdaMCP` — inspect the running app: UI tree (`ui.get_tree`, `ui.find_nodes`, `ui.hit_test`), render capture (screenshots), world/entity/component/resource introspection, and safe UI actions (tap, scroll, focus traversal).

Typical debugging flow:
1. Build and launch the client via `XcodeBuildMCP`.
2. Connect to the running app's MCP endpoint (default `127.0.0.1:2510/mcp`).
3. Use AdaMCP tools to inspect the UI tree, capture screenshots, and locate the problem.
4. Target nodes by `accessibilityIdentifier` for stable references.

### Frontend/docs/support
- `Dashboard/`: React dashboard for Core API.
- `docs/specs/`: protocol/runtime specs.
- `docs/adr/`: architecture decisions.
- `Demos/`: quickstart/sample payloads.
- `utils/docker/`: Dockerfiles and compose assets.

## Common recipes

### Add a new API endpoint

1. **Model** — add `XxxRequest` / `XxxRecord` structs to `Sources/Protocols/APIModels.swift` under the relevant `// MARK:` section.
2. **Service method** — add the method to `Sources/sloppy/CoreService.swift` in the correct domain section. Use a typed error enum.
3. **Router** — add the route to the appropriate `XxxAPIRouter` in `Sources/sloppy/Gateway/Routers/`. If creating a new router, add it to `CoreRouter+HTTPRoutes.swift`.
4. **Test** — add a test in `Tests/sloppyTests/` using Swift Testing macros (`@Test`, `#expect`).
5. **Verify** — `swift test --filter sloppyTests.XxxTests` then `swift build -c release --product sloppy`.

### Add a new agent tool

1. **File** — create `Sources/sloppy/Tools/AgentTools/XxxTool.swift` conforming to `CoreTool`.
2. **Implement** — define `name`, `domain`, `title`, `status`, `description`, `parameters`, and `invoke(arguments:context:)`.
3. **Register** — add `XxxTool()` to the array in `ToolRegistry.makeDefault()` in `Sources/sloppy/Tools/ToolRegistry.swift`.
4. **Test** — add a test in `Tests/sloppyTests/` using `ToolContext` with injected fakes.
5. **Verify** — `swift test --filter sloppyTests.XxxTests` then `swift build -c release --product sloppy`.

### Add a new SQLite table or column

1. **Schema** — add `CREATE TABLE IF NOT EXISTS xxx (...)` or `ALTER TABLE xxx ADD COLUMN yyy TEXT` to the schema string in `Sources/sloppy/CorePersistenceFactory.swift`.
2. **CRUD methods** — add the read/write methods to `Sources/sloppy/SQLiteStore.swift` inside the `#if canImport(CSQLite3)` guard with a matching in-memory fallback.
3. **Protocol** — add the method signature to the `PersistenceStore` protocol in `Sources/sloppy/Stores/PersistenceStore.swift`.
4. **Verify** — `swift test --filter sloppyTests` then `swift build -c release --product sloppy`.

### Add a Dashboard view

1. **Component** — create `Dashboard/src/views/XxxView.jsx` (function component, named export).
2. **Route** — add the route in `Dashboard/src/App.tsx`.
3. **API** — add the fetch function to `Dashboard/src/shared/api/coreApi.ts`.
4. **CSS** — add `Dashboard/src/styles/xxx.css` and import it in the component.
5. **Verify** — `cd Dashboard && npm run build`.

## Cursor/Copilot rules status

Contextual rules for specific file areas live in `.cursor/rules/`:
- `router-pattern.mdc` — HTTP router structure and patterns
- `tool-pattern.mdc` — agent tool implementation
- `api-models.mdc` — APIModels.swift conventions
- `core-service.mdc` — CoreService domain map and patterns
- `sqlite-store.mdc` — SQLite C API patterns and migrations
- `tests.mdc` — Swift Testing framework usage
- `dashboard.mdc` — React/Vite dashboard conventions
- `agent-runtime.mdc` — AgentRuntime actor architecture

These rules are activated automatically when working with matching files and take precedence over the general guidance above.

## Agent execution expectations
- Make small, targeted edits aligned with existing module boundaries.
- Avoid introducing new frameworks without strong justification.
- Keep API behavior backward-compatible unless task explicitly allows breaking change.
- Update/add tests when changing behavior.
- Run the smallest relevant verification first, then CI-parity checks.
