# Sloppy Apple Client ADRs

These ADRs define the target architecture for the future Apple client at `Apps/Client`.

Current status:
- `Apps/Client` is the target app location for the new AdaEngine/AdaUI client.
- `Sources/App` remains in place temporarily because it is still wired into the root `Package.swift` product graph and CI.
- Once `Apps/Client` owns the real app executable and build flow, `Sources/App` can be removed in a dedicated cleanup change.

ADR list:
- `0001-sloppy-apple-client-foundation.md`
- `0002-adaengine-fork-and-submodule.md`
- `0003-networking-remote-access-and-auth.md`
- `0004-adaui-product-shell-and-feature-mapping.md`
- `0005-build-distribution-and-push.md`
