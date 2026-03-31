# AdaMCP

`AdaMCP` exposes a live AdaEngine application as an MCP server. It is built for inspection-first workflows: world/entity/resource introspection, render capture, and AdaUI tree inspection with a small set of safe UI actions.

## Modules

- `AdaMCPCore`: runtime surface, type introspection, AdaUI inspection, and tool/resource payloads.
- `AdaMCPServer`: MCP server bootstrapping plus HTTP and stdio transports.
- `AdaMCPPlugin`: AdaEngine plugin for embedding `AdaMCP` directly into an app.

## Current platform support

`AdaMCP` currently ships for Apple platforms used by AdaEngine hosts today: `macOS 15+`, `iOS 18+`, `tvOS 18+`, and `visionOS 2+`.

The important distinction is:

- MCP clients can live anywhere and connect over HTTP or stdio.
- The host runtime now builds on the broader Apple surface, while `stdio` remains primarily a local host transport and HTTP is the main cross-device option.

So `SloppyClient` no longer needs a `macOS`-only gate just to embed the MCP plugin.

## What you get

- World, entity, component, resource, and asset inspection.
- Screenshot capture for live render output.
- AdaUI inspection tools such as `ui.list_windows`, `ui.get_tree`, `ui.get_node`, `ui.find_nodes`, and `ui.hit_test`.
- AdaUI diagnostics and safe actions such as focus traversal, deterministic tap, and scroll-to-node.
- MCP resources under `ada://...`, including `ada://ui/windows`, `ada://ui/window/{id}`, `ada://ui/tree/{id}`, and `ada://ui/node/{windowId}/{nodeRef}`.

## Embedding in an AdaEngine app

Until the package is published, add it as a local SwiftPM dependency:

```swift
dependencies: [
    .package(path: "../AdaMCP")
]
```

Then add the plugin to your app:

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

## Runtime architecture

`AdaMCP` is split into three layers:

1. `AdaMCPRuntime` builds tool/resource payloads from live AdaEngine and AdaUI state.
2. `AdaMCPServerFactory` exposes that runtime through the official MCP Swift SDK.
3. `MCPPlugin` wires the runtime into an AdaEngine app and starts HTTP and/or stdio transports.

## AdaUI surface

AdaUI support is intentionally inspection-first. The main flow is:

1. Locate windows or nodes.
2. Inspect the live tree and layout diagnostics.
3. Apply a limited, deterministic action.
4. Re-read the tree or diagnostics to verify the result.

External callers should target nodes by `accessibilityIdentifier`. `runtimeId` is returned in payloads as a session-local helper, but it is not intended to be a durable contract.

## Documentation

- [DocC landing page](./Sources/AdaMCPCore/AdaMCPCore.docc/AdaMCPCore.md)
- [Getting Started With AdaMCP](./Sources/AdaMCPCore/AdaMCPCore.docc/Getting-Started-With-AdaMCP.md)
- [AdaUI Inspection and Automation](./Sources/AdaMCPCore/AdaMCPCore.docc/AdaUI-Inspection-and-Automation.md)

Swift Package Index configuration lives in [`./.spi.yml`](./.spi.yml).
