# Remote subagents: bounded implementation handoff

Date: 2026-11-17. Checkout: `/Users/vlad-prusakov/Developer/Sloppy`.

**This is not the `$home_machine` MVP. Remote execution is intentionally unsupported in this build.** The slice establishes a backward-compatible target contract and prevents unsafe local fallback. No running user Core was restarted, deployed, committed or pushed. No external host was contacted.

## What is available

`long_chat.delegate` accepts optional `tasks[].executionTarget`:

```json
{
  "targetId": "$home_machine",
  "baseRevision": "0123456789012345678901234567890123456789",
  "agentId": "builder",
  "selectedModel": "optional-provider:model"
}
```

The model field may be omitted. The alias is exact Sloppy registry data, not shell/ENV substitution. Server resolution returns the canonical target ID and pins nodeId. Project, permitted coordinator peer ID, permitted agent ID, Mesh node availability and advertised capabilities are checked. A full Git object ID is syntactically required; existence/toolchain execution is not proved by this preflight.

For future configuration/testing only, the operator-owned registry is `<Core workspace>/remote-execution-targets.json`:

```json
[{
  "id": "home",
  "alias": "$home_machine",
  "nodeId": "stable-paired-mesh-node-id",
  "projectId": "my-project",
  "sharedProjectId": "shared-repo-mapping-id",
  "allowedPeerIds": ["coordinator-mesh-node-id"],
  "allowedAgentIds": ["builder"],
  "toolIDs": ["files.read", "agent_delegate.finish"],
  "requiredCapabilities": ["swift"],
  "maxConcurrentTasks": 1
}]
```

Do not put credentials here. No UI editor or remote setup wizard is shipped. This registry is operator configuration, not a new security sandbox: future execution must prevent project/agent tools from modifying it. An `online` catalog record is preliminary discovery, not a completed authenticated live executor preflight.

`long_chat.status` reports `remoteExecutionSupported: false`. A known online authorized target still receives `remote_execution_unsupported` before assignment/session creation. Unknown/offline/unauthorized targets return an explicit target error; do not remove the target and retry locally. Incoming `subagent.*` Mesh operations also fail closed. Local requests with no executionTarget retain the existing behavior.

The optional target survives assignment and worker-context persistence. Reuse cannot change target, pinned node, base, agent, project/resource keys or widen readOnly. Existing saved tool policies remain the upper bound. Changing a model does not choose another machine. Legacy contexts decode with a nil/local target.

## Restored state and changed files

Previous attempts had already left NodeMeshWorker safety edits, optional protocol fields, a Long Chat transport binding and a large unverified Core dispatcher. The pre-iteration tracked diff/status and the previous untracked dispatcher were saved under `.sloppy/verification/remote-subagent-slice/`. Other dirty changes (CodeMode, Console, client/auth/session/TUI work) were not reset.

Relevant implementation files (including retained work from earlier attempts):

- `Sources/Protocols/LongChatModels.swift`, `RemoteExecutionModels.swift`: optional request/task/attempt fields, explicit target selection/registry records. Some remote result/start DTOs remain reserved, not a supported wire protocol.
- `Sources/sloppy/LongChat/LongChatFileStore.swift`: assignment and WorkerContext target persistence; optional experimental binding archive.
- `Sources/sloppy/LongChat/RemoteExecutionRegistry.swift`: exact alias resolution/preflight and immutable reuse boundary.
- `Sources/sloppy/LongChat/RemoteWorkerBinding.swift`: retained binding shape and typed errors.
- `Sources/sloppy/CoreService+RemoteSubagents.swift`: registry loading, validation and explicit unsupported transport/dispatcher boundaries. The unverified executor was replaced with refusal, not certified.
- `Sources/sloppy/CoreService+LongChat.swift`: validation before reservation, status metadata, explicit tool errors and handling of old remote attempts.
- `Sources/sloppy/CoreService+LongChatWorkers.swift`, `CoreService+SubagentReuse.swift`: no local fallthrough; saved target/reuse boundary.
- `Sources/sloppy/CoreService+NodeMesh.swift`: reserved subagent RPC route through the existing Mesh handler; no second transport.
- `Sources/sloppy/Tools/AgentTools/Agents/LongChatTool.swift`: typed optional schema explicitly marked unsupported.
- `Sources/NodeCore/NodeMeshWorker.swift`: retained earlier detached/pinned worktree, optional commit and diff helper. No new production caller executes remote tasks.
- `Tests/sloppyTests/RemoteExecutionContractTests.swift`: 12 contract/service tests added in this iteration.
- `Tests/SloppyNodeCoreTests/NodeMeshWorkerTests.swift`: 6 tests total, including two additional pinned-branch/unsafe-option regressions.
- [ADR 0011](../architecture/adr/0011-bind-worker-reuse-to-execution-target.md).

## Verification actually performed

From this checkout, scratch build directory `/tmp/sloppy-remote-worker-test-build`:

```sh
swift test --scratch-path /tmp/sloppy-remote-worker-test-build --filter 'RemoteExecutionContractTests|LongChatTests|LongChatOptionalIDTests|NodeMeshWorkerTests|SubagentReuseTests'
swift build --scratch-path /tmp/sloppy-remote-worker-test-build --product sloppy
swift build --scratch-path /tmp/sloppy-remote-worker-test-build --product SloppyNode
```

Final focused run: **49 Swift Testing tests in 6 suites passed**, 5.185 seconds execution (build time separate). XCTest's earlier `0 tests` line is not the result. Debug builds of both products passed. Two earlier test compilations failed due to missing public registry initializer and an actor-isolation mistake in the new tests; both were corrected and the final run passed.

Evidence: `.sloppy/verification/remote-subagent-slice/focused-tests.log`, `build-sloppy.log`, `build-node.log`. Tool evidence IDs: verification-6 (final focused tests), verification-5 (sloppy debug build), verification-3 (SloppyNode debug build). Full suite, release/Linux builds and two-Core E2E were not run in this bounded recovery slice. Existing SwiftPM dependency identity conflicts (eventsource/swift-syntax), Sendable/deprecation warnings, and zlib macOS deployment-target warning remain outside scope.

No runnable remote feature is delivered, so no remote Play target is registered. Launching the existing user Core to demonstrate a schema would be misleading. The commands above reproduce the contract checks without starting a service. A verified isolated two-Core launch recipe is a follow-up prerequisite, not an available remote demo.

## Concrete remaining steps before enabling remote execution

1. **Immutable remote workspace:** validate authenticated shared-repository mapping and actual base existence; explicit dirty-local-input choice; isolated task worktree persisted with the attempt before execution. No user checkout switch/reset, no implicit commit/push/apply. Helper pipe collection currently waits before draining and needs bounded concurrent output handling for large logs/patches; this helper is not yet suitable for untrusted long builds.
2. **Receiving security boundary:** intersection of delegated tools, target ACL and remote agent policy, reapplied at each action/continuation; operation/attempt-bound approvals and explicit revocation/process policy. Narrow filesystem/exec roots instead of appending remote roots to broad local roots; strip inherited environment secrets and do not import the coordinator transcript or attachments by default. Worktree layout alone is not isolation.
3. **Durable lifecycle on existing Long Chat runtime:** peer+task+attempt+parent+remote session identity, durable exactly-once reservation/start, status/events cursor, idempotent follow-up, executor-confirmed cancellation of process descendants, results with base+diff/new files and command exit/log manifests plus artifact hashes/sizes. Preparation interruption must reconcile rather than permanently strand a half-bound start or create a duplicate.
4. **Reconnect/restart/stale protection:** immutable start payload persisted once; reconcile a start whose RPC reply was lost, reconnect without duplicate launch, reject stale attempts, bind follow-up to the same remote session and prevent retries while an old process may still run. Old experimental attempts in this slice retain uncertainty/locks; operator reconciliation is required, not an automatic stopped/success assertion.
5. **UI and setup:** minimal machine alias/permissions/mapping surfaces and existing task target/status/continue/cancel/result controls, following `docs/dashboard-style.md` with interaction/visual checks. Do not imply schema acceptance equals execution support.
6. **Acceptance and Play:** authenticated isolated two-Core loopback start/edit/build, disconnect/reconnect without relaunch, same-session follow-up and final diff; cancellation/process-descendant and secret/scope regressions, then release builds/full suite. Keep execution finished, verification passed and result applied separate. Physical-machine verification is separate from loopback and needs an authorized host.

Do not enable the archived dispatcher by simply restoring its file: it did not prove security or lifecycle guarantees and did not implement real remote reuse. Automatic scheduling/migration, arbitrary FS sync, distributed builds, automatic push/merge/apply and remote GUI remain out of scope.

## 2026-11-17 follow-up: receiving executor safety (blocked integration)

This iteration did **not** enable remote start/status/follow-up/cancel/result. The blocker is a missing enforced receiving execution boundary, not missing remote credentials. No two-Core execution, UI or Play target is claimed. The existing unsupported guard was not weakened. The following concrete prerequisite work is implemented and tested:

- New `Sources/NodeCore/NodeMeshProcess.swift` collects stdout/stderr concurrently on dedicated reader threads, retains at most 4 MiB raw bytes per stream, continues draining excess bytes, and records truncation. Dedicated threads matter: an initial GCD global-queue version passed 22 narrow tests but starved during a broader parallel run; that run timed out, its exact owned helper/shell were terminated, and the corrected parallel run passed. There is no silently truncated successful patch: Git output overflow throws `outputTooLarge`.
- Mesh helper shell/Git subprocesses use an exact environment, not host environment plus overrides: fixed system PATH, fresh 0700 temporary HOME/TMPDIR/XDG_CONFIG_HOME, C locale, no system/global Git config, and disabled Git credential prompts. No SSH agent socket, provider tokens, proxy/loader environment or user PATH is inherited. stdin is closed. Temporary home is removed after execution. Build tools needing custom paths/toolchain settings will require an explicit reviewed environment contract rather than automatic ENV forwarding.
- `NodeMeshWorker.swift` and `NodeMeshGitPolicy.swift` use that process runner. Helper Git calls disable hooks and fsmonitor. This does not disable arbitrary repository filters or prevent a trusted shell from explicitly calling Git/network/read operations; it is not a security guarantee against repository code. The autopilot closure is still caller-owned code and is not isolated by this helper.
- Added `Tests/SloppyNodeCoreTests/NodeMeshProcessTests.swift` (4 tests), plus 2 worker tests: large complete patches/explicit overflow and shared Git metadata canary. Existing pinned/no-commit/no-diff tests remain green.

### Proven security boundary gap

`RuntimeExecTool` validates `resolveExecCwd`, then invokes an unrestricted executable. `ToolHelpers.childProcessEnvironment` still merges the full host environment for the ordinary runtime. `CoreService+Tools` appends session roots to existing roots; it does not create a remote deny-all context. These ordinary local semantics were not globally changed because that would break unrelated local users and still would not sandbox shell arguments.

Two disposable-fixture tests demonstrate the actual blockers without reading any real credentials:

1. `cleanEnvironmentAndCwdAreNotFilesystemIsolation`: `/bin/cat` launched with an empty-of-secrets environment and a workspace CWD successfully reads a synthetic file outside that workspace. Root lists do not constrain child filesystem syscalls.
2. `detachedWorktreeStillSharesRepositoryMetadata`: `git config --local` launched inside the detached worktree mutates the source fixture repository's shared Git config. Thus merely allowing `.git` operations in a linked worktree can expose source checkout refs/config/hooks; an isolated detached CWD is not isolated Git metadata.

The machine has `/usr/bin/sandbox-exec`; a minimal `true` process under a deny-default profile runs successfully. **OS isolation is not proven impossible**, but there is no tested profile/adapter in the receiving runtime. Docker CLI exists, but `docker info` reports a missing OrbStack socket (daemon unavailable); it was not started. No unknown host/service was contacted. Do not treat either probe as a complete secure toolchain sandbox.

### Minimum prerequisite before production dispatch can be enabled

Implement a receiving execution adapter used by **every** remote file/exec/process tool entry point, not just the Mesh helper. It must own (a) an enforceable filesystem/network boundary or a dedicated disposable VM/container/OS account without host secrets, (b) task-private Git metadata or narrowly brokered Git operations so common-directory mutation cannot reach the user checkout, (c) explicit safe env/toolchain inputs, and (d) durable process ownership tied to peer/task/attempt with descendant termination and restart reconciliation. A macOS profile implementation is feasible but needs tested toolchain reads/writes and escape-denial tests, not an unreviewed allow-all file-read profile. Unsupported platforms/modes must fail closed.

The helper's pipe-capacity deadlock is fixed, but **process lifetime is not**: it has no timeout/cancellation and descendants retaining output descriptors may hold readers open. It remains trusted-command-only and is not wired into production remote dispatch. Receiving policy intersection, operation approvals, durable prepare/start idempotency, same-session follow-up, reconnect/stale-attempt reconciliation, result manifests and executor-confirmed cancellation remain unfinished. This is an implementation prerequisite, not a request for the user to expose secrets or relax permissions.

### Checks in this follow-up

Final command:

```sh
swift test --scratch-path /tmp/sloppy-remote-worker-test-build --filter 'NodeMeshProcessTests|NodeMeshWorkerTests|NodeMeshGitPolicyTests|RemoteExecutionContractTests|LongChatTests|LongChatOptionalIDTests|SubagentReuseTests'
```

**58 Swift Testing tests in 8 suites passed**, 6.031 seconds test execution, exit 0 (`verification-3` in this turn). Debug builds `sloppy` (`verification-1`) and `SloppyNode` (`verification-2`) passed after implementation. Evidence: `.sloppy/verification/remote-executor-safety/final-tests.log`, `build-sloppy.log`, `build-node.log`; the failed parallel log is retained as `regression.log` and corrected earlier run as `regression-fixed.log`. Full suite/release/Linux/physical-host and two-Core E2E were not run. Existing dependency identity/Sendable/deprecation/zlib warnings remain. No commit/push/deploy/restart of user Core, and no change to unrelated dirty work.

## 2026-11-17 follow-up: experimental macOS Seatbelt adapter

Added `Sources/NodeCore/MacOSReceivingIsolation.swift` and `Tests/SloppyNodeCoreTests/MacOSReceivingIsolationTests.swift`. This is an **internal synchronous library experiment**, not a supported receiving runtime. Remote production guard remains unchanged. Ordinary Core file tools are NOT sandboxed by this code, and it is NOT wired to Long Chat dispatch. No service/config/container was started or changed.

### Implemented boundary and actual observations

- Explicit `(deny default)` Seatbelt profile via `/usr/bin/sandbox-exec`; no profile imports, network/mach lookup grants, credential forwarding, user-home read or host writes. Read-only baseline: `/System/Library`, system Cryptex directories, `/usr/lib`, `/usr/bin`, `/bin`; optional explicit Xcode Developer root. File metadata/existence is globally observable (a deliberate traversal tradeoff), not file contents. Literal `/` is readable for dyld/libignition bootstrap, **not** recursively. `/System/Volumes/Data` is deliberately NOT a read root.
- Task root alone receives file read/write/executable mapping. Child shell/exec inherits Seatbelt. Temporary HOME/TMP/XDG config lives inside task root; host environment is still excluded using NodeMeshProcess. `.home` symlink replacement is rejected. Root must be a caller-owned fresh fixture; this is not a concurrent hostile-workspace broker and its check/use races are not closed.
- Canonical sandbox root uses POSIX `realpath`, not Foundation `resolvingSymlinksInPath`: on this host Foundation retained `/var` and legitimate writes failed against canonical `/private/var`. Initial tests failed closed for this reason and were corrected, not given broader temporary-directory grants.
- `prepare` initializes a task-private Git repository and fetches only the supplied full 40-character object ID with depth=1, then checks out detached. No linked `.git`, hardlinks/alternates, remote config, implicit commit/push/apply. Source config stays unchanged after task-private `git config`. Fetch preparation is privileged broker work and still assumes an operator-authorized trusted repository; it is NOT a hardened broker for malicious repository Git configuration or concurrent source mutation. Failed preparation leaves a partial directory for inspection; durable idempotent preparation is not implemented.
- Toolchain exception is explicit `/Applications/Xcode*.app/Contents/Developer`, read-only. It is operator-trusted, not an arbitrary model-provided readable path. This prototype validates spelling, not toolchain signature/symlink integrity; production must pin/canonicalize and verify the operator-selected install.

### Real disposable tests

The two new scenario tests prove: outside secret fixture read denied; symlink-to-secret read denied; child shell cannot read that secret; source `.git/config` write denied; task edit/private Git config allowed; pinned HEAD retained; no Git alternates; hostile `.home` symlink refused. Alternate `/System/Volumes/Data` secret path is rejected as well (not claimed as a universal firmlink audit).

Compiler smoke: **Apple clang 21.0.0 (clang-2100.1.1.101), Xcode-26.6.0.app**, explicit MacOSX SDK, compiles/links a C socket probe inside the profile and executes it. The probe requires `EPERM` from socket creation/connect to loopback; mere connection-refused/nonzero exit is not counted as network isolation. No external network request, package download, global compiler cache or dependency-resolution exception is granted. This does not validate SwiftPM/Kotlin/Gradle or remote model networking.

### Lifecycle and production blockers — still open

The adapter can start synchronous processes but provides **no timeout/cancel API, process-group ownership or descendant-reaping confirmation**. Only finite fixture commands were exercised; no cancellation guarantee is made. Descendants holding output descriptors can still prevent EOF. This alone prohibits production enabling even though finite sandbox canaries pass. Do not expose this prototype to arbitrary long-running remote objectives.

Remaining mandatory receiving work: canonical immutable operator toolchain/root contracts, race-safe filesystem broker (all remote file actions through isolated helpers, not host `FileManager`), robust private Git preparation, explicit receiving policy/approval intersection, durable process/attempt ownership, cancellation and restart reconciliation. Then implement durable start/status/events/follow-up/reuse/cancel/result and two-Core E2E. UI/setup and physical-machine verification remain later. No remote Play configuration: library prototype only.

### Verification in this iteration

- Final `swift test --scratch-path /tmp/sloppy-remote-worker-test-build --filter 'MacOSReceivingIsolationTests|NodeMeshProcessTests|NodeMeshWorkerTests|RemoteExecutionContractTests'`: **26 Swift Testing tests / 4 suites passed**, 3.360 seconds execution. Evidence `.sloppy/verification/macos-isolation/final-tests.log`.
- Debug `swift build --scratch-path /tmp/sloppy-remote-worker-test-build --product sloppy` and `--product SloppyNode`: passed, logs `build-sloppy.log`, `build-node.log` in the same evidence folder.
- Earlier failing runs retained (`tests-final.log`, `tests-second.log`, `diagnostic.log`); no failures represented as passes. One initial shell command accidentally retained a 10-second tool deadline and timed out during build; inspected output before rerunning with configured maximum. No foreign build was killed.
- Existing SwiftPM identity conflicts and deployment/deprecation/concurrency warnings remain; no release/full suite/Linux/cancellation/two-Core checks are claimed. No commit/push/deploy/Core restart.

## 2026-11-17 resume: root and toolchain boundary regressions

Continued the same isolation assignment, preserving prior evidence and dirty checkout. Initial snapshots and new logs are in `.sloppy/verification/macos-isolation-resume/`. Two new test methods initially failed with three expectations: profile accepted `/tmp` as a writable root, a replaced task directory was accepted, and a nonexistent Xcode Developer directory was accepted. The production guard was never removed.

Fixes in `MacOSReceivingIsolation.swift`:

- Writable roots must now be private same-UID directories below the canonical per-user temporary directory; the temp directory itself and arbitrary host directories are rejected. Group/other permissions must be absent. This narrows the prototype API rather than making caller-provided roots an authority.
- Workspace captures device/inode at construction and revalidates before each launch. A directory moved aside and replaced between commands is rejected. This detects static between-command substitution, **not** a complete concurrent TOCTOU defense: profile installation, path-based process cwd, parent rename and hostile same-UID concurrency still require a supervised broker/descriptor-based contract.
- Explicit Xcode Developer paths must exist and exactly match POSIX realpath; missing or symlink-remapped installs are rejected. Signature validation and replacement during launch are still not provided.
- Private HOME creation occurs during Workspace construction/preparation, not at every command launch. `NodeMeshProcess` no longer mkdir/chmods a supplied HOME; it verifies an existing real directory. `.home` symlink attempts remain rejected and a regression asserts that the outside fixture mode is unchanged. Default helper-owned temporary HOME behavior is unchanged.

Verification: two RED tests/three failing assertions recorded in `red.log`, then 28 tests/4 suites passed (`green.log`). After final HOME adjustment, the expanded regression command covering isolation/process/worker/GitPolicy/remote contract/LongChat/reuse passed **62 Swift Testing tests in 9 suites**, 8.532 seconds execution (`final-tests.log`). Both debug product builds passed (`build-sloppy.log`, `build-node.log`, current-turn evidence verification-1 and verification-2). Scoped `git diff --check` passed. Shell-wrapped test calls returned logs but no typed verification ID; no test evidence ID is invented.

The actual Seatbelt canaries and clang/network-EPERM smoke remain green. This is still **not** a production receiving executor: no timeout/cancellation/descendant ownership or bounded EOF, no Core file-tool sandbox wiring, no hardened privileged Git-preparation broker, no durable start/status/follow-up/cancel/reconnect lifecycle and no two-Core E2E. No new network exceptions were added. OS/daemon services were not started or changed; no foreign build was killed; no commit/push/deploy/restart. Full suite/release/Linux and physical host validation remain unperformed. The library-only result does not require a Play configuration.

## 2026-11-17 TOCTOU investigation: reproducible directory replacement, NOT fixed

The narrow requested race-free fix is **not delivered**. This iteration adds deterministic characterization evidence, not another inode preflight claimed as atomic protection. No unsupported OS-permission or entitlement blocker has been proven; lack of an implemented safe launch broker must not be described as OS impossibility.

`MacOSPathBindingTests.postValidationReplacementHasNoVnodeBinding(useSymlink:)` constructs the exact textual profile using the existing validated private root, then pauses at the validation/use seam by performing a controlled replacement before invoking the same `NodeMeshProcess` + `sandbox-exec` launch tuple as Workspace. No global hook or production bypass flag was added. Only disposable synthetic data is read.

- Replacing the validated task path with a **different real directory** containing a synthetic secret succeeds: that secret is read after sandbox installation. Path rules authorize the replacement occupying the path, not the previously checked device/inode.
- Replacing it with a symlink to the outside fixture is denied on this host. The first probe incorrectly expected this to leak and failed (`repro.log`); the failed hypothesis is retained, not claimed as evidence of a leak. The real-directory variant then reproduced the defect (`directory-replacement.log`). Final parameterized characterization covers both outcomes.
- This test deliberately checks the current unsafe behavior. A passing characterization is evidence of an OPEN defect, not an isolation acceptance test. Once a safe launch mechanism exists, convert the real-directory branch to require denial or execution confined to the original pinned object.

The concrete seam is between `Workspace.run`'s rootIdentity/profile construction and `Process.run`/sandbox-exec resolving `currentDirectoryURL`, HOME and the textual Seatbelt subpath. `fchdir` or a retained directory FD by itself would only bind cwd, not the separately interpreted path grant. A second stat/realpath moves the window rather than eliminating it. Closing it requires an ownership boundary preventing untrusted replacement during policy installation (including parents/toolchain grants), or a verified vnode-bound policy/file broker plus descriptor-bound launch. No such adapter has been implemented/tested in this iteration; no private sandbox API or undocumented extension is assumed safe.

Only a security warning was added to the prototype source; it remains internal/unwired. Production `remote_execution_unsupported` remains intact. Previous private Git/pinned base, static secret/symlink/source-write denial, subprocess inheritance and compiler/network canaries remain in the focused run, but they do not establish adversarial race safety. Cancellation/descendant ownership, durable prepare/start/status/follow-up/cancel/reconnect and two-Core E2E remain unfinished. Library prototype has no Play target. No commit/push/deploy/Core restart, external host or service/container startup occurred.

Final validation: **63 Swift Testing tests in 10 suites passed**, 6.987 seconds execution; the parameterized characterization has two argument cases but is one reported test. Logs: `.sloppy/verification/macos-toctou/final-tests.log`, `build-sloppy.log`, `build-node.log`. Both debug product builds passed, scoped diff check passed. Full suite/release/Linux/physical host verification not performed; existing SwiftPM dependency identity warnings remain. Runtime wrappers returned no typed verificationEvidence.id for these shell-wrapped commands; no IDs invented. Overall race-fix outcome is failed/incomplete, despite reproducible characterization and green regression/build commands.
