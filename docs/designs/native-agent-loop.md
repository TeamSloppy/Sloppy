---
layout: doc
title: Unified Native Agent Loop
description: One owner for model steps, tool execution, completion, context and recovery.
---

# Unified native agent loop

Status: approved for implementation by the contributor in chat on 2026-11-04. Date: 2026-11-04.

This English design replaces the earlier proposal at `docs/architecture/native-agent-loop.md`. It preserves the proposed architecture and makes implementation boundaries and delivery criteria explicit.

## Purpose and scope

Sloppy owns one native agent loop. A provider returns one complete model response; the runtime executes tools, persists their outcomes and makes one continuation decision. Existing approvals, filesystem policy, typed outcomes, verification evidence, coordinator handoff and worker finalizers remain enforced.

Start with ordinary native sessions, then native workers and the standalone host. External ACP agents retain their own internal loop and adapt their events/outcomes at the existing boundary. Keep Swift actors, current module dependencies, public tool APIs and JSONL storage. Do not replace the runtime with pi or introduce a generic hook framework.

![Target native agent loop](/design/native-agent-loop.svg)

Baseline: Sloppy `0efc5991c6f5450e55cc1252163c24a1f464a7dc`; pi `8da141c2ad8f9e9b5e9d3e42d78c4ed90c4fe125`. Adopt pi's common loop, request/turn boundaries and canonical session projection. Retain Sloppy's stronger completion, access and concurrency policies.

## Current problem

Provider implementations in AnyLanguageModel own repeated tool/model requests, while `RuntimeSystem.respondInline` adds stream retries, reconnect, context reset, non-streaming fallback and empty-response repair. `AgentSessionOrchestrator` adds completion recovery and derives outcomes from several parallel dictionaries and flags.

Request preparation runs before a potentially multi-request provider operation. The streaming tool handler checks the read ledger and records observations, but the timeout fallback handler calls the invoker directly. Recovery paths must duplicate setup and preserve already completed effects. A repeated read can currently return `ok: true` with a 240-character digest instead of the requested content. Build/Debug also add a separate planning request by default.

## Definitions and invariants

| Term | Meaning |
| --- | --- |
| Session | Durable conversation and journal |
| User turn | One task with stable `userTurnID`, evidence and budgets |
| Run | Active handling until completion, pause or stop |
| Model step | One model response and its complete tool batch |
| Request attempt | One provider request within a step |
| Projection | Deterministic model-visible view of persisted context |
| Settled | Required events are persisted and operations have stopped or have explicitly recorded unknown outcomes |

1. Only the loop schedules model steps. Providers receive declarations, never executable tool closures.
2. Persist intent and a start marker before an effect; enforce current policy and approval immediately before execution.
3. Preserve a final result per invocation, source call order and explicit call/result correlation. Reconciliation appends provenance-preserving corrections.
4. An unknown effect outcome cannot authorize replay. Exactly-once external effects are not promised.
5. Do not execute calls from output-limit or incomplete responses, including JSON that was salvaged successfully.
6. State and completion decisions use typed signals, never assistant phrases.
7. Cancellation cannot revive a run through a late callback; completed old-generation effects still receive durable outcomes.
8. A successful read returns content or a full equivalent cache entry. A digest is summary data, not a successful substitute.
9. Recovery retains the user turn, evidence, elapsed budgets and already completed work.

## Ownership and contracts

| Component | Ownership |
| --- | --- |
| `AgentLoop` and `RunState` in `AgentRuntime` | Model steps, queues, cancellation, budgets and transitions |
| `ModelStepProvider` in `PluginSDK` | One request, normalized streaming, complete response and typed failure |
| `ToolPipeline` | Runtime coordination through injected existing Core access/approval/invocation services |
| `SessionProjection` in `SloppyRuntime` | Journal/checkpoint projection, extending `AgentSessionTranscriptBuilder` |
| `RecoveryPolicy` | One typed recovery decision and bounded attempts |
| `CompletionPolicy` | Runtime contract with Core implementations for Build/Debug, coordinator and delegated worker |

Dependencies remain `Protocols → PluginSDK → AgentRuntime → SloppyRuntime/Core`. Runtime receives journal/projector closures and never imports Core or its file store. Existing event infrastructure remains in use.

`ModelStepProvider.streamStep(ModelStepRequest)` returns an `AsyncThrowingStream<ModelStepEvent, Error>`. The immutable request includes IDs, selected model, ordered messages, declarations, generation options, projection revision and provider/cache scope. Events are started, text/reasoning/tool deltas and exactly one final `ModelStepResponse`; closing without a final response is a typed failure. The final response includes complete ordered calls with IDs, usage, `endTurn/toolCalls/outputLimit`, and provider continuation metadata. UI deltas never replace the final response.

Preserve signed reasoning, continuation tokens, image limits, cache affinity and usage attribution. Transport errors normalize to category/code/retryability/stage/retry-after. OAuth refresh stays inside the adapter; generation retries are visible to the loop and its deadline. Consumer cancellation cancels the underlying request via stream termination.

Add this capability alongside the existing `ModelProvider`. A legacy multi-step provider cannot be made single-step by stopping its delegate after effects have run. Unsupported providers stay entirely on the legacy engine until their adapter passes the contract suite.

## State and events

One actor-owned `RunState` contains run/user-turn IDs, generation, model/mode/policy versions, queues, step, counters, active calls, completion and evidence. Its phase is preparing, requesting, executing, waiting approval, recovering, finalizing, stopping or settled. Individual calls retain their own state during parallel execution. Derive explicit-completion flags and summary from one completion record.

```text
Durable input → prepare projection and request → one model response
→ persist assistant final → execute tool batch → persist results/evidence
→ finish step → continue, recover, finalize or stop
```

Persist the assistant before tool preflight. Emit execution completions as tools finish, but project results in model source order. Retain both provider call IDs and `callEventId`; use legacy FIFO matching only for old records. Await durable writes and mandatory observers. UI streaming uses a bounded buffer; deltas may coalesce, critical final/results/approval/stop events may not disappear from durable history. A slow client that cannot accept critical updates disconnects and resumes from a persisted event cursor rather than growing an unbounded buffer or blocking effects. A write failure prevents new effects and marks unresolved started calls for recovery.

## Tool execution and concurrency

Every transport/recovery path uses the same sequence: resolve declaration and normalize arguments, validate schema, check reconciliation/loop guard, apply current access/pre-hook rules, await required approval, persist start, execute, normalize/archive output, record evidence and persist result.

Malformed calls return structured diagnostics without invented values. Ordinary tool errors return observations to the model; loop stops and terminal policy decisions remain explicit. Preserve contiguous concurrent safe-read segments and exclusive barriers for other calls, including unknown, MCP and shell tools by default. Recheck cancellation and policy after approval.

Consolidate tool metadata, keeping `readOnly`, `concurrencySafe`, `replayPolicy` and `cachePolicy` independent. Initially remove ledger read interception and retain its compact factual summary for compaction. Any later cache requires full equivalent results, valid resource versions and the same access policy.

## Completion and verification

After each step, policy returns continue, recover, finalize or stop. Ask/Plan may finish without tools. Build/Debug retain required `session.complete`. Coordinators use assignment evidence and existing report review; delegated workers use `agent_delegate.finish`.

Validate completion status, nonempty summary, evidence IDs and concrete blocked limitations. Rejected completion returns a tool error. The new waiting-input policy links to a live input request. Accepted completion is an exclusive barrier: remaining calls receive `not_executed_after_completion` results. Allow at most one tool-free final-answer step; its failure retains the accepted completion summary and never repeats work.

Ordinary Build/Debug may receive up to three completion-recovery continuations when otherwise eligible. They retain evidence/budgets and merge with an already required tools/steering request. Cancellation, access denial, pending input, reconciliation and hard limits cannot trigger automatic completion recovery.

Evidence records the source call, kind, outcome, resource scope and revision. Advance a conservative work-scope revision after known mutations and before unknown mutating operations; verification from the operation binds to its resulting revision. Older evidence does not certify later changes. External hashes/versions detect only observable external changes. Process `started`, `ready` and `passed` are distinct. Introduce stricter freshness/verification semantics separately from engine migration, with a versioned policy.

## Recovery

| Cause | Decision and bound |
| --- | --- |
| Transport loss before final response | Retry the saved model step; no tool from this attempt has executed |
| Context overflow | Compact the projection and retry once until the next successful step |
| Output limit with calls | Do not execute; persist paired errors allowing complete calls to be reissued |
| Empty final after tools | At most one tool-free finalization, never replay the original task with tools |
| Missing required completion | Bounded policy continuation, up to three passes |
| Started effect without durable outcome | Interrupted result and owner reconciliation; no automatic replay |
| Cancellation, denied access, loop stop | Typed stop; no bypass through model or transport fallback |

One policy owns `retryRequest`, `compactAndRetry`, `renderFinalAnswer` and `continueForCompletion`. Each carries a reason, budget and attempt. Preserve current configured retry values initially while eliminating nested multiplication. Attempts, tool rounds, cost and configured deadlines accumulate across recovery/restart; disabled user limits stay disabled. A tool-free final step still consumes a request and usage.

Model fallback follows existing routing/capability policy and never expands authority. Recompute limits; incompatible provider tokens must be explicitly normalized rather than silently reused with another provider.

## Projection and persistence

JSONL is authoritative; all caches are disposable. Build the next context from a compatible checkpoint and subsequent events. Bind session caches to projection revision, model, schema loadout and configuration. Prepare context before every request, budgeting instructions, schemas, images, input and reserved output.

Archive old large outputs before replacing them with complete artifact references, then summarize if necessary. Preserve the original task, recent user messages, paired/unresolved calls, pending approvals, evidence IDs and limitations. Failure leaves the previous projection; protected context that cannot fit fails explicitly instead of replaying with empty history. Bootstrap contains instructions/project context, without a duplicate rendered conversation. Maintain stable system-section and declaration order for prefix caching.

Add optional typed `runtimeMetadata` to existing `AgentSessionEvent` kinds: schema/run/user-turn/step/attempt IDs, generation, source order, execution phase, recovery/policy versions and checkpoints where needed. Do not reuse the existing unrelated `metadata` field or add public event enum cases unnecessarily. Keep public terminal outcomes compatible. Checkpoints store the covered cursor, projection version, summary, referenced entries/artifacts and reconstructable instructions/loadout.

Ship the reader before the writer. Reconstruct old IDs deterministically; imported calls remain historical. Distinguish requested/started/settled. A crash after the durable start marker is conservatively unknown even when the effect may not have begun. Preserve `SessionToolRecovery` and owner reconciliation. Test old clients separately from old Core binaries. Before enabling the new writer, a version gate must prevent an incompatible Core from resuming the new journal before effects; otherwise do not enable it in downgrade-capable environments.

## Input and cancellation

Steering enters at the next completed step; follow-up waits for the current task. Use explicit existing input metadata, not phrase classification. Recheck steering after long compaction before freezing the request. Once frozen, later input waits for the next boundary. Durable enqueue precedes acknowledgement, and queue selection/settlement is atomic under the run owner.

Priority is cancellation/hard stop, settlement of active step results, accepted completion/pause, steering, tools/policy continuation, then follow-up. Input after accepted completion becomes next-run input. Cancellation immediately reaches provider/child tasks; late-generation callbacks cannot schedule new work, but actual effect outcomes are still recorded. Unknown remote effects require reconciliation rather than an assumption of cancellation.

## Planning configuration and delivery

Introduce `legacy`, `executor` and `separate` planning policy. Migrate existing agents to legacy behavior and retain `plannerModel` API/Dashboard values. Executor planning starts immediately and maintains a plan through tools. Separate planning retains the existing tool-free planner and configured model/fallback. Change new-agent defaults only after independent evaluation; engine migration alone does not change planning defaults. This explicitly supersedes the always-plan behavior proposed in the older [planner specification](../specs/planner-executor-model-routing.md) only when the new policy is enabled.

Update the user guide `docs/guides/native-agent-execution.md`, linked in `docs/.vitepress/config.ts`. Explain current versus proposed support, read-result semantics, recovery/unknown outcomes, cancellation and completion limits. Verify examples through scripted production-path fixtures; add real CLI/config examples only when those APIs exist. The architecture document and ADR do not substitute for the guide. Run VitePress and validate navigation before review. Update the guide in every delivered behavior slice, including supported providers and platform limits.

## Migration and acceptance

1. Unify tool handling for stream/fallback and stop substituting read digests.
2. Introduce `RunState` and pure completion/recovery policies while retaining legacy transport.
3. Ship metadata reader, projection checkpoints and tested version gate.
4. Introduce one true single-step adapter and the common loop, initially behind explicit engine selection.
5. Pilot new native sessions, then opt in workers and standalone consumers.
6. Port remaining providers; separately enable planning and evidence-policy changes.
7. Remove obsolete loops/maps only after the last supported consumer migrates.

Pin engine and policy versions per run. Never switch engines during an active call, unknown outcome or approval. Rollback sends new eligible runs to legacy; unified journals resume with a compatible reader/engine or stop explicitly. Shadow comparison is limited to pure projection/policy decisions and cannot execute a second tool loop.

Tests use a scripted provider, fake effects, controllable time and fault injection around persistence. Cover response/tool/response, safe-read barriers, incomplete and truncated calls, tool errors, crash after effect, tool-free empty-answer repair, completion followed by another call, stale evidence, approval cancellation, steering during compaction, enqueue/settle races, restart with images/evidence, provider fallback, old/imported journals, coordinator and worker finalizers. Assert typed events and effect counts, never model prose or source-text surrogates.

Before provider rollout verify streaming/non-streaming parity, usage, reasoning and continuation. Run owning suites, `swift test --parallel`, release products and required downstream/platform checks through the contribution runner. Shared protocol changes select client/Dashboard checks where applicable. Independent review inspects the final snapshot and evidence; unavailable tools/platforms block completion.

Measure fixed coding tasks/models/settings/prompts with at least three repetitions per task: solve rate, valid completion rate, first-tool latency, total latency, input/output/cached tokens, cost per solved task, recovery by reason, compaction and duplicate effects. Hard gates: zero duplicate automatic effects in deterministic fault tests, no approval bypass and no lost critical events. Proposed pilot gates: median first-tool latency and cost per solved task regress by no more than 10%, solve rate by no more than 5 percentage points. Insufficient samples do not justify wider rollout. Evaluate planner/freshness changes independently.

## Alternatives and risks

Splitting the orchestrator into files alone does not remove provider-owned scheduling. Replacing the runtime with pi discards existing Swift and product boundaries. A general-purpose hook framework adds unnecessary control surfaces. Removing explicit completion loses Build/Debug guarantees. Keep small typed contracts and existing service injection.

Single-step adapters must preserve provider signatures, continuation, caching and usage. Unsupported capabilities remain legacy. Avoid a new actor monolith by keeping projection and policies separate. Journal metadata uses bounded values/references rather than duplicate outputs/images; retain artifacts needed by active runs and recovery. Strict evidence freshness may require extra checks and is separately gated. Successful evidence is not proof that every semantic requirement is met.

## Related contracts

Preserve [coding harness guarantees](../specs/coding-harness.md), [session reliability](../architecture/agent-session-reliability.md), [session tools/chat](../specs/agent-sessions-tools-chat.md), [long chat](../specs/long-chat.md) and [semantic routing](../specs/semantic-decision-routing.md). Existing ADRs retain their historical meaning; lasting ownership changes are recorded in the accompanying ADR.


## Ownership and artifact closure (2026-11-06)

The contributor explicitly requested completing the five listed implementation limitations. This
extends the accepted implementation scope; review remains deferred. New code must preserve old public
API signatures and readable old journals without silently replaying unknown effects.

- Use OS-held exclusive file leases (Darwin/Linux flock; Windows exclusive CreateFile handle), never
  stale PID files. A competing embedded host must fail before enqueue/effects. Hold a session lease
  across queued callers and outstanding late effect persistence. Approval persistence has one live
  storage owner; a contender fails closed and may acquire ownership only after a fresh reload.
- Reject same-conversation send reentry from awaited host callbacks using typed task-local context,
  including build and tool callbacks. Calls from independent UI tasks retain FIFO/steering behavior.
- Archive complete outputs without the upload API's 25 MiB ceiling, expose verified bounded reads and
  file export, and reclaim only unreferenced old generated blobs under an exclusive session lease.
  Active/evidence/completion references are roots. Preserve public hydrated results while a new guarded
  journal format can replace duplicated inline payloads. Missing canonical payloads fail explicitly.
- Embedded callers receive artifact metadata and verified reader/export APIs plus transcript linkage;
  UI presentations use these APIs rather than treating Core URLs as an embedded server.
- Consolidate supported native execution on the common owner. Retain legacy API/configuration readers
  and explicit adapters required by old/non-step providers; compatibility must not revive duplicate
  tool scheduling. Never switch an admitted owner during an effect or approval.

Document each delivered slice in docs/guides/native-agent-execution.md (existing navigation), with
owning filesystem/host/Core tests and docs build. Record remaining external validation separately.
