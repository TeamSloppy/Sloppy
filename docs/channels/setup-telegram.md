---
layout: doc
title: Setup Telegram
---

# Setup Telegram

This guide walks through connecting a Telegram bot to a Sloppy channel.

## Prerequisites

- A running Sloppy instance with a valid `sloppy.json`.
- A Telegram account.

## 1. Create a Telegram bot

Open Telegram and start a conversation with [@BotFather](https://t.me/BotFather).

```
/newbot
```

Follow the prompts to set a name and username for your bot. BotFather will reply with a **bot token** in the format `123456789:ABCdef...`. Save it — you will need it in the next step.

## 2. Add the Telegram config to sloppy.json

Add a `channels.telegram` section to your `sloppy.json`:

```json
{
  "channels": {
    "telegram": {
      "botToken": "123456789:ABCdefGHIjklMNOpqrSTUvwxYZ",
      "channelChatMap": {
        "main": 0
      },
      "allowedUserIds": [],
      "allowedChatIds": []
    }
  }
}
```

Using `0` as the `chat_id` value creates a **catch-all binding** that accepts messages from any chat. This is the easiest starting point. See [Bindings](#bindings) below for a fixed-chat setup.

## 3. Find your chat ID

Start your bot in Telegram and send it any message. Then check:

```
https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates
```

Look for the `"chat"` object in the response:

```json
{
  "message": {
    "chat": {
      "id": -1001234567890,
      "type": "supergroup",
      "title": "My Team"
    }
  }
}
```

Alternatively, after starting Sloppy with a catch-all binding, send `/whoami` to the bot and it will report the channel ID, user ID, and platform.

## 4. Bindings

The `channelChatMap` maps Sloppy channel IDs to Telegram chat IDs.

| Value | Effect |
| --- | --- |
| A specific `chat_id` | Messages are only routed from and to that chat |
| `0` | Catch-all: accepts any chat; replies go to the last active chat |

Example with multiple bindings:

```json
"channelChatMap": {
  "main": -1001234567890,
  "support": 987654321
}
```

Multiple bindings can point to different Telegram chats. Each Sloppy channel maintains its own conversation history and model settings.

### Catch-all binding

When `chat_id` is `0`, any Telegram chat that messages the bot is routed to that channel. The plugin tracks the most recent active chat ID and uses it for outbound delivery. This means only one chat is active at a time under a catch-all binding.

## 5. Access control

### Static allowlists

Set `allowedUserIds` to restrict access to specific Telegram user IDs:

```json
"allowedUserIds": [123456789, 987654321]
```

Set `allowedChatIds` to restrict to specific chats (private, group, supergroup):

```json
"allowedChatIds": [-1001234567890]
```

When either list is non-empty, messages from IDs not in the list are rejected immediately and the user receives an explanation.

### Approval flow

Leave both `allowedUserIds` and `allowedChatIds` as empty arrays to enable the approval flow. The first message from an unknown user creates a pending-approval request that an administrator can approve or reject:

```http
GET  /v1/channel-approvals/pending
POST /v1/channel-approvals/{id}/approve
POST /v1/channel-approvals/{id}/reject
POST /v1/channel-approvals/{id}/block
```

## 6. Full config reference

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `botToken` | string | yes | Bot API token from BotFather |
| `channelChatMap` | object | yes | Maps Sloppy channel ID → Telegram chat_id |
| `allowedUserIds` | array of int | no | When non-empty, only these user IDs are allowed |
| `allowedChatIds` | array of int | no | When non-empty, only these chat IDs are allowed |

## 7. Verify the connection

Restart Sloppy, then send `/status` to your bot in Telegram. You should receive:

```
Plugin is running. Messages are forwarded to Sloppy.
```

If the bot does not respond, check the Sloppy logs for errors from `sloppy.plugin.telegram`. Common issues:

- Invalid `botToken` — double-check the value from BotFather.
- No matching binding — the log will show `No channel mapping for chatId=...`. Add the chat ID to `channelChatMap` or use a catch-all binding (`0`).
- Network issue — ensure the machine running Sloppy can reach `api.telegram.org`.

## Bot commands

Once connected, the following slash commands are available in the Telegram chat:

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

Any other text is forwarded to the linked Sloppy channel as a regular message.
