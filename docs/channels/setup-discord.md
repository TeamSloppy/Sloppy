---
layout: doc
title: Setup Discord
---

# Setup Discord

This guide walks through connecting a Discord bot to a Sloppy channel.

## Prerequisites

- A running Sloppy instance with a valid `sloppy.json`.
- A Discord account with the ability to create applications.
- A Discord server where you have permission to add bots.

## 1. Create a Discord application and bot

1. Go to the [Discord Developer Portal](https://discord.com/developers/applications) and click **New Application**.
2. Give it a name and confirm.
3. Open the **Bot** tab and click **Add Bot**.
4. Under **Token**, click **Reset Token** and copy the token. You will need it in the next step.

### Enable the Message Content intent

Still on the **Bot** tab, scroll down to **Privileged Gateway Intents** and enable **Message Content Intent**. Without this, the bot cannot read message text from regular channels.

## 2. Invite the bot to your server

Go to the **OAuth2 → URL Generator** tab. Select the following scopes and permissions:

- Scopes: `bot`, `applications.commands`
- Bot permissions: `Send Messages`, `Read Message History`, `Read Messages/View Channels`

Copy the generated URL, open it in a browser, and invite the bot to your server.

## 3. Add the Discord config to sloppy.json

Add a `channels.discord` section to your `sloppy.json`:

```json
{
  "channels": {
    "discord": {
      "botToken": "YOUR_BOT_TOKEN",
      "channelDiscordChannelMap": {
        "main": "1234567890123456789"
      },
      "allowedGuildIds": [],
      "allowedChannelIds": [],
      "allowedUserIds": []
    }
  }
}
```

## 4. Find your Discord channel ID

1. Open Discord and go to **User Settings → Advanced**.
2. Enable **Developer Mode**.
3. Right-click the target channel in the server sidebar and select **Copy Channel ID**.

The ID is a large integer represented as a string (e.g. `"1234567890123456789"`).

## 5. Bindings

The `channelDiscordChannelMap` maps Sloppy channel IDs to Discord channel IDs.

```json
"channelDiscordChannelMap": {
  "main": "1234567890123456789",
  "alerts": "9876543210987654321"
}
```

Each key is a Sloppy channel ID. Each value is a Discord channel ID. Multiple Sloppy channels can be mapped to different Discord channels — each maintains its own conversation history and model settings.

Unlike Telegram, there is no catch-all binding for Discord. Every Discord channel that should receive agent responses must have an explicit entry.

## 6. Access control

### Static allowlists

Discord access control supports three independent filter levels. When any list is non-empty, all three are checked simultaneously.

| Field | Filters by |
| --- | --- |
| `allowedGuildIds` | Discord server (guild) ID |
| `allowedChannelIds` | Discord channel ID |
| `allowedUserIds` | Discord user ID |

A message is allowed only when it passes all non-empty filters. For example, to allow all users in a specific server but only in one channel:

```json
"allowedGuildIds": ["111111111111111111"],
"allowedChannelIds": ["222222222222222222"],
"allowedUserIds": []
```

### Approval flow

Leave all three lists as empty arrays to enable the database-backed approval flow. The first message from an unknown user creates a pending entry:

```http
GET  /v1/channel-approvals/pending
POST /v1/channel-approvals/{id}/approve
POST /v1/channel-approvals/{id}/reject
POST /v1/channel-approvals/{id}/block
```

## 7. Full config reference

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `botToken` | string | yes | Bot token from the Discord Developer Portal |
| `channelDiscordChannelMap` | object | yes | Maps Sloppy channel ID → Discord channel ID |
| `allowedGuildIds` | array of string | no | When non-empty, only these guild IDs are allowed |
| `allowedChannelIds` | array of string | no | When non-empty, only these channel IDs are allowed |
| `allowedUserIds` | array of string | no | When non-empty, only these user IDs are allowed |

## 8. Verify the connection

Restart Sloppy. The bot will connect to the Discord Gateway and register slash commands automatically on the `READY` event. This may take a few minutes for global commands to propagate in Discord.

In the mapped Discord channel, run:

```
/status
```

You should receive:

```
Plugin is running. Messages are forwarded to Sloppy.
```

Check the Sloppy logs (`sloppy.plugin.discord`) for errors. Common issues:

- Invalid `botToken` — verify the token in the Developer Portal and regenerate if needed.
- `MESSAGE_CONTENT` intent not enabled — the bot will connect but cannot read message text; enable the intent in the Developer Portal.
- No binding for the channel — the log will show `No Discord channel mapping for channelId=...`. Add the Discord channel ID to `channelDiscordChannelMap`.
- Missing bot permissions — ensure the bot has `Send Messages` and `Read Messages` in the target channel.

## Slash commands

Slash commands are registered globally when the bot connects. They are available in all servers and channels the bot is in.

| Command | Description |
| --- | --- |
| `/help` | Show available commands |
| `/status` | Check plugin connectivity |
| `/new` | Start a new session with the agent |
| `/whoami` | Show channel, user, and platform info |
| `/task <description>` | Create a task via Sloppy |
| `/model [model_id]` | Show or switch the channel model |
| `/context` | Show token usage and context info |
| `/abort` | Abort current agent processing |
| `/create-skill <description>` | Create a new agent skill |
| `/create-subagent <description>` | Create a subagent |
| `/fork <task>` | Fork an operation to a subagent |

Regular text messages (non-slash-command) posted in a mapped channel are forwarded to Sloppy as conversation messages.
