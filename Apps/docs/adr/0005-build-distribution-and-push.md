# ADR 0005: Build, Distribution, and Push Notifications

- Status: Accepted
- Date: 2026-03-24

## Context

The app must be an SPM-based project, but it also needs an `.xcodeproj` so iOS builds, signing, entitlements, and simulator/device workflows are predictable. The app also needs Apple push notifications, which are not present in Sloppy today.

## Decision

- Source code organization is package-first.
- Xcode project generation is project-tool driven, not hand-maintained.
- Preferred shape:
  - Swift packages under `Apps/Client`
  - generated `SloppyClient.xcodeproj` for Apple app targets, schemes, and entitlements
- Do not depend on AdaEngine's unfinished `Product.iOSApplication` path for the product app.
- Release mode for v1 is internal-first:
  - local development
  - simulator/device builds
  - TestFlight when ready

## Implemented Now

- `Apps/Client` is package-first and builds independently from the root server package.
- `project.yml` defines generated Apple app targets, deployment targets, and entitlements for macOS, iOS, iPadOS, and visionOS.
- `SloppyClient.xcodeproj` is generated from repo state rather than hand-maintained.

## Roadmap / Not Yet Implemented

## Push Model

Add a backend push pipeline to Sloppy with:
- device registration endpoint
- APNs token storage
- per-device notification preferences
- APNs sender
- deep-link payload routing into app screens

Initial push categories:
- pending approval
- task assigned or mentioned
- agent error
- task completed

This section remains roadmap work. The client already has websocket-backed in-app notifications, but APNs device registration, backend token storage, and push delivery are not complete yet.

## Consequences

Positive:
- Reliable Apple build workflow
- Clear separation between package code and signing/distribution concerns
- Push notifications become a first-class backend capability instead of an app-only hack

Negative:
- Requires new backend APIs and storage
- Adds Apple certificate/key operational work

## Deferred Work

- App Store-hardening
- public internet exposure through Cloudflare Tunnel
- advanced push categories and notification content extensions
