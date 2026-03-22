# Channel Plugin Protocol v1

Channel plugins are **external processes** that bridge Sloppy channels to
messaging platforms (Telegram, Slack, email, etc.). Communication between sloppy
and each plugin uses plain HTTP/JSON — the plugin can be written in any language.

## Lifecycle

1. Plugin process starts (manually or spawned by sloppy).
2. Plugin reads its configuration from environment variables, CLI arguments, or
   receives it via `POST /start` from sloppy.
3. Plugin begins listening for inbound messages from its platform (e.g. Telegram
   long-polling) and accepts outbound delivery requests from sloppy.

## Inbound (platform → sloppy)

When the plugin receives a user message from the external platform it forwards
it to sloppy using the standard channel message endpoint:

```
POST {CORE_BASE_URL}/v1/channels/{channelId}/messages
Content-Type: application/json

{
  "userId": "<platform-specific user id>",
  "content": "<message text>"
}
```

`channelId` is the Sloppy channel identifier mapped to this external chat
in the plugin configuration.

## Outbound (sloppy → plugin)

sloppy delivers messages to the plugin by calling:

```
POST {plugin_base_url}/deliver
Content-Type: application/json

{
  "channelId": "<sloppy channel id>",
  "userId": "<recipient hint — may be empty for broadcast>",
  "content": "<message text>"
}
```

Response: `200 OK` with `{ "ok": true }` on success, or an appropriate error
status. sloppy logs failures but does not retry automatically in v1.

### Optional outbound streaming

Plugins on platforms that support message editing may opt into a three-step
streaming flow:

```
POST {plugin_base_url}/stream/start
Content-Type: application/json

{
  "channelId": "<sloppy channel id>",
  "userId": "<recipient hint>"
}
```

Response:

```json
{ "ok": true, "streamId": "opaque-plugin-stream-id" }
```

Chunk updates:

```
POST {plugin_base_url}/stream/chunk
Content-Type: application/json

{
  "streamId": "opaque-plugin-stream-id",
  "channelId": "<sloppy channel id>",
  "content": "<progressively built text>"
}
```

Completion:

```
POST {plugin_base_url}/stream/end
Content-Type: application/json

{
  "streamId": "opaque-plugin-stream-id",
  "channelId": "<sloppy channel id>",
  "userId": "<recipient hint>",
  "content": "<final text or null>"
}
```

If any of these endpoints are absent, sloppy falls back to the regular
`/deliver` flow.

## Optional endpoints

### Validate

sloppy may call this **before** accepting an inbound message to let the plugin
decide whether the sender is allowed:

```
POST {plugin_base_url}/validate
Content-Type: application/json

{
  "channelId": "...",
  "userId": "...",
  "content": "..."
}
```

Response:

```json
{ "allowed": true }
```

or

```json
{ "allowed": false, "reason": "user not in allow list" }
```

If the endpoint is not implemented (404/501) sloppy treats the message as allowed.

### Start

sloppy may push configuration to the plugin at startup:

```
POST {plugin_base_url}/start
Content-Type: application/json

{
  "pluginId": "...",
  "channelIds": ["..."],
  "config": { "botToken": "...", "allowedUserIds": [...], ... }
}
```

The plugin should apply the received configuration and return `200 OK`.

## Plugin registration

Plugins are registered in sloppy via the `/v1/plugins` REST API or seeded from
the sloppy configuration file. Each registration record contains:

| Field        | Type     | Description                                      |
|-------------|----------|--------------------------------------------------|
| id          | string   | Unique plugin identifier (auto-generated or set) |
| type        | string   | Plugin kind, e.g. `"telegram"`, `"discord"`, `"slack"` |
| baseUrl     | string   | Root URL of the plugin HTTP server               |
| channelIds  | [string] | Sloppy channel IDs served by this plugin   |
| config      | object   | Arbitrary settings (tokens, allow-lists, etc.)   |
| enabled     | bool     | Whether sloppy should deliver to this plugin     |
| createdAt   | ISO 8601 | Creation timestamp                               |
| updatedAt   | ISO 8601 | Last update timestamp                            |

## Commands

Plugins may intercept platform-specific commands (e.g. `/task`, `/status`) and
either translate them into regular `content` for sloppy or handle them locally.
The set of supported commands is plugin-specific and should be documented per
plugin.

## Compatibility

- All payloads are JSON, UTF-8 encoded.
- Unknown fields must be ignored by both sides.
- Additive changes only; breaking changes require a version bump.
