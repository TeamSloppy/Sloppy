---
layout: doc
title: About Channels
---

# About Channels

Channels are the primary conversation endpoints in Sloppy. Each channel is a named context that receives messages from users, maintains conversation history, and routes requests to the agent runtime.

## What is a channel

A channel is identified by a unique string ID such as `"main"` or `"support"`. The ID is arbitrary — you choose it when configuring bindings. A single Sloppy instance can run any number of channels simultaneously.

Channels are not created through a setup wizard. They come into existence the first time a message is delivered to them (either via a platform plugin or the HTTP API) and persist in the runtime for the duration of the process.

## How messages flow

```
Platform (Telegram / Discord)
        │
        ▼
  Gateway Plugin
  (in-process)
        │
        ▼
POST /v1/channels/{channelId}/messages
        │
        ▼
  ChannelRuntime  ──── ingests message, decides route
        │
        ▼
   WorkerRuntime  ──── runs agent, streams response back
        │
        ▼
  ChannelDeliveryService
        │
        ▼
  Gateway Plugin  ──── delivers reply to platform
```

Messages can also enter a channel directly through the HTTP API, which is useful for custom integrations or testing:

```http
POST /v1/channels/{channelId}/messages
Content-Type: application/json
Authorization: Bearer <token>

{
  "userId": "user-123",
  "content": "Hello"
}
```

## Bindings

A **binding** connects a platform-specific chat identifier to a Sloppy channel ID. Without a binding, the plugin cannot route an incoming message to a channel and will drop it.

### Telegram bindings

Bindings are configured in `sloppy.json` under `channels.telegram.channelChatMap`. The key is the Sloppy channel ID; the value is the Telegram `chat_id` (negative for groups and supergroups, positive for private chats).

```json
{
  "channels": {
    "telegram": {
      "botToken": "...",
      "channelChatMap": {
        "main": -1001234567890,
        "support": 987654321
      }
    }
  }
}
```

### Discord bindings

Bindings are configured under `channels.discord.channelDiscordChannelMap`. The key is the Sloppy channel ID; the value is the Discord channel ID (a 64-bit integer represented as a string).

```json
{
  "channels": {
    "discord": {
      "botToken": "...",
      "channelDiscordChannelMap": {
        "main": "1234567890123456789"
      }
    }
  }
}
```

### Catch-all binding (Telegram only)

Setting a Telegram `chat_id` value to `0` creates a catch-all binding. Any chat that does not match an explicit binding is routed to that channel. The plugin remembers the last active chat ID from inbound messages and uses it for outbound delivery.

```json
"channelChatMap": {
  "main": 0
}
```

## Access control

Each built-in channel plugin supports two access control modes.

### Static allowlists

When `allowedUserIds` (and for Discord: `allowedGuildIds`, `allowedChannelIds`) are configured with one or more entries, the plugin enforces them before routing any message. Messages from IDs not in the list are rejected immediately with an explanation to the user.

### Approval flow

When no static allowlists are set, the plugin falls back to a database-backed approval flow. The first message from an unknown user triggers a pending-approval entry. An administrator can then approve, reject, or block the request through the Dashboard or the REST API.

| Endpoint | Purpose |
| --- | --- |
| `GET /v1/channel-approvals/pending` | List pending requests |
| `POST /v1/channel-approvals/{id}/approve` | Approve a request |
| `POST /v1/channel-approvals/{id}/reject` | Reject a request |
| `POST /v1/channel-approvals/{id}/block` | Block the user permanently |
| `GET /v1/channel-approvals/users` | List approved and blocked users |

## Bot commands

Both built-in plugins register a shared set of slash commands. These are handled locally by the plugin and do not consume agent processing time unless the command is forwarded.

| Command | Description |
| --- | --- |
| `/help` | Show available commands |
| `/status` | Check plugin connectivity |
| `/new` | Start a new session with the agent |
| `/whoami` | Show channel ID, user ID, and platform |
| `/task <description>` | Create a task via Sloppy |
| `/model [model_id]` | Show or switch the channel model |
| `/context` | Show token usage and context info |
| `/abort` | Abort current agent processing |
| `/create-skill <description>` | Create a new agent skill |
| `/create-subagent <description>` | Create a subagent |
| `/fork <task>` | Fork an operation to a subagent |

## Streaming

Telegram and Discord both support streaming responses. When the agent produces output incrementally, the plugin edits the placeholder message in place rather than sending multiple messages. Edits are throttled to at most once per second to stay within platform rate limits.

When the final content is empty or the stream is cancelled, the placeholder is deleted automatically.

## Channel model override

Each channel can use a model different from the system default. The override persists across restarts.

Via the CLI:

```bash
sloppy channel model set main --model "openai:gpt-4.1"
sloppy channel model get main
sloppy channel model clear main
```

Via the HTTP API:

```http
PUT /v1/channels/{channelId}/model
Content-Type: application/json

{ "model": "openai:gpt-4o" }
```

Clear the override to return to the default:

```http
DELETE /v1/channels/{channelId}/model
```

Users can also switch models via the `/model <model_id>` bot command inside any active channel.

## Channel state

The current state of a channel (message history, context utilization, active workers) can be inspected via the CLI:

```bash
sloppy channel state <channelId>
sloppy channel events <channelId> --limit 100
```

Or via the HTTP API:

```http
GET /v1/channels/{channelId}/state
GET /v1/channels/{channelId}/events
```

## Control actions

Abort or pause a running agent response from the CLI:

```bash
sloppy channel control <channelId> --action abort
```
