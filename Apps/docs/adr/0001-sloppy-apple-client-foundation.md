# ADR 0001: Sloppy Apple Client Foundation

- Status: Accepted
- Date: 2026-03-24

## Context

We want a native macOS/iOS client for Sloppy that mirrors the product surface of the current dashboard in `Dashboard/src`, while also giving us a practical way to patch and debug AdaEngine when the UI stack exposes engine bugs.

The original planning draft used `Clients/SloppyApple`, but the repository direction is now:
- product app code lives under `Apps/Client`
- design and execution docs live under `Apps/docs`
- the Apple client is maintained as a separate workspace from the root server package
- the app is already structured into core, UI, and feature modules inside `Apps/Client/Sources`

## Decision

- The Apple client lives at `Apps/Client`.
- Architecture and execution planning documents will live at `Apps/docs/adr` and `Apps/docs/tasks`.
- The product scope for v1 is an internal-first Apple client built on AdaEngine + AdaUI.
- The app will mirror the dashboard information architecture:
  - root navigation for `Overview`, `Projects`, `Agents`, `Tasks`, `Review`
  - nested tabs inside project and agent detail screens
- The app is maintained as its own package and project-generation flow, separate from the root `Package.swift` products.

## Consequences

Positive:
- `Apps/Client` is clearer and product-oriented than `Clients/SloppyApple`.
- Docs and execution artifacts sit next to the future app rather than near backend targets.
- Package boundaries and generated Apple targets are explicit and reproducible.

Negative:
- The client still trails the web dashboard in feature completeness.
- Apple-specific build, signing, and release concerns remain a separate maintenance track from the server runtime.

## Implementation Notes

- All new execution work should reference `Apps/Client` as the target path.
- Human-readable implementation status should be maintained in `Apps/docs/current-state.md`.
- ADRs should capture durable architecture decisions; task JSON should capture execution status and remaining roadmap.
