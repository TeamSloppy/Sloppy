# ADR 0002: AdaEngine Fork and Submodule Strategy

- Status: Accepted
- Date: 2026-03-24

## Context

The Apple client depends on AdaEngine and AdaUI, and part of the goal is to be able to fix engine bugs quickly when they block product work. A pure package URL dependency is not enough for fast iteration, and a loose local path dependency is not a reliable source of truth for a team or CI.

## Decision

- Maintain a dedicated fork, expected shape: `SloppyTeam/AdaEngine`.
- Vendor that fork into this repository as a git submodule at `Vendor/AdaEngine`.
- Pin the submodule to explicit commits.
- Use app-local code for product-specific widgets and flows.
- Patch the engine fork only for generic primitives, engine bugs, and AdaUI gaps that are reusable.

## Boundaries

Keep in `Vendor/AdaEngine`:
- focus and input handling fixes
- generic AdaUI controls needed by multiple product surfaces
- scroll and hit-testing fixes
- text layout and rendering fixes
- packaging/build fixes needed for Apple targets

Keep in `Apps/Client`:
- Sloppy-specific screens
- route enums and screen composition
- diff/review rendering logic
- backend DTO adaptation
- product themes and icons

## Consequences

Positive:
- Fast hotfix loop when AdaEngine blocks product work
- Reproducible CI and onboarding
- Clean path to upstream reusable changes later

Negative:
- Requires submodule discipline
- Some features will span two repos logically, even if developed together

## Operational Rules

- Every app task that touches AdaEngine must identify whether the change belongs in:
  - app layer only
  - engine fork only
  - both
- Generic engine fixes should be written so they can be upstreamed later without Sloppy-specific assumptions.
