# Getting Started With AdaMCP

`AdaMCP` exposes an AdaEngine host process as an MCP server. The package is split into three responsibilities:

- `AdaMCPCore`: builds inspection payloads from live runtime state.
- `AdaMCPServer`: serves those payloads through MCP over HTTP or stdio.
- `AdaMCPPlugin`: plugs everything into an AdaEngine app.

## Host versus client

The host and the client have different constraints:

- The host is the process running AdaEngine and AdaUI.
- The client is any MCP consumer that connects to that host.

Today the host package is `macOS 15+`, because `AdaMCP` is currently packaged around the desktop AdaEngine runtime. That does not limit the client to macOS. HTTP clients can connect from any device that can reach the host.
Today the host package targets the Apple platforms used by AdaEngine hosts: `macOS 15+`, `iOS 18+`, `tvOS 18+`, and `visionOS 2+`. That still does not limit the client to those platforms. HTTP clients can connect from any device that can reach the host.

## Embed the plugin

For application integration, `MCPPlugin` is the simplest entry point:

```swift
import AdaEngine
import AdaMCPPlugin

@main
struct ExampleApp: App {
    var body: some AppScene {
        WindowGroup {
            RootView()
        }
        .addPlugins(
            MCPPlugin(configuration: .init(
                enableHTTP: true,
                enableStdio: true,
                host: "127.0.0.1",
                port: 25102,
                endpoint: "/mcp",
                serverName: "example-app",
                serverVersion: "0.1.0",
                instructions: "Inspect the live AdaEngine runtime."
            ))
        )
    }
}
```

This gives you:

- world/entity/resource inspection tools
- render capture
- AdaUI inspection and safe actions
- transport startup and shutdown tied to the app lifecycle

## Run a server from a runtime

If you want more control, build a runtime and server directly:

```swift
import AdaMCPCore
import AdaMCPServer

let runtime = AdaMCPRuntime(
    appWorlds: appWorlds,
    registry: registry,
    renderCaptureService: captureService
)

let server = await AdaMCPServerFactory.makeServer(
    runtime: runtime,
    configuration: .init(
        enableHTTP: true,
        enableStdio: false,
        host: "127.0.0.1",
        port: 25102,
        endpoint: "/mcp",
        serverName: "example-app",
        serverVersion: "0.1.0"
    )
)
```

## Transport model

`AdaMCP` currently supports two transport modes:

- HTTP for external tools, remote agents, and device-to-device access
- stdio for local MCP host integration when a process-local transport makes sense

The transport is independent from the runtime surface. The same `AdaMCPRuntime` powers both modes.

## Surface design

The runtime is organized around stable, JSON-friendly results:

- tools for active queries and deterministic actions
- resources for durable read endpoints under `ada://...`
- resource templates for parameterized access patterns

The AdaUI surface follows a consistent loop:

1. locate a window or node
2. inspect the tree or node snapshot
3. diagnose layout and focus state
4. perform a limited action
5. verify by reading the surface again

Continue with <doc:AdaUI-Inspection-and-Automation> for the UI-specific contract.
