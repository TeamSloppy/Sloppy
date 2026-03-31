# ``AdaMCPCore``

`AdaMCPCore` turns a live AdaEngine application into an inspection-friendly MCP runtime.

## Overview

Use `AdaMCPCore` when you need to expose live engine state to tools, agents, or external automation:

- Inspect worlds, entities, components, resources, and assets.
- Capture render output for visual verification.
- Inspect AdaUI windows and view trees.
- Run a small, deterministic set of AdaUI actions such as focus traversal, scrolling, and tapping a resolved node.

`AdaMCP` is transport-agnostic at the runtime layer. `AdaMCPServer` handles MCP server wiring, while `AdaMCPPlugin` embeds the runtime inside an AdaEngine app.

## Topics

### Essentials

- <doc:Getting-Started-With-AdaMCP>
- <doc:AdaUI-Inspection-and-Automation>

### Core types

- ``AdaMCPRuntime``
- ``MCPServerConfiguration``
- ``RenderCaptureService``
