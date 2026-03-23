# ADR 0001: Sloppy Apple Client Foundation

- Status: Accepted
- Date: 2026-03-24

## Context

We want a native macOS/iOS client for Sloppy that mirrors the product surface of the current dashboard in `Dashboard/src`, while also giving us a practical way to patch and debug AdaEngine when the UI stack exposes engine bugs.

The original planning draft used `Clients/SloppyApple`, but the repository direction is now:
- product app code lives under `Apps/Client`
- design and execution docs live under `Apps/docs`

The repository still contains `Sources/App/AppMain.swift`, but it is only a placeholder executable currently used by the root SwiftPM package.

## Decision

- The future Apple client will live at `Apps/Client`.
- Architecture and execution planning documents will live at `Apps/docs/adr` and `Apps/docs/tasks`.
- The product scope for v1 is an internal-first macOS/iOS client built on AdaEngine + AdaUI.
- The app will mirror the dashboard information architecture:
  - root navigation for `Overview`, `Projects`, `Agents`, `Tasks`, `Review`
  - nested tabs inside project and agent detail screens
- `Sources/App` will not be removed yet. It stays as a compatibility placeholder until `Apps/Client` has a real executable, schemes, and CI wiring.

## Consequences

Positive:
- `Apps/Client` is clearer and product-oriented than `Clients/SloppyApple`.
- Docs and execution artifacts sit next to the future app rather than near backend targets.
- We avoid breaking the current `App` product and CI while the new client is still in planning and scaffold phases.

Negative:
- The repo will temporarily contain two app concepts:
  - placeholder `Sources/App`
  - planned real client in `Apps/Client`
- A later cleanup ADR or task will be required to retire `Sources/App`.

## Implementation Notes

- All new execution work should reference `Apps/Client` as the target path.
- Any task that changes the root `Package.swift` executable graph must explicitly account for the current `App` product.
