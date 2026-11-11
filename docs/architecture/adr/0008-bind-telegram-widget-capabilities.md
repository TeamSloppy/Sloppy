# Bind Telegram widgets to source-session capabilities

Status: Accepted for first-stage implementation, 2026-11-11.

## Context

Bot API 10.4 introduces immutable HTML widgets with mutable data and queries.
Production only permits private chats. Existing catch-all delivery uses a last-active
chat, which cannot safely identify the origin of a delayed interaction.

## Decision

Expose dedicated `telegram.widget.send` and `telegram.widget.update` tools through
an optional typed PluginSDK gateway capability. The model supplies no recipient.
Bind an opaque server-generated handle to the channel journal generation, user,
Telegram chat and message. Reject catch-all destinations, foreign private users,
unregistered action tokens, wallet/signature/transaction variants and stale handles.
Validate HTML UTF-8 size and zlib level-9 size independently. Require a plain caption.

Acknowledge query receipt before access checks or model work, with a bounded HTTP
request. Receipt is not authorization or successful execution. Recheck channel access
and source session before delivery. Send symbolic untrusted events through the normal
model tool authorization pipeline, not slash-command, plan-answer or approval parsing.
Edit only data on the recorded message: HTML and action permissions remain immutable.

Ownership is intentionally volatile: restarting/stopping the gateway invalidates all
handles. Handles also expire after 24 hours and the bounded registry may evict old
entries. Old widgets remain visible but cannot trigger new actions. Users must request
a fresh widget. This trades seamless recovery for fail-closed restart behavior.

## Consequences

No new widget persistence migration is required. Groups get caption text; an exact
unsupported-method Telegram response may fall back to text. Authentication/network
failures must remain errors, never silent text fallback. Unsupported clients receive
the caption from Telegram. Widgets are not full browser artifacts: no network, text
input, keyboard or external resources. Never put secrets in HTML/state.

Shared/inline widgets, TON, wallet signing and payments are deliberately out of scope.
Actual rendering and live request delivery require a compatible Telegram client and
bot credentials; mocked transport tests cannot establish that behavior.

Reference: https://core.telegram.org/bots/widgets.md
