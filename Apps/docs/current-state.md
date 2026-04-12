# Sloppy Apple Client Current State

This document is the main status entry point for the Apple client in `Apps/Client`.

## Workspace Shape

The client is maintained as a separate Swift package and XcodeGen workspace:

- `Apps/Client/Package.swift`
- `Apps/Client/project.yml`
- `Apps/Client/SloppyClient.xcodeproj`

Current source modules:

- `SloppyClient` - app entry point and shell flow
- `SloppyClientCore` - routing, settings, API client, websocket managers, deep links, models
- `SloppyClientUI` - reusable visual components and theme primitives
- `SloppyFeatureOverview`
- `SloppyFeatureProjects`
- `SloppyFeatureAgents`
- `SloppyFeatureChat`
- `SloppyFeatureSettings`

## Working Today

- Splash flow that attempts saved-server reconnect, then local network discovery, then falls back to manual setup
- Manual server connection using host and port entry
- Local network server discovery
- Deep-link connection flow via `sloppy://connect?...`
- Root app shell with navigation state and route scaffolding
- Agent chat UI with session selection and message sending
- Websocket-backed session streaming and reconnect signaling
- Websocket-backed in-app notifications rendered as banner UI
- Settings screen with client-side preferences and server config fetch/save flow

## Implementation Notes

- The app is internal-first and built separately from the root `sloppy` server package.
- The current runtime integration path is HTTP plus WebSocket against a running Sloppy server.
- The app includes AdaMCP plugin wiring for live runtime inspection in supported environments.

## In Progress

- Broader polish and completion across overview, projects, and agents surfaces
- Hardening of reconnect, error handling, and cross-platform UX details
- Keeping task docs aligned with the implementation as the client evolves

## Still On The Roadmap

- Review and unified diff surfaces
- Review comments workflows
- APNs device registration and push delivery
- Deep-link routing from push payloads
- Internal release hardening and distribution guidance beyond the current generated project flow

## Related Docs

- [`adr/README.md`](adr/README.md)
- [`adr/0001-sloppy-apple-client-foundation.md`](adr/0001-sloppy-apple-client-foundation.md)
- [`adr/0004-adaui-product-shell-and-feature-mapping.md`](adr/0004-adaui-product-shell-and-feature-mapping.md)
- [`adr/0005-build-distribution-and-push.md`](adr/0005-build-distribution-and-push.md)
- [`../Client/README.md`](../Client/README.md)
