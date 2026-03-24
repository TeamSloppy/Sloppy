# SloppyClient

Native macOS/iOS client for Sloppy. Built on AdaEngine + AdaUI.

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

## Coexistence with Sources/App

The root package at the repo root contains a `Sources/App` placeholder executable (`App` product). It remains untouched as a compatibility shim for the root SwiftPM graph and CI. `Apps/Client` is the real Apple client workspace and is built independently.

`Sources/App` will be retired in a future task once `Apps/Client` has a real executable, schemes, and CI wiring wired up.

## Structure

```
Apps/Client/
  Package.swift          # Standalone SwiftPM package (SloppyClient)
  project.yml            # XcodeGen spec for .xcodeproj generation
  Sources/
    SloppyClient/        # App entry point and product screens
```

## Notes

- AdaEngine is vendored as a git submodule at `Vendor/AdaEngine` (see ADR 0002).
- Requires macOS 15.0+ (driven by AdaEngine's minimum platform requirement).
- Push notification entitlements are already stubbed in `project.yml` per ADR 0005.

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

Ownership rules for changes: see [ADR 0002](../Apps/docs/adr/0002-adaengine-fork-and-submodule.md).
