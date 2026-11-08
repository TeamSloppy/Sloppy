# Swift and supported hosts

SwiftPM declares Swift 6.2. Use the repository toolchain/CI configuration for each target;
do not infer compatibility solely from an installed compiler. `AGENTS.md` has commands
and the detailed module map. Prefer actor isolation, async orchestration, explicit `Sendable`
at concurrency boundaries and narrow recoverable errors; avoid shared mutable globals.

| Surface | Validation boundary |
| --- | --- |
| Core/runtime | Linux/macOS release products and Swift Testing suites; Windows has its own build/runtime CI |
| SloppyNode | Shared `NodeCore`, protocol tests, native computer-control behavior and platform conditionals |
| Dashboard | Node, TypeScript and Vite; browser happy-path validation requires the Core service and Chromium |
| Apple client | macOS/Xcode; SwiftPM tests plus actual target build/run when iOS or other Apple behavior changes |
| Native SwiftUI client | `ClientNative/` requires macOS 26/Xcode; shared protocols/control/migration packages also select this downstream lane |
| Local packages | Owned source in `Packages/`, including `SloppyComputerControl` and `TauTUI` |
| Vendor | Third-party/submodule source; preserve licenses and avoid treating it as owned lint scope |

Windows cannot establish AppKit, Metal or iOS behavior; compiling on macOS cannot establish
Windows service/computer-control behavior. Use `#if` boundaries already present in the
owning module. Do not invent Android/WASM support because the upstream engine supports it.

SwiftLint analyzer rules require real compiler invocation evidence. Incremental builds
may omit it: use an appropriate task-owned scratch path when analysis requires recompilation;
never delete the shared `.build` just to obtain a compiler log.

The legacy `ci.yml` currently disables its `swift-test` and `swift-test-macos` jobs.
The new contributor workflow declares its own selected Swift-test jobs. A YAML declaration
is not proof of a hosted pass. Apple-client feature checks still need relevant simulator/device
or AdaMCP evidence when runtime UI behavior is material.
