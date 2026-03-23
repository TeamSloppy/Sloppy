---
layout: doc
title: MCP Integration
---

# MCP Integration

Sloppy acts as an MCP (Model Context Protocol) client. You can connect external MCP servers and expose their tools, resources, and prompts to Sloppy agents. MCP servers are configured in the `mcp` section of `sloppy.json` or via agent tools at runtime.

## How it works

1. Each MCP server entry in config describes a connection (stdio subprocess or HTTP endpoint).
2. On first use, Sloppy connects to the server, initializes an MCP client session, and discovers available capabilities.
3. Discovered tools can be exposed as dynamic agent tools — agents call them like any built-in tool.
4. Resources and prompts are accessible through dedicated agent tools.

## Config format

MCP servers live in the `mcp.servers` array inside `sloppy.json`:

```json
{
  "mcp": {
    "servers": [
      {
        "id": "filesystem",
        "transport": "stdio",
        "command": "npx",
        "arguments": ["-y", "@modelcontextprotocol/server-filesystem", "/tmp/workspace"],
        "cwd": "/tmp",
        "timeoutMs": 15000,
        "enabled": true,
        "exposeTools": true,
        "exposeResources": true,
        "exposePrompts": true,
        "toolPrefix": "fs"
      }
    ]
  }
}
```

### Server fields

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `id` | string | — | Unique server identifier |
| `transport` | `"stdio"` \| `"http"` | `"stdio"` | Transport protocol |
| `command` | string | — | Executable path or command name (stdio only) |
| `arguments` | string[] | `[]` | Command-line arguments (stdio only) |
| `cwd` | string | — | Working directory for the subprocess (stdio only) |
| `endpoint` | string | — | HTTP endpoint URL (http only) |
| `headers` | object | `{}` | HTTP headers sent with every request (http only) |
| `timeoutMs` | int | `15000` | Connection and discovery timeout in milliseconds |
| `enabled` | bool | `true` | Whether the server is active |
| `exposeTools` | bool | `true` | Expose server tools as dynamic agent tools |
| `exposeResources` | bool | `true` | Allow agents to list and read resources |
| `exposePrompts` | bool | `true` | Allow agents to list and get prompts |
| `toolPrefix` | string | `"mcp.<id>"` | Prefix for dynamic tool IDs |

## Transport types

### stdio

Sloppy spawns the MCP server as a child process and communicates over stdin/stdout using JSON-RPC. This is the most common setup for local MCP servers.

```json
{
  "id": "brave-search",
  "transport": "stdio",
  "command": "npx",
  "arguments": ["-y", "@anthropic/mcp-server-brave-search"],
  "enabled": true
}
```

### http

Sloppy connects to a remote MCP server over HTTP with Streamable HTTP transport. Use this for hosted or shared MCP servers.

```json
{
  "id": "remote-db",
  "transport": "http",
  "endpoint": "https://mcp.example.com/v1",
  "headers": {
    "Authorization": "Bearer sk-..."
  },
  "timeoutMs": 30000,
  "enabled": true
}
```

## Dynamic tools

When `exposeTools` is `true`, Sloppy discovers all tools from the MCP server and registers them as dynamic agent tools. Each tool gets an ID in the format `<prefix>.<toolName>`:

- With default prefix: `mcp.filesystem.read_file`
- With custom `toolPrefix: "fs"`: `fs.read_file`

Agents can call these tools like any built-in tool. The tool's input schema, description, and annotations are passed through from the MCP server.

## Agent tools for MCP

Sloppy provides built-in agent tools to interact with MCP servers at runtime:

### Discovery tools

| Tool | Description |
| --- | --- |
| `mcp.list_servers` | List all configured MCP servers and their capabilities |
| `mcp.list_tools` | List tools exposed by a specific MCP server |
| `mcp.list_resources` | List resources exposed by a specific MCP server |
| `mcp.list_prompts` | List prompts exposed by a specific MCP server |

### Interaction tools

| Tool | Description |
| --- | --- |
| `mcp.call_tool` | Call any tool on an MCP server by name with arguments |
| `mcp.read_resource` | Read a resource by URI from an MCP server |
| `mcp.get_prompt` | Get a prompt template and resolved messages |

### Config management tools

| Tool | Description |
| --- | --- |
| `mcp.save_server` | Add or update an MCP server entry in runtime config |
| `mcp.remove_server` | Remove an MCP server from runtime config |
| `mcp.install_server` | Run an install command, then save the server to config |
| `mcp.uninstall_server` | Run an uninstall command and optionally remove from config |

## Examples

### Add an MCP server via config

Add a GitHub MCP server to `sloppy.json`:

```json
{
  "mcp": {
    "servers": [
      {
        "id": "github",
        "transport": "stdio",
        "command": "npx",
        "arguments": ["-y", "@modelcontextprotocol/server-github"],
        "enabled": true,
        "exposeTools": true
      }
    ]
  }
}
```

Set the `GITHUB_PERSONAL_ACCESS_TOKEN` environment variable before starting Sloppy.

### Add an MCP server at runtime

An agent can use the `mcp.save_server` tool to register a new server without restarting:

```json
{
  "id": "memory",
  "transport": "stdio",
  "command": "npx",
  "arguments": ["-y", "@modelcontextprotocol/server-memory"],
  "enabled": true,
  "exposeTools": true
}
```

### Call an MCP tool

Using the `mcp.call_tool` agent tool:

```json
{
  "server": "filesystem",
  "tool": "read_file",
  "arguments": {
    "path": "/tmp/workspace/README.md"
  }
}
```

### HTTP server with authentication

```json
{
  "id": "production-api",
  "transport": "http",
  "endpoint": "https://api.example.com/mcp",
  "headers": {
    "Authorization": "Bearer sk-prod-key",
    "X-Custom-Header": "value"
  },
  "timeoutMs": 30000,
  "enabled": true,
  "exposeTools": true,
  "exposeResources": false,
  "exposePrompts": false
}
```

## Connection lifecycle

- Connections are created lazily on first use and reused for subsequent requests.
- When config is updated at runtime, obsolete connections (removed servers) are disconnected automatically.
- Discovery of dynamic tools runs once per config change and is cached until the next config update.
- A configurable timeout prevents slow servers from blocking startup.

## Guardrails

Install and uninstall commands executed through `mcp.install_server` and `mcp.uninstall_server` are subject to the runtime guardrails policy:

- Commands are checked against `deniedCommandPrefixes` before execution.
- Execution timeout is controlled by `execTimeoutMs`.
- Output is capped at `maxExecOutputBytes`.
