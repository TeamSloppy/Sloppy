# SloppyClient

Native macOS/iOS client for Sloppy. Built on AdaEngine + AdaUI.

Current status: internal-first Apple client workspace with connection setup, local server discovery, deep-link connection, chat, websocket-backed notifications, and settings/config editing foundations.

## Build

```bash
cd Apps/Client
swift build
```

## Generate Xcode project

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
cd Apps/Client
xcodegen generate
open SloppyClient.xcodeproj
```

## Workspace Notes

`Apps/Client` is the canonical Apple client workspace. It is built independently from the root server package and has its own package boundaries plus generated Xcode project flow.

## Structure

```
Apps/Client/
  Package.swift          # Standalone SwiftPM package (SloppyClient)
  project.yml            # XcodeGen spec for .xcodeproj generation
  Sources/
    SloppyClient/        # App entry point and product screens
```

## Current Feature Status

Implemented now:

- splash and connection setup flow
- saved server retry and local network discovery
- manual host/port connection
- `sloppy://connect` deep-link handling
- chat UI with session streaming
- notification socket integration and in-app banners
- settings and server config editing surfaces

Still on the roadmap:

- review and diff flows
- APNs device registration and push delivery
- release/distribution hardening

## Notes

- AdaEngine is vendored as a git submodule at `Vendor/AdaEngine` (see ADR 0002).
- Requires macOS 15.0+ (driven by AdaEngine's minimum platform requirement).
- Push notification entitlements are already stubbed in `project.yml` per ADR 0005.
- More implementation status is tracked in [Apps/docs/current-state.md](../docs/current-state.md).

## Updating the pinned engine revision

The submodule is pinned to a specific commit. To update it:

```bash
cd Vendor/AdaEngine
git fetch origin
git checkout <target-commit-or-tag>
cd ../..
git add Vendor/AdaEngine
git commit -m "chore: bump AdaEngine to <commit>"
```

To initialize the submodule after a fresh clone:

```bash
git submodule update --init --recursive
```

Ownership rules for changes: see [ADR 0002](../docs/adr/0002-adaengine-fork-and-submodule.md).
