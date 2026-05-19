# Sloppy SDK

Sloppy can be embedded into another Swift package at two levels:

- `SloppySDK` is the recommended first integration layer. It is a typed Swift client for a running Sloppy Core API process.
- `AgentRuntime`, `PluginSDK`, and `Protocols` expose lower-level runtime and plugin contracts for host apps that want to assemble their own harness.

`SloppySDK` keeps Sloppy as a sidecar process. This works well for apps that want agent sessions, project context, tools, approvals, memory, MCP, and model routing without linking the full Core service into their own process.

## Add The Package

```swift
// Package.swift
.package(url: "https://github.com/TeamSloppy/Sloppy.git", branch: "main")
```

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "SloppySDK", package: "Sloppy")
    ]
)
```

## Run Sloppy Core

```bash
sloppy run --no-gui --config-path sloppy.json
```

By default, the SDK connects to `http://127.0.0.1:7331`. Pass a custom base URL when Sloppy is bound elsewhere.

## Use An Agent Session

```swift
import Foundation
import SloppySDK

let client = SloppyClient(baseURL: URL(string: "http://127.0.0.1:7331")!)

let session = try await client.createAgentSession(
    agentID: "builder",
    request: .init(title: "Build from host app")
)

let response = try await client.sendMessage(
    agentID: "builder",
    sessionID: session.id,
    userID: "my-app",
    content: "Inspect this repository and suggest the smallest safe next step.",
    mode: .ask
)

print(response.summary.lastMessagePreview ?? "")
```

## Authentication

If dashboard/Core API auth is enabled, pass the bearer token:

```swift
let client = SloppyClient(
    baseURL: URL(string: "http://127.0.0.1:7331")!,
    bearerToken: token
)
```

## Current Surface

`SloppySDK` currently covers:

- list, create, read, and delete agents
- list, create, read, message, control, append events to, and delete agent sessions
- add working directories to a session
- post channel messages
- list channel events
- control active channel work

For non-Swift projects, use the same Core API over HTTP directly. For in-process Swift embedding, use `AgentRuntime` and `PluginSDK` directly until a future `SloppyCore` library target is split out of the CLI executable.
