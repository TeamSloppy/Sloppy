---
layout: doc
title: ACP Integration
---

# ACP Integration

Sloppy supports ACP (Agent Client Protocol) to delegate agent work to external coding agents like Claude Code. An ACP target is a subprocess that Sloppy launches and communicates with over stdio using JSON-RPC. When an agent is configured with ACP runtime, messages are forwarded to the external agent instead of the built-in generation pipeline.

Sloppy can also run as an ACP server for IDEs. In that mode an IDE launches `sloppy acp serve`, and Sloppy exposes one configured Sloppy agent as the ACP provider.

## How it works

1. You define ACP targets in the `acp` section of `sloppy.json`.
2. You create a Sloppy agent with `runtime.type` set to `"acp"` and `runtime.acp.targetId` pointing at one of the configured targets.
3. When a message arrives for that agent, Sloppy launches the ACP target subprocess, creates a session, and forwards the prompt.
4. The external agent's responses (text chunks, tool calls, plans, thoughts) stream back through Sloppy's session event system.

## Config format

ACP configuration lives in the `acp` section of `sloppy.json`:

```json
{
  "acp": {
    "enabled": true,
    "server": {
      "enabled": true,
      "agentId": "dev",
      "cwd": "/projects/my-app"
    },
    "targets": [
      {
        "id": "claude-code",
        "title": "Claude Code",
        "transport": "stdio",
        "command": "/usr/local/bin/claude",
        "arguments": ["--mcp"],
        "cwd": "/tmp/workspace",
        "environment": {
          "ANTHROPIC_API_KEY": "sk-ant-..."
        },
        "timeoutMs": 60000,
        "enabled": true
      }
    ]
  }
}
```

### Top-level fields

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `enabled` | bool | `false` | Enable the ACP gateway globally |
| `targets` | Target[] | `[]` | List of ACP target definitions |
| `server` | object | disabled | Settings for exposing Sloppy itself as an ACP server |

### Server fields

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `enabled` | bool | `false` | Allow `sloppy acp serve` to expose Sloppy over ACP stdio |
| `agentId` | string | — | Default Sloppy agent to expose when `--agent` is omitted |
| `cwd` | string | — | Default working directory used for new ACP sessions |

### Target fields

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `id` | string | — | Unique target identifier |
| `title` | string | same as `id` | Display name shown in the Dashboard |
| `transport` | `"stdio"`, `"ssh"`, `"websocket"` | `"stdio"` | Transport protocol for the upstream ACP target |
| `command` | string | — | Path to the agent executable |
| `arguments` | string[] | `[]` | Command-line arguments passed to the agent |
| `cwd` | string | workspace root | Working directory for the subprocess |
| `environment` | object | `{}` | Environment variables passed to the subprocess |
| `timeoutMs` | int | `30000` | Timeout for initialization and prompt operations |
| `enabled` | bool | `true` | Whether the target is active |

## Setting up an agent with ACP runtime

### Step 1: Enable ACP and add a target

Add the `acp` section to `sloppy.json`:

```json
{
  "acp": {
    "enabled": true,
    "targets": [
      {
        "id": "claude-code",
        "title": "Claude Code",
        "command": "/usr/local/bin/claude",
        "arguments": ["--mcp"],
        "environment": {
          "ANTHROPIC_API_KEY": "sk-ant-..."
        },
        "timeoutMs": 60000
      }
    ]
  }
}
```

### Step 2: Create an agent with ACP runtime

Via the API:

```bash
curl -X POST http://localhost:25101/v1/agents \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "id": "claude-agent",
    "displayName": "Claude Code Agent",
    "role": "coder",
    "runtime": {
      "type": "acp",
      "acp": {
        "targetId": "claude-code",
        "cwd": "/projects/my-app"
      }
    }
  }'
```

Or update an existing agent's config:

```bash
curl -X PUT http://localhost:25101/v1/agents/claude-agent/config \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "runtime": {
      "type": "acp",
      "acp": {
        "targetId": "claude-code"
      }
    },
    "documents": { ... },
    "selectedModel": null
  }'
```

### Step 3: Send messages

Messages sent to the agent are forwarded to the ACP target:

```bash
curl -X POST http://localhost:25101/v1/agents/claude-agent/sessions/my-session/message \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{ "content": "Implement a REST API for user management" }'
```

## Agent runtime types

Each Sloppy agent has a `runtime` config that determines how it processes messages:

| Runtime type | Description |
| --- | --- |
| `native` | Default. Uses the built-in generation pipeline with configured LLM providers. |
| `acp` | Delegates to an external agent via ACP. Requires `acp.targetId`. |

The `runtime.acp.cwd` field optionally overrides the working directory for the ACP session. If omitted, the target's `cwd` is used, falling back to the workspace root.

## Probe API

Before saving a target, you can verify connectivity with the probe endpoint:

```bash
curl -X POST http://localhost:25101/v1/acp/targets/probe \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "target": {
      "id": "claude-code",
      "title": "Claude Code",
      "transport": "stdio",
      "command": "/usr/local/bin/claude",
      "arguments": ["--mcp"],
      "timeoutMs": 60000,
      "enabled": true
    }
  }'
```

The response includes:

| Field | Description |
| --- | --- |
| `ok` | Whether the target was reachable and initialized |
| `targetId` | Target identifier |
| `agentName` | Name reported by the ACP agent |
| `agentVersion` | Version reported by the ACP agent |
| `supportsSessionList` | Whether the agent supports listing sessions |
| `supportsLoadSession` | Whether the agent supports loading existing sessions |
| `supportsPromptImage` | Whether the agent accepts image prompts |
| `supportsMCPHTTP` | Whether the agent supports MCP over HTTP |
| `supportsMCPSSE` | Whether the agent supports MCP over SSE |
| `message` | Human-readable status message |

## Dashboard configuration

The Dashboard provides a visual editor for ACP targets under **Settings > ACP**.

1. Toggle **ACP Server** on if you want IDEs to connect to Sloppy as an ACP provider.
2. Set the server **Agent ID** and optional working directory.
3. Copy the displayed IDE command, for example `sloppy acp serve --agent dev --cwd /projects/my-app`.
4. Toggle the **ACP Runtime** gateway to enabled if you want Sloppy agents to delegate to external ACP targets.
5. Click **Add Target** to open the target form.
6. Fill in the target fields (id, title, command, arguments, environment).
7. Click **Probe** to test connectivity before saving.
8. Click **Save** to persist the target to config.

To run Sloppy as an ACP server manually:

```bash
sloppy acp serve --agent dev --cwd /projects/my-app
```

The command speaks ACP JSON-RPC over stdio. Do not wrap it in `sloppy run`; IDEs should launch it directly.

For one-off non-interactive prompts without starting the server:

```bash
sloppy -p "Summarize the current project" --agent dev --cwd /projects/my-app
```

The `-p` mode loads the local config, creates or resumes a Sloppy session, prints the final assistant answer to stdout, and exits.

For upstream ACP targets:

1. Toggle the **ACP Runtime** gateway to enabled.
2. Click **Add Target** to open the target form.
3. Fill in the target fields (id, title, command, arguments, environment).
4. Click **Probe** to test connectivity before saving.
5. Click **Save** to persist the target to config.

To assign an ACP runtime to an agent, open the agent's settings page and change the runtime type to ACP, then select the target.

## Session lifecycle

- A new ACP session is created for each `(agentID, sloppySessionID)` pair on first message.
- The session persists across messages within the same Sloppy session.
- If the target config changes, existing sessions are terminated and recreated.
- Sessions are cleaned up when the Sloppy session ends or on shutdown.
- If the ACP subprocess terminates unexpectedly, the next message creates a fresh session.

## Streaming events

ACP sessions stream events back to Sloppy in real time:

| Event type | Description |
| --- | --- |
| Text chunks | Agent response text, streamed incrementally |
| Thought chunks | Agent reasoning/thinking, shown as thinking segments |
| Plan updates | Structured plan with status entries |
| Tool calls | External agent's tool invocations with content and status |
| Tool results | Completion or failure of tool calls |
| Session info | Title and metadata updates |

## Permissions

Sloppy's ACP client delegate handles permission requests from the external agent. By default, it auto-approves with "allow once" when available. File system read/write and terminal operations requested by the ACP agent are executed locally by Sloppy.

## Minimal target config

A target only requires `id` and `command`:

```json
{
  "id": "minimal-agent",
  "command": "/usr/bin/my-agent"
}
```

All other fields use defaults: `title` defaults to `id`, `transport` to `"stdio"`, `timeoutMs` to `30000`, `enabled` to `true`.
