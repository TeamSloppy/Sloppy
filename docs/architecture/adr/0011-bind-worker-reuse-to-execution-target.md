# ADR 0011: Bind worker reuse to an explicit execution target

- Status: accepted for the bounded contract implementation; remote execution remains unsupported
- Date: 2026-11-17

The [distributed task execution design](../../specs/distributed-task-execution.md) extends this contract to chat mentions, Kanban assignment, shared code snapshots, model routing and verification on multiple machines. The design is proposed.

## Context

Delegation must distinguish machine, agent and model. Existing Long Chat assignments and worker contexts survive restart; adding a remote schema without binding that context could silently run a continuation locally or move it after an alias remap. Earlier unverified implementation attempts left a Mesh dispatcher in the working tree. Compilation alone did not establish its workspace isolation, receiving-policy intersection, cancellation or restart safety.

## Decision

Extend LongChatTaskRequest, LongChatTask and durable WorkerContext with optional executionTarget. Absent fields retain legacy local behavior. A remote selection contains targetId, immutable baseRevision, explicit agentId, optional selectedModel and server-resolved nodeId. Resolve an exact operator alias or ID from the Core workspace's remote-execution-targets.json into a stable Mesh identity. Never interpret aliases as environment variables or infer intent from language fragments. Reject ambiguous registries, project/agent/peer mismatches, offline/missing nodes, missing advertised capabilities and changed pinned identities.

Reuse preserves target/node/base/agent, project, resource scope and readOnly; existing tool allowlists may only narrow. A model choice is independent of location. An ordinary continuation with a saved remote target must not become local work.

Ship this as a fail-closed contract slice, not as a remote executor. New remote delegations fail before reservation with remote_execution_unsupported after target preflight. The existing Mesh subagent namespace returns the same unsupported error; no task starts and no transcript or credentials are transferred. Persisted experimental remote requests retain their locks and require operator reconciliation instead of being retried locally. There is no enable flag that bypasses this boundary.

## Consequences

Legacy local execution continues through the existing Long Chat scheduler. The stable target can be serialized and tested without inventing another task manager. A configured alias is not a promise that remote execution is available. Tool status exposes remoteExecutionSupported=false.

The earlier experimental dispatcher is archived in workspace-private verification artifacts rather than enabled. It cannot be restored merely by deleting the unsupported check: receiving policy and operation approvals, task-workspace isolation, bounded output collection, durable idempotent session operations and two-Core transport acceptance tests are prerequisites. See the [implementation handoff](../../guides/remote-subagents-handoff.md).

NodeMeshWorker already present in this checkout creates detached worktrees from a resolved base, defaults commitChanges/push to false and returns a binary patch including new files. This is a helper, not an integration or sandbox. Runtime shell commands remain trusted code under the OS user, and arbitrary commands can themselves invoke Git. Do not claim that worktree isolation enforces no-commit/no-secret access for a remote agent.

## Verification

RemoteExecutionContractTests covers legacy request decoding, target/context persistence, exact alias resolution, stable identity checks, missing/offline/capability/project/peer/agent failures, immutable base syntax, reuse scope, actual tool-boundary unsupported rejection, Mesh refusal and persisted remote dispatch without local fallback. Existing local Long Chat and reuse suites remain part of the focused run. NodeMeshWorkerTests separately verifies detached pinned base, preservation of an existing task branch, no implicit commit, new-file diff and no-diff success. No two-Core remote execution or physical-host validation is claimed.

## Addendum — 2026-11-17 receiving-executor safety probe

The follow-up fixes bounded concurrent output capture and sanitizes environment for NodeMeshWorker/GitPolicy helper subprocesses, but does not enable receiving remote execution. Disposable canary tests prove that clean ENV+CWD permits out-of-root reads and detached worktrees permit shared source-repository config mutation. Ordinary Core exec roots are not syscall isolation, and ordinary runtime environment inheritance remains unchanged. A tested OS execution adapter plus private/brokered Git metadata and durable process ownership are prerequisites; a shell denylist is not a substitute. `sandbox-exec` can launch a minimal process here; a suitable toolchain profile is not implemented/tested, so isolation is not declared impossible. Docker daemon is unavailable. See the dated handoff addendum for 58 passing tests/8 suites, build evidence and remaining lifecycle requirements. The no-local-fallback/unsupported decision is unchanged.

## Addendum — 2026-11-17 experimental macOS profile

An internal `MacOSReceivingIsolation` prototype now demonstrates deny-default Seatbelt with task-only writes, system/explicit-Xcode read-only paths, clean task-local environment and independent pinned Git metadata. Finite real canaries and Apple clang 21 C build/network-EPERM smoke pass (26 focused tests/4 suites). Global metadata/existence observation and literal root-directory read for libignition are explicit exceptions, not recursive host reads. Profile imports and network grants are absent. POSIX realpath was required for canonical `/private/var` matching. This is private macOS sandbox policy behavior, not a portable supported API.

The production unsupported decision remains: this prototype has no cancellation/descendant lifetime guarantees, race-safe file broker, verified immutable toolchain install or hardened/durable private Git preparation, and does not wrap existing Core file tools. It must not be exposed to arbitrary remote objectives. See the dated handoff for precise boundaries, failed-run evidence and remaining integration work.

### Same-assignment resume: validated prototype roots

Writable profile roots are now limited to same-UID private directories strictly below the canonical user temporary tree, and Workspace revalidates captured device/inode before launch. Explicit Xcode Developer grants must exist and equal their realpath. Supplied HOME no longer triggers host-side directory creation/chmod during command launch. RED/GREEN regressions demonstrate broad-root/replaced-root/missing-toolchain rejection; 62 expanded tests/9 suites and both debug builds pass. These are between-command validation defenses, not a claim of race-free isolation or complete cancellation. Production unsupported status remains unchanged; no scope or permission expansion.

### TOCTOU characterization: open defect, no atomicity claim

A deterministic validation/use-seam test demonstrates that replacing a validated root with a different real directory before sandbox-exec launches exposes the replacement's contents. Symlink replacement is denied on the tested host. Captured device/inode validation and textual profile grants do not bind to the same vnode. Descriptor cwd alone is insufficient while Seatbelt authorizes a separately resolved path. This iteration records the open defect, does not implement a race-free launch mechanism, and does not prove unavailable OS permissions. Production remains unsupported. See dated handoff for 63 passing characterization/regression tests (10 suites) and both debug builds; those are not acceptance of isolation under concurrent substitution.
