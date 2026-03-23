# ADR 0003: Networking, Remote Access, and Authentication

- Status: Accepted
- Date: 2026-03-24

## Context

Sloppy already serves HTTP and WebSocket routes from the backend using SwiftNIO. The dashboard uses REST plus WebSockets for live agent sessions and notifications. The Apple client needs the same transport model, plus a remote access story that works outside the local network.

## Decision

- Keep the backend transport on the existing Sloppy server stack.
- On the Apple client, use `Foundation` networking:
  - `URLSession` for REST
  - `URLSessionWebSocketTask` for WebSocket streams
- Do not use `FoundationNetworking` on Apple platforms.
- Do not introduce client-side `SwiftNIO` for v1.
- Remote access v1 is `Tailscale first`.
- Cloudflare Tunnel is explicitly deferred to a later phase after external auth hardening exists.
- Add mobile-focused bearer-token auth for both REST and WebSocket handshakes before remote rollout.

## WebSocket Model

The client will maintain:
- one long-lived notifications socket for `/v1/notifications/ws`
- one active chat/session socket for `/v1/agents/:agentId/sessions/:sessionId/ws`

Socket rules:
- initial load comes from REST
- WS delivers incremental updates
- reconnect with backoff
- after reconnect, resync state via REST before trusting fresh stream events

## Consequences

Positive:
- Apple-native lifecycle integration
- Lower complexity than introducing a second networking stack on the client
- Safer remote story for an internal-first release

Negative:
- Tailscale adds an operational requirement for internal testers
- Cloudflare convenience is intentionally delayed

## Follow-up Requirements

- Add bearer-token validation for REST and WS in Sloppy
- Add onboarding/config UI for base URL + token
- Store tokens in Keychain on Apple platforms
