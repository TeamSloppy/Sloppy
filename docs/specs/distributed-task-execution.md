# Distributed task execution

**Status:** Proposed · 2026-11-18

Builds on [ADR 0011](../architecture/adr/0011-bind-worker-reuse-to-execution-target.md), the [remote subagent handoff](../guides/remote-subagents-handoff.md), [Long Chat](long-chat.md), and [SloppyNode Mesh](../guides/mesh.md). Today `long_chat.delegate` supports the target contract and returns `remote_execution_unsupported` for remote execution. Kanban already stores `executionNodeId`. The dispatch and verification flow below is the proposed extension.

## Single-machine pilot

Dashboard, TUI and ClientNative suggest machines after `$`. Online Mesh nodes use their registered project alias when available. Operators can add SSH entries to `<Core workspace>/ssh-machine-targets.json` as an array of records with `alias`, `name` and optional `projectId`. Entries are labels for hosts the operator has already configured. The directory does not probe hosts or carry SSH connection details.

An admin can send `/verify $home_machine <full-commit-id>` in a project chat. The operator must configure an exact match in `<Core workspace>/machine-verification.json`. Each record contains `projectId`, `alias`, `nodeId`, `commit`, `tree` and `executable`. The configuration and executable are private regular files. The executable is an operator-maintained, non-interactive check with a fixed transport, destination, source snapshot and test command. It takes no arguments from chat. On success it reports `Commit: <full-commit-id>` and `Tree: <full-tree-id>` on stdout and exits zero. Core records the resulting status and bounded log in the chat. The initial home check uses SSH with the pinned host key. General remote Long Chat delegation remains disabled.

An admin can also ask the AdaEngine project coordinator to “build Studio on `$home_machine`” in Auto or Build mode. The coordinator model selects `long_chat.build_studio`. Core checks that the exact alias occurs in the current user message and resolves a single profile for that project and machine with `operation: "studio_build"` in the same registry. The profile supplies the commit and executable. Core records the queued build in the conversation before execution and posts the final status and log when it returns. Repeated tool calls from the same user turn reuse that reservation. If Core restarts before recording a result, it reports an interruption and does not replay the build.

## Roles and ownership

One Core owns a run. It may be the user's laptop, home Core, or another machine that owns the conversation or project board. It resolves targets, persists the plan and inputs, dispatches work, and aggregates results. The Mesh relay routes messages. Each receiving Core owns execution, local permissions, process lifetime, and its results. Coordinators and executors may serve other roles in other runs. An orchestrator restart keeps ownership on the same Core.

The existing [Shared Project mapping](../guides/mesh.md#shared-projects) associates a repository with each node's checkout and permissions. The operator registers aliases in the coordinator's `remote-execution-targets.json`, mapping them to stable Mesh node IDs. Each target also has a receiving policy for that shared project, approved agent/tool access, and supported OS and check capabilities. A registry entry and an online heartbeat are discovery signals. The receiving Core verifies the mapping and reports live readiness before work starts.

## Chat and Kanban

### Machine mentions

- The composer completes registered `$` aliases and sends machine references separately from message text. Plain-text clients can recognize exact registered tokens outside code spans and escaped text. The Core resolves and authorizes each reference before admitting it to a plan. An explicit unresolved or ambiguous machine selection produces a target error. Ordinary text and shell variables have no routing effect.
- The coordinator model interprets the user's objective and emits a typed Long Chat plan. In “Fix the Studio bug, verify everything on `$windows_machine` and `$home_machine`”, both references constrain verification. The implementation step uses the project's default execution target, or the coordinator's local worker if the project has no default. “Fix it on `$home_machine`” instead pins the implementation step to home. The UI shows the actual target for each step.
- Each child still carries at most one `executionTarget` from ADR 0011. Multi-machine verification creates one child per distinct node. The Core checks that every explicitly requested verification target appears in the plan. It rejects a plan that omits one or maps two intended machines to the same node. An explicit offline target remains selected. Aliases are display names once the run is saved, and alias edits never retarget existing attempts.

### Task properties

Use the existing **Runs on** field for the task's primary executor (`executionNodeId`) and **Assignee** for its agent (`actorId`). Add an optional **Verify on** multi-picker for required verification nodes, proposed as `verificationNodeIds`. A saved task with no verification targets retains its current behavior. A chat launched from a task starts with these settings. An explicit chat override applies to the current run. Changing the saved task requires a task edit.

The task board owns the task record. Starting a task creates or reopens its run on that Core and dispatches to the pinned executor when remote, using the same Long Chat ledger as chat delegation. The initiating action uses a stable key so a repeated Start opens the active run. The remote dispatch path is owned by the board Core, and the existing local lifecycle guard continues to prevent a second local execution. Changing **Runs on** or **Verify on** changes the next run. The active run retains its plan and remains visible from the task. Surface each machine's offline, blocked, running and finished state in chat and task details.

## One fix, two verification jobs

1. **Pin the source.** The coordinator resolves the current project revision to an immutable Git object ID. It reports any relevant working-tree changes before dispatch. The default input is the committed revision. If the user asks to include local changes, capture the approved tracked changes and explicitly selected untracked files in an immutable input snapshot. Scope the capture to the project and exclude secrets, ignored files and generated output. Once the run starts, later edits in the user's checkout have no effect on its input.
2. **Produce the fix.** The implementation worker edits a private task workspace. It returns its change artifact against the exact input plus its structured completion and evidence. The coordinator validates the artifact, materializes it against that input in a private staging repository and freezes the result as a Git commit object with an exact tree. Internal task refs can retain this object for the run. The user checkout, branches and remotes are outside this operation.
3. **Publish the verification input.** Store a content-addressed Git bundle for the fix and its manifest under the run. The manifest binds the shared project, original base, input commit, fix commit, tree ID, bundle digest and size. The bundle includes the private commits needed to reconstruct the fix, with the original base as a prerequisite. Use an authenticated artifact transfer scoped to the run and receiving node. Each receiver resolves the base from its repository mapping or an allowed fetch, imports into private Git storage, verifies the digest, ancestry and tree, then creates its task checkout. A missing base, invalid bundle or checkout failure blocks that target before any check runs.
4. **Fan out.** The Windows and home verification children depend on the frozen fix. Each receives the same manifest and its own check profile. The project defines stable required checks per platform with approved commands, working directories, and toolchain constraints. Record the profile version in the run. Validate it against receiving policy before invoking it. Both children verify the same Git tree and record the actual platform, toolchain and checkout settings. If the project needs submodules or Git LFS, preflight also verifies the pinned dependencies and blocks the check if it cannot materialize them. Scratch output and build caches are private to the attempt.
5. **Collect.** Each worker reports the verified input identity, check outcomes, and evidence. If a check requires changing source, it returns the failure and evidence to the coordinator. A revised fix creates a new snapshot and a new verification round. Results from older snapshots remain inspectable in history. Applying the selected fix to the user's checkout is a separate action with its own conflict check.

| Step | Machine | Input | Output |
| --- | --- | --- | --- |
| Fix Studio | Project default or local coordinator | Pinned base or approved input snapshot | Candidate fix |
| Freeze candidate | Coordinator | Base plus accepted change artifact | `fixCommit`, `treeId`, bundle digest |
| Verify Studio | `$windows_machine` | Same frozen candidate | Windows build and test results |
| Verify Studio | `$home_machine` | Same frozen candidate | Home build and test results |

## Model selection

Model generation and tool execution are independent. The coordinator retains its conversation model. An agent-backed execution step stores its agent, selected model, and inference route separately from its executor. Resolve choices in this order:

1. Explicit model selection for the step, including any explicit inference location.
2. The project's model policy for that role, such as implementer or verifier.
3. The receiving agent's configured default.

Resolve these choices against the receiving agent's allowed models and its live catalog. An authorized [Sloppy server provider](../guides/model-connections.md) can serve inference from another Core. The executor keeps all tool calls local to its task workspace. Provider keys stay on the serving Core. Check both the execution agent's policy and the inference route's project/data permissions before sending model input. The worker receives the approved objective and input scope. Transcript, attachments, provider credentials and local agent configuration are outside that payload.

Persist the resolved provider/model and inference Core with the attempt. An unavailable or disallowed explicit choice blocks preflight. If a route disappears mid-run, report the model error and require a new attempt for a route change. Reusing the same execution context retains the ADR's machine, base, agent and scope bindings. Verification that only invokes a fixed project check profile can run without an agent turn or a model.

## Dispatch, recovery and cancellation

Reuse Long Chat assignments, dependencies and attempt history, and the existing Mesh transport for proposed `subagent.*` operations. The coordinator persists a start request before sending it, keyed by coordinator, run, child and attempt. The receiver binds that key to the authenticated peer, pinned node, request digest, workspace, and remote session. A repeated start with the same digest returns the saved state. A different digest is a conflict. The receiver durably records launch intent and owns the task's processes. Recovery reconciles launch intent with process ownership before any repeat launch.

| Situation | Behavior |
| --- | --- |
| Machine offline before start | Keep the child queued for that node and show the missing verification. Other eligible children can run. |
| Delivery or start acknowledgement lost | Query the same attempt and replay idempotently as needed. Resume events from the persisted cursor. |
| Worker disconnected after start | Show the last known state and reconcile on reconnect. Hold its locks while process or result status is uncertain. |
| User cancels | Stop queued work and request cancellation of active attempts. Keep active attempts in cancelling until the receiver confirms owned processes have stopped. |
| User retries a failed or blocked check | Start a new attempt on the pinned node and snapshot once its predecessor is resolved. Changing the snapshot starts a new verification round. |
| A stale attempt reports completion | Retain it in attempt history. Only the active attempt for the current snapshot counts toward verification. |

Follow-ups target the original remote session. Persist message IDs and receiver acknowledgements so reconnection does not replay a user action. Result retrieval is idempotent. Artifact downloads can be retried separately from task execution.

### Receiving boundary

Intersect coordinator delegation scope, receiving project grants, receiver agent permissions and platform capabilities at each operation. The receiving OS adapter confines Git, file tools and subprocesses to authorized task and toolchain roots, strips inherited secrets, and owns descendants for timeout and cancellation. Receiving preparation must protect workspace and toolchain paths against replacement between validation and launch. Private Git storage and network access are covered by the same policy. Windows and the home platform qualify independently. Keep `remote_execution_unsupported` for targets without a validated execution adapter and lifecycle. See the [open macOS isolation issue](../architecture/adr/0011-bind-worker-reuse-to-execution-target.md#toctou-characterization-open-defect-no-atomicity-claim).

## Results and task state

Each completed attempt emits a structured record with project/run/child/attempt IDs, node ID, base and fix commits, tree ID, check profile, platform and toolchain, and a result for every required check. A check record includes its ID, exit status or reason it did not run, and bounded log/artifact references with sizes and digests. The receiving Core binds the record to the authenticated attempt. The coordinator rejects records with a mismatched project, executor or snapshot. Chat and Kanban show the same ledger, with one row per target and links to its evidence.

Keep implementation state, verification state and fix application state independent. Verification passes when all required checks report success for the current snapshot on every selected node. A failed check yields failed verification. Offline, cancelled, timed-out, interrupted and incompatible checks remain visible with their specific outcomes. Until all required results arrive, the coordinator reports the completed checks and which checks are outstanding. The task can be ready for review once implementation and required verification pass.

## Onboard machines over SSH

Use the bundled skill **`ssh-machine-onboarding`** from an operator session to verify SSH access and prepare Windows, macOS or Linux for Mesh enrollment. Pair through the [Mesh setup guide](../guides/mesh.md#quick-start), register the alias against the confirmed `nodeId`, and attach the shared project. Verify SSH access, Mesh membership and executor readiness as separate checks. SSH host names and keys belong to operator configuration. Dispatched steps use Mesh node IDs and never carry SSH credentials or shell connection details.

## Acceptance

- A chat request and a Kanban task each exercise dispatch to Windows and home. Both workers report the same fix commit and tree. The orchestrator reports distinct platform results and the fix remains available for explicit application.
- A required node goes offline, reconnects after an acknowledgement is lost, and completes without a duplicate process. Repeat across coordinator and receiver restarts. Cancel a running check and confirm its process tree has stopped before retrying.
- When one target fails, is unavailable, or returns a result for a different snapshot, the parent cannot reach verified. A second fix triggers fresh required checks. Retries of one target preserve the other target's evidence for the same snapshot.
- Exercise machine mention escaping, alias remapping, legacy local tasks, task edits during a run, dirty-input capture, missing base, corrupt bundles, and receiver-side permission revocation.
- Verify an explicitly selected model, a policy default, a permitted model hosted on another Core, and a denied route. Confirm the chosen provider and evidence identify their respective machines.
- Validate execution isolation and the full lifecycle in a two-Core test before enabling a platform. Exercise the cross-platform example on actual Windows and home machines before advertising it as supported.
