# Unified native agent loop implementation

Design: [approved native loop](../designs/native-agent-loop.md). Approved in contributor chat on 2026-11-04. All seven migration stages are in scope. This plan records implementation progress; unchecked items are not shipped behavior.

On 2026-11-05 the contributor explicitly instructed the implementer to finish remaining work
without a reviewer and discuss it afterwards. Further reviewer work is waived by that instruction;
earlier independent reports remain historical scoped evidence. Behavioral validation is still required.

## Delivery order

- [ ] 1. Use one observed tool handler for legacy streaming and fallback. Repeated reads execute normally; keep ledger summaries for compaction. Exercise actual RuntimeSystem tool paths.
- [ ] 2. Introduce actor-owned RunState and typed completion/recovery decisions. Retain legacy transport while consolidating budgets and cancellation state.
- [ ] 3. Add backward-compatible runtime metadata readers, canonical projection/checkpoints and a tested compatibility gate before enabling journal writers.
- [ ] 4. Add the single-step provider contract and a true adapter, preserving OAuth, opaque continuation, reasoning, usage, cancellation and raw arguments. Integrate AgentLoop behind explicit engine selection.
- [ ] 5. Connect native sessions, workers and standalone host with shared pipeline, completion barriers, queues, durable effect tracking and reconciliation.
- [ ] 6. Port each supported provider after contract tests. Add versioned planner and evidence policies while preserving existing defaults. Evaluate rollout independently.
- [ ] 7. Remove legacy owners only when every supported native consumer has migrated. Update guides and ADR status with actual support and limitations.

## Validation

### Stage boundaries and acceptance

The approved design remains unchanged. Each stage closes against its deliverable and owning checks;
later migration work does not retroactively expand an earlier stage. The final runner report, supported
platform evidence, rollout evaluation and independent review cover the complete implementation.

| Stage | Deliverable and owned scope | Acceptance and required checks | Boundary |
| --- | --- | --- | --- |
| 1 | Shared legacy observation in RuntimeSystem and SessionWorkLedger | Actual streaming, fallback and reset tools return full repeated reads; owning runtime/ledger tests | Keep legacy consumers until stage 7 |
| 2 | RunState, completion/recovery policies and snapshots | One turn owns counters, configured budgets, pins, completion and cancellation across retries/restart; runtime policy/state tests | Product handoffs belong to stage 5 |
| 3 | Protocol envelopes, file store, projection and storage codec | Legacy compatibility, future-version rejection, atomic records, checkpoint retention, paired writer protection; journal/catalog and prefix-fault tests | Do not infer execution authority from copied history or disposable caches |
| 4 | ModelStepProvider, AgentLoop and shared ToolPipeline | Exactly one complete provider step; durable effect boundary, owned cancellation/recovery and bounded streams; portable loop/provider contract suites | A passing adapter does not claim every consumer/provider migrated |
| 5 | Core/native consumer integration | Canonical input/cancellation/failure/receipts and queue reconstruction; owned pause/approval/derived work; sessions, workers, coordinators, planners and standalone host use the shared owner; owning Core/runtime/restart tests | Preserve supported defaults; no legacy removal before the last consumer |
| 6 | All supported providers and versioned product policies | Mock, Claude Code, remote transports and factory aliases preserve auth, raw calls, continuation, reasoning, usage and cancellation; independent fixed-task evaluation with approved sample/metric gates | Record unavailable live/platform evidence as blocked |
| 7 | Remove superseded owners and finish documentation | Consumer inventory has no remaining native legacy owner; unfiltered suites, release products, Dashboard/docs/client/platform checks, final complete runner report and independent review | Completion requires every approved stage and mandatory check |

Current stage 5 work is grouped into four acceptance gaps: canonical input lifecycle/reconstruction;
pause, approval and derived-work ownership; remaining native consumers; and durable reconciliation.
Scoped reviews distinguish demonstrated regressions or unmet approved requirements from optional
coverage and adjacent pre-existing issues. SQLite telemetry write-error reporting is an adjacent issue;
it is not a newly added requirement of the queued-input slice.

The canonical-input block now includes cache-independent recovery/ingress, previous-format queue
backfill, source eligibility for forks, atomic UI receipts and semantic projection. Focused cycles are
retained in `unified-native-agent-loop-v2`. Its owning Core/UI/compatibility aggregate passes 152
functions in 13 suites (81.095s); the actual-source portable/runtime/provider/accounting aggregate
passes 105 in 7 suites (3.172s). Independent scoped re-review found no remaining defects within this
block and accepted the recorded TDD exceptions. This does not close
the remaining stage 5 pause/approval/derived-work, consumer migration or reconciliation gaps.

An initial UI fixture incorrectly coupled receipt/projection to the still-gated default Auto consumer.
Its Red-only cycle and original test bytes remain preserved. A new cycle holds dispatch and verifies
actual Core receipt/restart APIs plus the real model projection after a typed admission. It does not
claim UI Auto execution. Consolidated applicability notes are in the ignored contribution evidence;
the final reviewer must inspect them alongside the frozen original task and all named cycles.

Stage 2 scope was independently checked against actual configuration. The turn now pins its originally
selected transport retry delays/ceiling and resolved inherited reasoning effort, including an absent
override, before first admission. Compatible snapshots restore those settings after profile changes;
older unbound snapshots adopt settings on first binding rather than inventing historical values.
Unobserved-provider usage is committed with each canonical response and rebuilt idempotently into
accounting on startup. A real Core restart fixture verifies recovery without generation; separate
SQLite migration/query fixtures verify additive run/turn ownership, filtering and deduplication.
Observed HTTP requests retain the same run/turn through provider wrappers. These focused checks pass;
the current owning aggregates and scoped independent review are still pending. Existing tool limits,
disabled-limit behavior, output reserve, recovery counters, model/engine/completion configuration,
input mode and elapsed reconstruction remain the contracts. This migration does not add new public
max-request, monetary, turn-token or total-age deadline knobs. Planning consumers and stricter evidence
policy stay in their existing stage 5/6 boundaries.

Contributor tooling changed independently during implementation. Continuation task
`unified-native-agent-loop-v2` retains the same owned product scope and approved design. The original
`unified-native-agent-loop` task and its original logs remain external historical evidence; their
ordering is not recreated or overwritten. Newly edited contributor-tooling files remain outside this task.

Stage 1 implementation: common observed handler is connected to streaming, fallback and context reset; digest interception is removed. Recorded regression cycle demonstrates the old failures and 10 passing focused tests after the change. Independent review and broader validation remain pending.

Stage 2 foundation: turn-owned `RunState` now survives native completion continuations and transport retries. A production orchestrator regression demonstrated four actual tool invocations with an incorrectly expanded ceiling of eight under a configured limit of two; the same test now records two invocations and the original ceiling. Completion/recovery policy extraction and full state consolidation remain pending.

Completion and evidence now live in `RunState`; the orchestrator derives its flags/summary from one record, and the coding completion policy is extracted as a pure Core policy. Production fixtures cover the barrier after accepted completion, including completion after the last allowed work round. Full recovery-policy consolidation remains pending. Portable validation prerequisites: add the already-imported SloppyA2UI product to the portable manifest, refresh its stale lockfile to the current manifest, and give the existing explicit-session test deterministic historical timestamps (its latest-session assertion previously depended on random ID order within one second).

Stage 3 reader foundation: optional typed runtime metadata round-trips without changing legacy creation metadata. Journal/cache/page reads retain physical order. Future event/runtime versions fail closed, including append preflight. Batches encode before writing and synchronize before returning. NativeJournalTests recorded the old failures and now pass. Projection checkpoints, start-marker recovery and the old-Core writer gate remain pending.

Stage 3 projection/recovery: SessionProjection reads atomic byte-bound journal snapshots and honors compatible checkpoints while retaining task/input/evidence/call provenance. Requested calls without a start marker get not-started outcomes; started or legacy calls without results remain unknown. Append preserves valid legacy EOF rows without a newline. Seven focused journal tests (including parameterized cases) pass. No production writer enables unified metadata yet; the old-Core gate and common-loop integration remain pending.

Stage 3 Core gate: optional nativeEngine preserves old-client updates and defaults. A storage-only native_v2 discriminator in both profile files rejects old Core readers; public runtime types remain native/acp. Marker preservation covers canonicalization, summary hydration and explicit legacy rollback. Paired activation verifies both synced files before readiness; partial writes do not grant readiness. Current unsupported unified admission fails before model/tool generation. Focused Core regressions passed, and the portable owning suite passed 18 tests. Standalone writer remains disabled because it bypasses the catalog gate. True step adapters/common loop are next.

Stage 4 contract foundation: separate optional ModelStepProviderFactory leaves existing ModelProvider witnesses/plugin boxes unchanged. Immutable value requests contain declarations, raw arguments, complete response/continuation/usage and typed failures. AgentLoop collects one settled stream, requires a start and exactly one final, rejects events after final, and treats deltas as presentation only. A scripted production RuntimeSystem test verifies explicit unified text generation uses this capability with zero legacy generation calls. Effectful pipeline, retry/context policies, real HTTP adapters and Core admission remain pending; this is not completion of stage 4.

Stage 4 pipeline foundation: AgentLoop now owns response/tool/response scheduling through typed journal and executor contracts. Full responses precede requested batches, and the Core executor must commit a durable start after policy/approval. Failed writes stop scheduling. ToolPipeline checks declared names and structural argument schemas; incomplete responses receive paired errors without effects. Focused runtime tests pass. SessionLoopJournal writes synchronized correlated records behind an injected writer guard. A fresh file-store test reconstructs opaque continuation and projects results in source order while retaining their physical completion order in JSONL. Concurrency, cancellation generations, recovery policies, real adapters and product admission are still pending.

Safe-read segments now execute concurrently using the shared ToolConcurrencyPolicy segmentation, with mutations and unknown/MCP/shell calls remaining barriers. Runtime tests demonstrate overlapping reads with an exclusive write between segments. A stopped generation is rechecked at the effect boundary and before continuation. Known late effect outcomes remain journaled and cannot schedule a new request. Immediate upstream request cancellation and durable run-state restoration remain pending.

RunState now owns cancellation handlers for the active loop/request tasks. Cancelling it terminates the provider stream, with generation checks preventing later callbacks from restarting the turn. Eight focused runtime tests (with parameterized cases) pass, including incomplete/inconsistent responses and malformed/schema-invalid arguments. A Windows incremental binary crashed after actor layout changes; the unchanged tests passed after a clean owning-package rebuild. Original crash/dump analysis logs are retained in contribution artifacts; no failed execution is counted as passing evidence. Durable state restoration remains pending.

RecoveryPolicy now permits only typed retryable transport/provider failures. AgentLoop retries a frozen step with a new attempt ID and attributes its persisted final/batch to the successful attempt. Turn-owned recovery counters bound continuations; default delay values match the existing reconnect schedule. Ten focused runtime tests pass after a clean rebuild. Retry state is currently in memory; persisted attempts/deadlines, context compaction and finalization recovery are not yet implemented. Cross-module incremental actor changes produced stale binaries on Windows, so subsequent cycles must invalidate the owning build or disable cross-module incremental imports rather than accepting those results.

First HTTP adapter: OpenAIOAuthModel implements ModelStepProvider without using its legacy generation/tool loop. A bounded, cancellable URLSession transport feeds a strict Responses codec. Raw arguments and ordered opaque output items survive replay; terminal output-limit responses retain calls without authorizing execution. Composite/context-limited providers forward the optional capability. Three URLSession contract tests (including cases) pass for one-request behavior, continuation, incomplete/closed streams and single usage attribution. Authentication-refresh, actual HTTP cancellation and JSON/stream parity still need explicit fixtures before pilot admission. New provider test commands disable cross-module incremental imports for reliable Windows invalidation.

OAuth contract coverage now includes exactly one forced refresh after HTTP 401, terminal repeated authentication failure, cancellation reaching the active URLSessionTask, and equivalent JSON/SSE final values. Six provider tests (including cases) pass. These are isolated HTTP fixtures, not live account/backend or rollout evaluation evidence. Core session admission remains disabled until the durable pipeline/product policies are integrated.

The shared pipeline now receives a typed completion candidate from product execution, commits its tool result first, then applies the candidate under the run generation. Cancellation or a failed result write prevents acceptance; remaining calls get durable skipped results. A committed finalizer returns its existing summary without another model request (within the at-most-one tool-free final step bound). Eleven focused loop tests pass. These common-loop rules still need the Core session bridge and durable restart/cancellation metadata.

RuntimeSystem now accepts AgentLoopServices for explicit unified execution. It prepares canonical journal history, refreshes instructions/declarations/scoped memory before each step, observes durable calls/results, and emits total request usage once. A real filesystem/JSONL fixture verifies full read content, no duplicate task text, correlation, ledger and usage through postMessage. Missing durable services reject declared tools before generation. Thirteen loop tests pass. Core admission is still closed; product access/approval integration, recovery/queue state and worker/standalone wiring remain pending. The local compiler reports -disable-incremental-imports as obsolete/ignored; touching unchanged owning test timestamps correctly forced client recompilation after API changes without modifying test content. Future commands should omit that ineffective flag and force affected client rebuilds when necessary.

Turn-state journal foundation: versioned snapshots record original run/turn IDs, generation, attempts, tool rounds, recovery counts, evidence, completion, elapsed time and pinned loop settings. Attempts are durable before provider requests, and work counters before effects. A fresh file-store regression restores the same turn after an authentication failure; a caller proposing a larger ceiling still cannot execute a second mutation. Fourteen loop tests pass. Readers validate snapshot versions and envelope identity. Durable input/cancellation queues, replay of outcome tails/unknown effects, pinned model/mode policy, configured deadline enforcement and Core admission still require implementation; this is not a completed restart feature.

Unknown-effect safety: a filesystem fault test demonstrated a duplicated mutation after result-write failure; the unchanged test now proves one effect across restart. Prepared requests derive unresolved started/legacy outcomes from the authoritative journal and block further mutations until owner reconciliation, while allowing declared safe inspections. Structured access/approval/loop stops now settle later calls as skipped and cannot generate a continuation. Terminal stop records survive snapshots. Sixteen focused loop tests pass. Product reconciliation/approval wiring and full cancellation persistence remain pending before Core admission.

Model identity now survives checkpoints and rejects silent model changes before a generation. An active checkpoint without a model identity stops explicitly rather than guessing one. Twenty-five loop/journal tests (including cases) pass, including unsupported snapshot versions through warm caches, pagination and append preflight. Explicit compatible model fallback transitions still need the routing policy bridge; this default guard does not implement fallback by inference.

Required completion and empty-answer recovery now belong to AgentLoop. Turn-owned counters and scoped durable instructions bound completion recovery; available work tools remain until the work ceiling, then only finalizers remain. Empty answers after tools receive one tool-free answer request, and unexpected calls cannot reopen execution. A hard budget stop precedes completion acceptance. Twenty-nine focused loop/journal tests pass in the recorded cycle. Core admission remains closed until its policy/approval bridge is connected.

Use small recorded Red/Green/Refactor cycles through the contribution runner. Behavioral fixtures cover effect counts, ordered call/result pairing, read barriers, output limits, persistence failures, unknown outcomes, completion barriers, cancellation, steering, queue races, compaction and restart. Provider fixtures cover terminal responses, transport loss, opaque continuation, usage and streaming parity.

Run owning suites before root Swift tests and release products. Run affected Dashboard/client/package checks and VitePress, followed by an independent review and runner completion verification. Missing supported-platform evidence remains a blocker, not a passing check. Do not remove legacy support merely to satisfy migration checkboxes. Live pilot solve-rate/latency/cost gates remain required before broad rollout.

Core execution boundary: exact durable-call identity, unknown-outcome checks, post-hook schema validation and approval/start integration now share the existing Core invocation path. Approval references the original call ID and rechecks policy after waiting; stale restrictions cannot authorize an effect. Recorded production filesystem regressions pass for success, failed start, cancellation and revocation. Native hard-timeout ownership and late-result persistence remain pending, so Core admission stays closed. Windows fixture prerequisite failures were retained as failed infrastructure attempts, not successful validation.

Effect-lifetime primitive: cancellation and monotonic deadlines return explicit non-retryable unknown outcomes while an uncancellable effect remains active. The actual late result is observation-only and cannot accept a completion candidate. Atomic native-result appends retain a known result even when a synthetic unknown placeholder races after it. Recorded filesystem/JSONL regressions cover cancellation, deadline expiry and both append orders. The Core executor now uses this primitive with a correlated late writer; session admission remains closed.

Core owned-effect integration: shared invocation returns a typed candidate while the legacy public facade preserves its scalar result. Current policy and start checks run inside the owned task before dispatch. Correlated late outcomes persist without candidate authority, and loop-guard correction cannot erase an unknown interruption. Cancellation now withdraws pending approval and settles its continuation, rejecting late approval. Four focused Core tests (eight cases) pass through the recorded cycle. The first 30ms active-effect fixture correctly expired during preparation; its incomplete cycle is retained, and the corrected 500ms fixture was recorded under a new Red with the approval cancellation regression.

Durable caller cancellation: AgentLoop refuses an already-cancelled caller before creating its operation, settles cancellation under the original IDs and awaits a stop checkpoint before returning. Run-level stopping snapshots do not invent a step identity. A real store/reopen fixture demonstrates no provider request after either pre-start cancellation or stream cancellation. Thirty loop/journal tests pass. Core run-control, durable queues/approvals and restart admission still need the full session bridge.

## Ownership

OAuth endpoint ownership: two real HTTP cases demonstrated reuse of the same opaque response items after changing the host or tenant path under an unchanged account/model. OAuth's provider identity now includes the configured endpoint digest, matching the other native HTTP adapters. Existing continuation validation rejects the changed scope before HTTP, with no extra routing layer. All31 provider/journal functions pass at Green. The original six failed assertions and both unintended requests remain recorded in Red evidence.

Disposable summary-cache boundary: a real JSONL outcome test with a directory blocking summary.json reproduced a failed durable append acknowledgement and failed paged history (five assertions). Derived-cache write failures now log and leave the synchronized result authoritative. Paging uses a validated canonical summary/control projection when its cache cannot be read or replaced; state-event selection is shared with cache serialization. Canonical file and metadata-validation errors remain throwing paths. All77 portable functions in five suites pass at Green. The initial test build's missing optional chain was corrected before valid behavioral Red; no assertions changed between recorded Red and Green.

Gemini usage provenance: an actual HTTP regression exposed26 missing-component/completeness assertions across API-key and Code Assist requests. UsageWireDecoder now unwraps the typed Code Assist envelope, includes Gemini system/part text in catalog attribution and links declared API call IDs through generated arguments, history and structured results. No-ID calls remain explicitly incomplete without invented links. All29 provider/journal functions pass at Green, including unchanged totals, actual wire-ID presence/omission, schema/catalog counts and successful result records. Runtime-generated synthetic IDs remain outside this wire observation layer.

Read-only compatibility readiness: broader Core validation first failed two warm-delivery assertions after a permission error during preparation of the second model step. An unchanged repeat passed all21 selected functions. Investigation found that every preparation rewrote both already-protected profiles. A deterministic regression then failed both modification-date assertions with live readers. Protection now verifies an installed pair and returns without writes; only protectionMissing permits activation, while I/O and malformed profiles still fail. All7 compatibility/session functions pass at Green. The original intermittent permission failure is retained as observed evidence; its precise cause was not established by the timestamp regression.

Gemini Code Assist slice: typed native transport settings now choose the OAuth route/envelope, bearer/client headers and an independent refresh callback. Project identity is captured after refresh and included in continuation ownership; a changed project fails before HTTP. Four JSON/SSE/project-change cases plus preflight rejection cases pass, with all28 provider/journal functions green. Core uses its proxy session for native credential/project requests, keeps resolved project state with the provider instance and never updates the legacy global caches on native refresh. Reusing that binding avoids a metadata lookup on every tool step; rebuilt provider settings resolve again. Core compilation/downstream tests are still required. The initial50-assertion Red established the wrong route/project behavior; after adding isolated-refresh data, an uncaught test error was correctly rejected as Red, then an explicit no-error assertion recorded valid Red. Periodic pauses retain all800 event assertions while eliminating the fixture's slow per-event Windows timers. Live backend and other migration gates remain pending.

Gemini API-key slice: original signed parts, ordered tool history, inline images, JSON/SSE finalization and thinking/cache usage now use a true single-step adapter. Partial/length-limited calls cannot become executable; exact API call IDs round-trip. Explicit low/medium/high effort uses the documented uppercase thinkingLevel enum without model-name heuristics. The Core native session uses the configured proxy without legacy global signature rewriting. All26 provider/journal functions pass at Green. A cancellation race exposed raw CancellationError from the run guard before the adapter error; public collectStep now normalizes that path to request_cancelled. The first build retained an old constructor reference on Windows; unchanged test timestamp invalidation corrected that prerequisite. OAuth Code Assist still requires its separate typed transport configuration before Gemini migration is complete.

Model-event backpressure: an actual SSE burst reproduced transport failure after257events in both OpenAI adapters. A shared asynchronous delivery helper now suspends the single producer when its256event queue is full, preserving ordering and the final response without increasing the queue. The unchanged800fragment regression passes for both adapters alongside existing cancellation fixtures (23provider/journal functions at Green). The first Red showed the intended assertions but its expected-expression matcher missed Swift Testing's rendered value; the unchanged repeat used the observed typed code and recorded valid Red evidence.

Preserve unrelated worktree changes. Expand the registered task's exact file scope before edits. AgentRuntime owns scheduling and typed state; PluginSDK owns provider contracts; SloppyRuntime owns journal projection; Core owns access, approvals and product policy. No effect executes in a provider adapter.

Ordinary Core Ask bridge: explicit unified execution now uses the real Core tool boundary and a canonical per-step journal. Immutable invocation metadata carries exact durable identities; awaited publication follows writes. Scoped mode/reference context does not repeat the user task, and UI-only final delivery does not duplicate model history. The same-process and fresh-store integration cases passed, as did the unsupported-provider admission regression (two test functions, three cases). The full portable suite passed 51 tests. Admission remains deliberately restricted until planner/router modes, queues, restart ownership and other consumers migrate. This is not completion of stage 5.

Completion crash gap: a durable outcome journal now preserves the typed product-policy candidate with the correlated successful result. A fresh reader checks original requested/start provenance, generation and pinned finalizer policy before recovering that authority. Scalar late results carry observation-only provenance and no candidate. The filesystem fault test first demonstrated a second effect after a result/snapshot gap; the unchanged test now proves no second provider request or effect. Thirty-one focused loop/journal tests pass. Full outcome-tail replay and product restart admission remain outstanding.

Busy Core inbox: a gated real Core post reproduced premature projection of a durably queued follow-up and an unintended shadow legacy request caused by repeatedly appending bootstrap. The unchanged production-path test now proves exclusion from the active turn, exactly one delivery under the queue UUID, four model steps and no legacy calls. Request preparation freezes the journal before awaiting pending IDs; bootstrap refresh replaces instructions without growing channel history. Three focused Core test functions (four cases) and all 52 portable tests pass. Explicit steering and durable run/approval recovery remain pending.

Engine rollback boundary: a gated real Core request demonstrated loss of an active result after a profile flag change and an incompatible legacy continuation of the same journal. Active preparation now follows the engine already pinned in RunState; the writer verifies persistent paired compatibility protection so actual outcomes can settle. New legacy runs reject non-imported native journal records. A fresh legacy chat still answers through its normal provider. Four focused Core test functions (five cases) pass with unchanged assertions, including one original task occurrence across the flag change.

Delivered-input retries: original native input IDs bind a versioned SHA-256 fingerprint of the effective submission. A terminal typed delivery record can be replayed read-only. The real Core warm/fresh-service test first showed three effects/turns after retry and changed-payload reuse; it now proves one start, one user row, one counted turn, unchanged journal bytes, no extra generation and explicit rejection of conflicting payloads. The optional replayed response flag prevents repeated Core post-turn side effects. Five Core test functions (seven cases) and all 52 portable tests pass. Unfinished accepted input currently stops explicitly; full interrupted-run recovery remains pending.

Executor coding slice: optional legacy/executor/separate planning configuration preserves existing defaults and planner-model values. Explicit executor policy now admits ordinary unified Build/Debug without a separate legacy generation. Real Core fixtures run an isolated Swift package build, require current-turn verification, settle a successful finalizer, and stop after three missing-completion recoveries. Debug input requests supply a validated live question ID to the durable completion barrier; later calls cannot execute. Four cases pass with unchanged assertions, alongside the existing Core session regressions (six test functions / eleven cases total) and the 52-test portable suite. A matching paused delivery marker supports read-only input-ID retries. Separate planning, Plan/Auto, workers/coordinators and remaining provider consumers are still pending; this does not complete stages 5 or 6.

Responses API-key slice: explicit Responses configurations now expose a true single-step factory under both existing selection settings, without changing default Chat Completions behavior. Four HTTP cases cover JSON/SSE, ordered opaque continuation, configured endpoint and bearer auth, output ceiling, one generation per step and one observed usage record per request. OAuth and API-key adapters share transport failure classification and stable cache-key digest logic; only API-key Responses sends max_output_tokens. Seven provider test functions pass at Green. Live endpoints, Chat/Anthropic/Gemini/Ollama and the final migration gates remain pending.

Chat Completions slice: the existing default API-key format now exposes a true single-step adapter sharing HTTP transport with Responses. JSON/SSE fixtures preserve indexed fragmented calls, invalid raw argument bytes, ordered continuation/reasoning, images, frozen output limits and usage after the terminal choice. Partial streams fail explicitly; length-limited calls retain a non-executable output-limit outcome. Cancellation reaches the real URLSessionTask for both OAuth and API-key Chat. Nine provider functions pass at Green. Common SSE framing is extracted during Refactor; provider-specific payload semantics stay in their codecs. Cross-format native fallback and other providers remain pending; legacy fallback settings remain available on the legacy engine.

Typed timeout observation: a state-level Red reproduced two false timeout observations from quoted error prose/unrelated code substrings and a missed owned-effect deadline. Exact protocol codes and the typed interrupted-effect timedOut flag now drive RunState, independent of message language. Six cases pass through actual tool-start/tool-finish state transitions alongside loop/journal regressions (32 test functions at Green).

Outcome-tail authority: the recorded filesystem result/checkpoint fault reproduced lost verification and a lost policy stop followed by an extra generation. Product-validated evidence now travels separately from untrusted scalar result data through AgentLoopToolOutcome into the journal envelope. A fresh reader verifies requested/start provenance, restores evidence IDs without charging counters again, and replays policy errors before any new request. Scalar late observations cannot supply that authority or erase a recorded stop. Three cases pass alongside loop/journal tests (33 test functions). One unchanged Green attempt exposed the old cancellation fixture's 200ms natural-finish race; the failed log remains, and an unchanged repeat passed. Correct its synchronization in a subsequent recorded cycle. Core now supplies typed verification through its existing classifier; the updated Core integration still needs downstream validation after these shared ABI changes.

Scalar-journal boundary: the low-level loop previously accepted a product completion after a scalar-only write, or silently discarded verification and continued. Two cases now prove retention of the known result, explicit durable_outcome_journal_required failure, no accepted completion and no continuation. Runtime's adapter preserves the same actual-result semantics before refusing authority; stopping runs await a state checkpoint when available. The in-memory test journal now genuinely records typed outcomes. The cancellation fixture uses a suspension stream rather than a natural 200ms finish, removing the observed scheduling race. All 34 loop/journal test functions pass at Green.

Ollama provider slice: the step factory now uses JSON/NDJSON chat with no tool scheduling, indexed calls and unique native IDs, preserved thinking/images/history, frozen output ceiling and exact cached-token accounting. Explicit reasoning controls come from a cached api/show probe: named levels match exactly, declared boolean controls enable thinking, unknown levels fail before inference. Native metadata queries use the common bounded delegate transport to avoid completion-handler loss of fragmented URLProtocol bodies; legacy metadata transport behavior stays unchanged. Thirteen provider functions pass at Green (Ollama cases include JSON/NDJSON, thinking controls, partial/length limits, unsupported level and actual generation cancellation). Initial TokenUsage property typo and diagnostic failures remain failed logs, not claimed evidence. Native HTTP requests now serialize keys consistently for stable schema prefixes. Live Ollama/provider behavior and remaining formats still need their migration gates.

Anthropic Messages slice: one JSON/SSE generation now returns ordered signed/redacted thinking blocks, full tool input, terminal/length disposition and cumulative token/cache usage without executing tools. Native auth uses the existing API-key/OAuth/proxy header contract, preserves configured transport and skips legacy auth rewriting; credential refresh precedes generation and auth failures stop before HTTP. Canonical projection restores an optional typed tool-error flag for API is_error without interpreting text. Twenty-one provider/journal functions pass at Green, including real store reopen, OAuth preflight and cancellation. Request effort uses adaptive thinking on compatible models; unsupported continuation binding extensions fail rather than lose state. Live models/accounts, Gemini, other consumers, context/policy migration and final platform/review gates remain pending.

HTTP backpressure correction: the broader suite exposed a real valid-response failure from the 64-event HTTP queue. A direct Red delivered 128KiB in 17-byte callbacks to a slow consumer and retained only1088bytes before http_buffer_exhausted. The transport now provides a pull-driven single-consumer sequence with coalesced buffered bytes, preserving the existing32MiB total ceiling. Callback handoff is synchronous to its private queue, while network cleanup runs outside that handoff; cancellation ownership is installed before URLSessionTask.resume and remains synchronous through a small per-request lock bridge. All22 provider/journal functions pass at Green, including the slow consumer and actual cancellation. An initial stale Windows test object linked against the old internal return type; touching unchanged test timestamps fixed the compiler prerequisite without editing assertions.

Accepted-input recovery slice: Core resolves delivered and unfinished submissions separately under the original payload fingerprint. A fresh compatible journal restores the latest same-run/turn checkpoint, model and limits, reuses the original user message/attachments and skips duplicate scoped context. Unsafe newer user input or missing/incompatible state stops explicitly. An actual filesystem result/write-gap fixture confirms one effect, one user row/count and the original identities/result despite a changed file. All24 selected Core functions in three suites pass at Green. Remaining crash boundaries, paused input, approvals and steering still require migration. Broader usage failures remain recorded and outstanding.

Tokenizer resource portability: existing production reference tests reproduced14 failures because CRLF vocabularies yielded no ranks and silently selected estimation. Parsing now splits on newline characters, including CRLF, without changing vocabulary hashes, model allowlisting or expected reference counts. All13 owning functions pass at Green, including code/JSON/Unicode fixtures. Direct Windows URLProtocol configuration-header observation is a separate unresolved platform behavior, with its failures retained.

Recovery-boundary extension: the actual filesystem fixture reproduced21 failed assertions across complete initial acceptance, pre-persisted inbox input and a settled Ask response before presentation. Initial acceptance now writes the resolved model/config checkpoint last, after all original input/context records; both execution and acceptance use the same native configuration/chunk helpers. Pre-persisted input is linked through its explicit acceptance identity. Settled canonical end-turn responses publish through normal Core finalization without a generation. All25 selected Core functions in three suites pass at Green. Refactor moves cleanup before throwing restore guards. Interim review still identifies partial acceptance prefixes, distinct queued follow-up recovery and current-provider admission before terminal replay; these remain open alongside active-ID ingress and post-presentation accounting. No full restart-completeness claim is made.

Active-input delivery: the gated production Core test reproduced three defects (duplicate inbox receipt, original ID pending and missing original task in the next model request). Core now registers an immutable input identity/fingerprint before execution awaits and checks identical active IDs before the busy queue. A saved active input returns its existing read-only receipt; a changed payload or unpersisted input is rejected. Only the original owner removes its registration. Delivery inspection is separate from cold recovery's later-user guard, and projection never excludes its own turn ID because of an older duplicate queue entry. All26 selected Core functions in three suites pass at Green, including distinct follow-ups and coding modes. Test declarations use typed Generable arguments instead of force-try schema construction. Partial admission, durable queue recovery and other previously listed boundaries remain pending.

Settled delivery without a current provider: initial Red reproduced three failures for a saved end-turn response. Expanded Red added a real accepted session.complete through the Core pipeline and reproduced six failures across both saved terminal forms. Generation admission now follows restoration; settled snapshots publish their saved response or accepted completion without a provider factory or model request. Incomplete runs retain model/capability checks, and unsupported consumer kinds remain gated. Accepted retries skip fresh semantic routing. Recovered completion metadata and pause identity remain typed. All26 selected Core functions pass at Green, including five recovery-boundary cases and required coding completion. This does not yet make completion-result tails, cancellation delivery, queues or partial admission fully recoverable.

Cross-platform usage ownership: real Linux execution reproduced the same five missing-accounting assertions as Windows, and a new reused-request fixture exposed attribution to the wrong session. Public URLProtocol.task.delegate retains the session delegate on both tested FoundationNetworking versions. The observer now resolves that typed owner first and retains the existing header path for native delegate transports; it no longer requires configuration headers during protocol selection. No private API, thread-local current channel or dynamic protocol classes were added. All95 Linux portable/SDK functions in seven suites pass at Green. Refactor preserves sorted request serialization when enabling streamed usage. The isolated harness copies and hashes actual source/test/resource bytes and adds the owning SDK suites; original dependency pins remain untouched. Supported full-Core/platform and live rollout gates remain outstanding.

Durable queue ownership: a real Core restart fixture reproduced nine failures when startup delivered B before unfinished A. The journal now retains A's input identity until terminal presentation; the scheduler and the post-approval drain boundary both check it. A's explicit retry bypasses only the waiting queue, while an active in-memory owner remains exclusive. Recovery excludes only queued inputs that have never acquired acceptance metadata. All84 selected Windows functions in11 suites pass at Green. Refactor indexes terminal identities once to avoid repeated full journal scans. Earlier Windows runs retain a Foundation heap-crash dump and two nonpersistent existing-test failures; added boundary diagnostics and a full-root Linux source-verified check investigate these rather than treating them as resolved. Interim independent review additionally identified fork history authority, older delivered input retry during a different active turn and partial queued-payload equality; those fixtures/fixes remain pending, along with the already recorded admission/input/approval/context/provider/consumer/rollout work. No migration stage is marked complete.

Linux root validation prerequisite: a source-hashed copy of the unchanged root package compiled production modules, then could not compile shared test support because CoreHTTPServerTests.encodedMeshEnvelope was declared inside !os(Linux) while authenticateRelayConnection used it outside that conditional. The identical helper body is moved into shared scope, preserving all assertions and platform test selection. This is a compilation prerequisite, not behavioral Red evidence; the original failing log remains native-loop-linux-root-core.log. No Linux tests from that failed build are counted as executed/passing. The existing95-function portable/SDK Linux result is separate. The identity cycle's actual Red reproduces23 assertions across fork ownership/provenance, read-only delivered retry during another active task and seven queued-payload mutations; all preexisting collaboration cases pass. Reader changes classify fork provenance as historical before the fork writer is validated. Platform checks rerun against the updated source copy.

Historical identity slice: all100 selected Windows functions in12 suites pass at Green; actual Linux portable/runtime/provider/accounting suites pass95 functions in7 suites. Full Linux Core now compiles and executes the same100 selected functions after the shared HTTP test-helper prerequisite. It reports two gate/polling failures, not an overall pass. An isolated repeat passes the delivered-retry case but still observes the existing follow-up count before its inbox runner finishes. Replace polling fixture synchronization in the next recorded cycle, without weakening assertions or serializing the suite. Independent re-review confirms the three primary fixes but finds live-only filtering gaps in inbox message dedup, peer worker classification and Auto route restoration; add production-path cases before correcting these. The historical contract and migration remain in progress.

Live versus historical control: the fresh cycle replaces five-second test polling with explicit gate-arrival/operation-completion signals and awaited inbox runners; existing behavior assertions remain unchanged. Windows and Linux each execute102 selected functions and reproduce exactly eight assertions across the two new history scenarios, with the100 earlier cases passing. A copied UUID must not suppress a newly queued user event or remove the historical task from another active context. Worker classification and unfinished Auto routes must read live records only, including when a historical completion follows a live route. The fixes apply live-only filtering at persistence, projection/bootstrap and the two policy readers. Added agent-read failure diagnostics preserve underlying unexpected errors before public mapping; the earlier nonpersistent Windows profile/read failures are not declared resolved by this test synchronization change.

History control Green: Windows passes102 selected functions in12 suites (56.076s); Linux's unchanged full root package passes the same102 functions/12 suites (50.026s), and the actual portable/runtime/provider/accounting suites pass95 functions/7 suites (3.214s). All tests run with their normal parallel execution. The source-verified Linux copies keep the original worktree pins unchanged; only their local Linux graph is resolved. Prior failed Windows/timeout evidence remains archived and is not overwritten as a success. Refactor updates the public guide's verified history behavior; no additional production restructuring is needed for this slice. Full suite/release/client/platform/live rollout and final independent review remain required, together with admission commits, durable pause/approval/input queues, cumulative budgets, remaining consumers/providers and the other unchecked migration work.

Presentation identity follow-up: independent review found that allowing historical/live rows to share nested message.id loses content in existing Apple-client reconciliation, can duplicate transcript keys on reload, and makes forkBefore/forkThrough choose the wrong event. The refinement gives copied messages independent UUIDs while preserving source event provenance. A source UUID can identify a fresh input in the destination; an actual historical presentation UUID remains reserved and cannot be acknowledged as a new direct, peer or UI input. Windows and Linux each reproduced12 assertions in103 selected functions before the fix, including unique IDs, repeated fork boundaries and all three ingress paths. This replaces the implementer's earlier permissive duplicate-ID choice within the approved stable-identity contract; no user-approved requirement required duplicate presentation IDs. Prior evidence is preserved with its actual expectations and dates. The Dashboard's historical pending indicator is a separate remaining view-projection fix.

Presentation identity Green: Windows passes103 selected functions in12 suites (34.089s); the source-verified Linux root passes the same103 functions/12 suites (15.591s). Copied nested message IDs are new UUIDs, and immediate source event provenance is retained. Historical presentation IDs are rejected at all three ingress boundaries before acknowledgement, durable enqueue or generation. The new tests preserve source-UUID fresh-input behavior while proving unique presentation IDs and correct subsequent fork cut points. Refactor updates the article with this distinction. This is one completed behavior slice within the still-unfinished migration; the Dashboard historical activity indicator, admission/recovery/input ownership, remaining providers/consumers and release/evaluation/platform gates are still pending.

Dashboard activity slice: first extract the three existing helpers unchanged into the feature module and verify typecheck/Vite build; this preparatory movement is not behavioral Red evidence. The actual production-module tests reproduce10 failures in11 Node tests. Historical calls/results/terminal states cannot alter current pending activity; explicit result correlation settles the correct invocation and an orphan link cannot consume another call. Legacy results without a correlation retain FIFO behavior. Green passes all11 tests, Dashboard typecheck and build (24.67s). Node's initial default spec reporter was not recognized by the runner; that blocked record is retained, and the unchanged Red uses explicit TAP output for executed-test counting. No CSS, layout or visual identity change is introduced. Supported Swift CLI separately executes and passes all6 existing A2UI action tests (4.446s); an earlier direct unknown-extension binary invocation produced zero test output and is not accepted as evidence.


Atomic admission prefix: the corrected ISO8601 filesystem fixture reproduces22 assertions across the two new valid-prefix cases on Linux, with103 selected functions in12 suites executed. An earlier Windows run failed only because the fixture used the wrong date decoder; it is preserved and superseded, not counted as behavioral Red. Initial admission now stores the run snapshot and all turn-context chunks in the first complete record, whether that is a new user row or a marker linked to an already-persisted inbox row. Legacy standalone instruction records remain readable. Projection emits the user before scoped context, and historical copies grant no runtime instructions. Linux Green passes103 functions/12 suites (21.265s), and Refactor passes103/12 (27.410s); Windows validation is running separately. The full TDD state is archived as native-loop-stage5-atomic-admission-evidence.json. Independent interim review confirms these valid-prefix mechanics but identifies two additional P2 defects for the next recorded cycle: physically early queued user rows precede the previous response in model projection, and a compatible checkpoint may discard pre-persisted admission or standalone scoped instruction markers. Neither is waived, and no migration stage is complete.


Projection ownership slice: real Core fixtures reproduce4 assertions in103 selected Linux functions/12 suites: queued B appears before A's final answer and away from its own context, while a compatible checkpoint removes both active admission and legacy standalone context. The model view now moves live queued users to their first accepted input boundary without rewriting physical journal order. Checkpoint retention protects scoped instructions for the active run/turn. Linux Green passes103/12 (25.922s), Refactor103/12 (27.850s), and the separate source-hashed portable/runtime/provider/accounting suite passes95/7 (2.713s). TDD state is archived as native-loop-stage5-input-projection-evidence.json. The previous Windows atomic-admission run has two fault-setup assertion failures, with all recovery assertions passing; it is not an overall pass. A standalone Windows file-operation probe succeeds, so the fixture now blocks the journal immediately after moving it, before slower prefix truncation, and reports exact setup errors. The corrected full Windows check is running. Interim re-review closes the two original projection cases but finds a composition P2: a later run's checkpoint may retain B's user and A/B answers while discarding B's admission boundary, restoring the old order. Add that actual stored-checkpoint regression in the next Red cycle; no overall approval or stage completion is claimed.


Completed-input checkpoint composition: the new real-store checkpoint fixture reproduces one ordering assertion in103 Linux functions/12 suites. Retention now keeps the first live admission boundary of every retained live user, so the model view can still order a completed queued input after compaction by a later run. Green passes103/12 (35.231s). Interim independent re-review confirms the composition fix without overall approval. The current Windows projection run failed only three fault-setup assertions; expanded diagnostics identify ENOENT at the backup path. A standalone executable reproduces the exact Foundation FileHandle(forWritingTo:) failure at264 characters, while fileExists/Data read succeed; all operations pass with a short name (native-loop-prefix-path-probe.log). The fixture now uses a short unique backup filename. The earlier block-first synchronization change remains useful but is not presented as the cause of that ENOENT. Corrected Windows fixture validation is pending; no failing Windows result is relabeled a pass.


Core-generated input ownership: the gated Core fixture now retries the user ID observed in the journal both when the caller supplied it and when Core generated it. Linux Red executes103 functions/12 suites and reproduces exactly two assertions for the generated-ID case: a queued receipt instead of replay and a self-enqueued input. Core now assigns an omitted unified UUID before active-owner registration and passes it unchanged to journal admission. Green passes103/12 (16.950s). Legacy and ACP ID behavior are preserved. The prior completed-input checkpoint Refactor passes103/12 (22.712s), its full TDD state is archived as native-loop-stage5-retained-input-evidence.json, and docs build passes. Corrected short-path Windows fixtures remain pending supported execution, not waived.


Provider-free accepted completion: a filesystem fault after the authoritative completionCandidate result, before the settled checkpoint, reproduces3 Linux assertions with the current step capability disabled. Core now asks RunState to settle only a restored finalizing completion with matching generation, no active effects, no stop and no caller cancellation, then persists the settled checkpoint before presentation. Linux Green103/12 passes21.565s and Refactor23.773s; full state archived as native-loop-stage5-completion-result-tail-evidence.json. A separate actual finalizing-checkpoint fault reproduces the same3 assertions because reconstruction normalized accepted completion back to preparing. RunState reconstruction now preserves terminal intent as finalizing when completion exists, while explicit stopping/settled phases remain unchanged. Green passes103/12 (26.107s). Interim review finds no generated-ID defects but identifies another P2: durable unscoped interrupt can be ignored during completion-tail replay. That cancellation boundary, old-format reader support and provider-free interruption receipt need the next recorded fixtures/fix; they are not waived by completion recovery. Corrected short-path Windows validation and full migration gates remain pending.


Durable interrupt recovery: the actual current Core control API and a saved old-format unscoped control each reproduce resurrection of Done after a completion result. Red executes103 Linux functions/12 suites with11 assertions across metadata, terminal status and replay counting. The journal reader now binds legacy typed controls to the live accepted input before restoring completion authority. New unified controls cancel the active or durably unfinished owner, store a stopping checkpoint in the first control record and recheck the writer guard before acknowledgement. The terminal presentation carries the same run/turn and cancellation generation; fresh retries return it read-only. Stopping restoration needs no current provider and never forwards the old completion as a successful product outcome. Green passes103/12 (34.300s). Generated-ID and completion slices remain independently reviewed only in their stated boundaries. A self-found composition issue remains: the idempotent cancel guard can skip still-registered child handlers after a policy stop. Add the owning primitive regression/fix next; do not waive it or present cancellation as fully complete. Corrected Windows and final platform/rollout checks remain pending.


Cancellation handlers after policy stop: the owning RunState regression registers child cancellation, enters a typed deadline stop and cancels twice. Portable Red executes96 functions/7 suites and reproduces2 missing notifications. Cancel now advances generation only when entering stopping, but always drains/removes remaining handlers. Green96/7 passes2.744s and Refactor passes; full state archived as native-loop-stage5-stop-handlers-evidence.json. Independent review closes the original durable-interrupt reader/control defect, but identifies a separate P1: Core awaits controlSession before canceling queued entries, allowing A's defer to schedule B during cancellation. The next fixture must gate an actual awaited Core control boundary; the asynchronous control append observer is not a valid barrier. Keep new ingress and drains blocked until the control scope settles, capture preexisting queued IDs so later input survives, and cover awaited approval/drain interleavings. Windows recovery/cancellation aggregate is currently running; its supported result remains pending.


Control barrier: the actual Core dispatch seam reproduces11 assertions in104 Linux functions/12 suites: queued B starts before interrupt settles, and later C starts immediately or is misclassified. A per-session scoped barrier now covers ingress, scheduling and drains before/after awaited approvals. Target selection is shared/frozen; overlapping controls use depth; only IDs queued at admission are cancelled. Green104/12 passes36.199s and Refactor24.096s (native-loop-stage5-control-barrier-evidence.json). New independent findings require the next slice, not overall approval.

Admitted task and partial tree failure: actual Core preparation/caller cancellation and a child-journal directory fault reproduce6 assertions in106 functions/12 suites. Core now owns an admitted execution Task across preparation and actor dispatch and forwards caller cancellation. Preparation and orchestrator checkpoints recheck Task cancellation. Typed cancelled outcomes cannot render Done. Per-target control UUIDs identify exact durable controls; error-path cleanup cancels old queued IDs of successfully interrupted targets before barriers release. Green106/12 passes34.757s and Refactor passes (native-loop-stage5-admission-control-evidence.json). This does not yet implement canonical queued-input lifecycle, cross-file cancellation roster/restart windows or removal of all legacy owners.

Pending-input skip: interim review identifies cancellation occurring before the orchestrator's unanswered-input skip. The actual Debug fixture now pauses at the awaited finalizing journal checkpoint after planning.request_input and verifies that default interrupt does not cancel that real delivery task or change its generation. Red has3 expected new assertions plus3 failures in the preexisting three-second branch-usage wait. The unchanged branch-usage test passes isolated on the same binary (1.777s); no fixture/assertion is weakened. The cancellation callback now runs synchronously inside Orchestrator only after its skip decision, with captured Task handles and after setting the interruption flag. Green passes all106 functions/12 suites (21.119s), including branch usage. The original failed Red is preserved. A supported Windows aggregate before the new barrier/admitted-task slices passes103/12 (45.965s), including corrected short backup paths and all prior recovery/cancellation cases; it is not evidence for subsequent source edits.


Terminal delivery ownership: the real restored-settled completion fixture reproduces exactly two behavioral assertions in98 portable/SDK functions across7 suites. Child work now waits for ownership registration; settled completion delivery retains cancellation ownership without authorizing a new request. Fresh-scratch Green passes98/7 (2.659s). The initial incremental Green crashed in the preexisting stop-handler cancellation test; its log is preserved and the cause is unproven. Independent scoped review finds no production defect but requests combined restored-settled cancellation coverage. Earlier terminal-cancellation fixture correction remains documented in its explicit TDD exception; no retrospective phase ordering is claimed. All migration stages remain unfinished.


Storage v3 reader foundation: real paired profile fixtures reproduce2 assertions in108 selected Linux Core/SDK functions across12 suites. Current readers now normalize native_v2/native_v3, reject unknown discriminators explicitly and preserve the maximum supported marker across companion files during ordinary edits and explicit engine rollback. Green108/12 passes41.910s. This ships readers only; minimum-version writer authorization and lifecycle event writers remain pending, and no migration stage is complete.


Canonical input reader foundation: real JSONL fixtures reproduce9 assertions in100 portable/SDK functions across7 suites, including silent discard of malformed/future input envelopes without runtimeMetadata and rejection of a supported v3 queue. Typed input transitions now preserve immutable first context, separate delivery from execution disposition, and validate chain identity/admission ownership before append. Model and recovery transcript views exclude never-admitted inputs while raw history remains visible and untagged legacy context stays compatible. A fresh-scratch Green passes100/7; the initial aggregate crashed in Linux FoundationNetworking configuration mutation and remains failed evidence. A separate native probe confirms configuration getter aliasing; its deterministic isolation regression/fix is next. No v3 lifecycle writers are enabled yet: paired minimum-version activation, full source fork/import eligibility, materialization verification, canonical inbox rebuild and product integration remain pending.


HTTP configuration ownership: a deterministic real observed POST reproduces5 assertions in101 portable/SDK functions across7 suites. Linux configuration getters alias the injected base; the new implementation takes checked owned copies for observer setup, forwarding and Anthropic protocol removal. Forwarding applies preserved caller headers without exposing internal accounting headers. Public provider factory contracts remain throwing as before; the migration's new usage helper now propagates an explicit copy failure instead of force casting. Green101/7 passes2.911s. Existing concurrent attribution tests remain included. The earlier signal11 is retained; the probe and regression establish mutation, not its causal connection to the crash. Reader review separately identifies image-budget filtering and first-context/admission-generation binding for the next recorded slice.


Reader review corrections: the actual image-loader and first-context/admission fixtures reproduce14 assertions in104 portable/SDK functions across7 suites. Eligibility filtering now precedes image loading. First context is structurally bound to its stored user, normalized display text (except typed UI presentation), ordered attachment refs, peer/UI provenance, references and UI support. First owner acquisition requires an exact generation; later generation metadata does not rewrite immutable admission ownership. Green104/7 passes. Full historical copy/materialization/writer activation integration remains pending.


Minimum-version writer gate: the real Core append fixture reproduces4 assertions in110 Linux Core/SDK functions across12 suites: v3 writes previously succeeded with v2 profiles or partial activation. Both Core file-store instances now inject the same version-aware append/rewrite guard. It checks the maximum existing/new journal version; rename/promote also require compatible protection. Catalog activation can explicitly upgrade/verify both synced profiles to the required supported version while ordinary writes retain the maximum marker. Generic APIs cannot bypass it. Green110/12 passes53.178s. Core factory/provider and all newer protocol code are included in this owning aggregate; it is not the full unfiltered root/platform/release/client suite. Canonical lifecycle writers remain disabled until capture/admission integration.


Empty attachment distinction: the actual persist/reopen fixture reproduces2 assertions in105 portable/SDK functions across7 suites. Explicit empty inline data now creates a zero-byte attachment, while absent data retains no file reference; all inline attachment writes synchronize before returning. Green105/7 passes. This prerequisite does not yet implement digest-bound capture/materialization or canonical queue reconstruction.


Canonical capture/admission slice: the actual busy Core fixture reproduces12 assertions in111 selected Linux functions/12 suites. Queued user records now atomically contain normalized original request fields, ordered blob refs/decoded-byte SHA256 and UI/peer context; first admission retains that identity and assigns its immutable owner. New direct unified admissions use the same v3 envelope. Product terminal/paused delivery is a separate lifecycle transition. Blob reads are scoped to the owning session's resolved assets, bounded by stored actual byte count, and verified by digest before admission. The existing SHA256 implementation is shared in Protocols with a compatibility wrapper for plugin archives; empty/abc vectors are exercised through real captured attachments. New v2 fingerprints normalize base64 bytes and preserve original upload metadata; old v1 accepted identities still use exact original serialization. Green111/12 passes56.375s. Initial aggregate fails only the preexisting3 branch-usage wait assertions; the same binary isolated passes2.194s, and the unchanged aggregate then passes. Original failed log retained. Durable queued cancellation/failure roster, cache-independent reconstruction, historical copy eligibility, UI semantic projection and final independent review remain pending; all7 stages remain incomplete.


Peer preparation binding: a corrected real delegated-scope fixture reproduces35 assertions in112 selected functions/12 suites for plain,/build,/debug,/auto peer messages. Canonical capture now pins the prepared execution request and an optional original sourceRequest; only command text/mode may differ, while identity/model/attachments/authority fields remain equal. Both participate in new v2 identity; retries retain the raw source payload. All4 peer cases pass before and after correcting a separate existing accounting fixture. Two initial owning Green attempts fail only that fixture's3 polling assertions and remain preserved; no untouched-full-suite cycle is claimed. Accounting now waits for the matching Core consumer operation, retains exact300/120 plus router assertions, and has a cancel-aware60-second failure watchdog. A completion signal acknowledges the attempt, not SQLite commit. Full Green112/12 passes62.294s and Refactor59.565s. The task's explicit TDD exception identifies changed broader fixture provenance. Durable queue cancellation/failure, cache rebuild, forks/imports, full native-consumer/provider migration and final gates remain pending.


Atomic queued cancellation: the real valid-prefix/cache-removal fixture reproduces6 assertions in113 Linux functions/12 suites. Core captures canonical queued identities at the control admission cutoff and passes the pinned roster with the frozen targets. Orchestrator rechecks identity/current disposition before placing cancellation transitions in the FIRST runControl JSON record beside the stopped run snapshot; already admitted/settled preparations are not rewritten as queued work. Canonical never-admitted eligibility now drives the later-input conflict guard independently of the inbox cache. Fresh Core with only that prefix and no inbox.json retires A provider-free, replays cancelled B without recreating it, and runs C without B in model context. Green113/12 passes62.444s; the earlier Green compilation failure was a missing module import and remains blocked evidence. Never-admitted failure transitions, cache reconstruction, legacy queued-context migration and remaining full design scope are not complete.


## Current consumer implementation block (2026-11-05)

The preceding settings/accounting boundary passed 159 Core functions in 14 suites (64.237s),
109 portable functions in 7 suites (3.412s), and VitePress (20.65s). Later consumer changes below
require fresh affected checks; these earlier results are not a final full-profile report.

Mock and Claude Code now expose the step contract. The actual Claude CLI/admission fixture checks
one generation, signed history, raw arguments, usage, output limits and foreign-continuation rejection.
Its focused cycle passes two functions including two Claude cases. No live-account claim is made.

Ordinary Plan, separate/inherited planning and Auto now use the common owner. A tool-free planner
checkpoints the parent attempt and commits its response/accounting with bounded executor context;
a complete saved response can rebuild the instruction after a partial batch. An accepted Auto route
changes completion policy after its durable result without replenishing budgets. Ten coding cases
passed through Auto, including actual Swift builds and exhausted missing-completion recovery.

An answered native question resumes the same run and user turn in a new generation. The atomic
response retains settings, work, evidence and original context. Duplicate answers replay the original
receipt, and unfinished answered inputs can be reconstructed from the journal. Eleven coding cases
passed before additional fresh-Core and duplicate-answer coverage was added; that additional
coverage and the owning aggregate are pending. An actual peer-conversation regression now passes
for explicit empty scopes: no schemas and no Core invocation. The legacy allowlist API retains its
empty-means-clear contract; delegated consumers use an explicit scope API where empty permits no tools.
These blocks do not assert whole-stage completion.

### Core worker and coordinator continuation (2026-11-05)

Core now admits explicitly unified delegated workers and long-chat coordinators under profile-v4
protection. Worker completion is a durable `agent_delegate.finish` outcome with an exclusive barrier;
missing completion keeps original recovery budgets. Canonical settings retain tool scope, base policy,
working directory and filesystem roots. Missing saved authority blocks both contracts, and current
policy is rechecked before effects. The corrected real-build fixture passes fifteen mode/worker cases,
including a fresh-Core question answer that retains worker ownership and resource context. Its initial
combined worker cycle remains incomplete because a fixture sent a field from the ordinary finalizer;
corrected coverage is explicitly post-implementation.

Coordinator repair and factual report review now execute through the common owner. The original
three-case Red/Green checks actual status, actual persisted delegation and the two-pass handoff limit,
with one run and no legacy model calls. A later corrected-verdict/fresh-reader assertion is additional
coverage and must pass in the owning aggregate. The independent reviewer remains waived by the user.
Remote HTTP/Console/Mesh step contracts are implemented; focused HTTP/auth checks and Linux Console
fixtures pass. Actual Mesh client and Windows Console evidence remains unavailable/failed, as recorded
in the guide and retained logs. These changes do not close all of stage 5 or remove the remaining
standalone, control, derived-work, compaction and rollout requirements.

Coordinator notifications now retain their actual persisted system source. Native reports pin that ID
and a content fingerprint, expose no tools, create no user task and use one shared run for the report
and factual check. Legacy and unified notification cases pass unchanged after the fix; later durable
source replay coverage must pass in the next Core aggregate. Typed auxiliary response metadata also
permits hidden planning/report-review usage to be committed with its response without exposing it in
model history. Its two-case file-store Red/Green passes. Memory checkpoint preparation now uses
canonical admitted semantic inputs in journal order; its real queue/cancellation file-store regression
and existing recent-correction check pass. The portable aggregate passes 110 functions in seven suites.
Core owning aggregates remain to be refreshed after these changes. Derived scheduling, standalone
entry points, control ownership and other previously listed requirements remain open.


### Durable background memory continuation (2026-11-05)

A typed derived-source reader now retains the completed parent owner and separates foreground and
internal model projections. Its real file-store Red/Green passes one function. Automatic native memory
uses a background completion contract, its own common RunState/ToolPipeline and the parent canonical
journal; no parallel private history store was introduced. Source, model, static tool scope and resource
authority are pinned. Ordinary history and paged history hide internal records while raw storage retains
effect/reconciliation and usage records. Foreground admission and interrupt cancel registered derived
runs; source and policy are checked after approval before dispatch. The actual Core Red/Green passes
one function, including fresh-file settlement and unchanged foreground history. The portable owning
suite subsequently passes 111 functions in seven suites (4.572s).

Public manual-checkpoint outcome and real document-write cases are the next validation slice. Startup
resumption/deduplication of derived jobs, other derived consumers, standalone, remaining controls and
projection budget/compaction remain open. All seven overall stages remain unchecked; no final
platform/profile/rollout result or independent final review is claimed. The user waived further reviewers.


Manual native checkpoint completion now reports its real outcome through the existing public API.
The corrected three-case Red/Green passes: manual success, provider authentication failure without
resetting source counters, and a real user-scoped MEMORY.md write with paired start/result and filtered
pagination. Two earlier fixture attempts read the wrong document scope/trailing-newline representation;
they remain incomplete cycles. The final cycle reproduced only the real manual API defects before the
production fix. Its initial Green had a Swift Sendable capture error, retained before the unchanged
successful Green. The earlier guide build passes 19.91s; the latest public API paragraph needs refresh.


### Explicit embedded host continuation (2026-11-05)

SloppyRuntimeHost now supports explicit `.unified` engine selection; its default remains legacy.
Unified data uses an isolated native-agent-v1 store and verified format marker, outside paths that an
older host enumerates. Shared input capture now lives in SloppyRuntime and Core retains a typealias;
there is no second fingerprint/materialization implementation. The host uses canonical admitted input,
pinned model/budget/workspace, shared RunState/ToolPipeline, durable starts/results and fallback usage.
Real project write/build and legacy isolation pass the native-portable-host cycle. Restart Red/Green
also passes three cases: saved terminal delivery without credentials, read-only rejection of a started
unknown effect, and future marker rejection. Missing terminal receipts are synchronized before return.
The current portable owning suite passes 113 functions in eight suites (4.555s).

The first broad Core memory aggregate failed only its new one-minute watchdogs: 50 functions in seven
suites, 22 issues after110.779s. Cancellation at those caps caused downstream expected-result failures.
Original fixture bytes/logs are retained; derived/effect harness caps are now three minutes, with every
behavioral assertion and production deadline unchanged. A later focused cycle separately reproduces
and fixes duplicate full memory context (two copies -> one). Core owning rerun is still required after
shared capture extraction and the current shutdown slice. The embedded follow-up queue/controller,
additional restart/cancellation cases and Apple platform execution are not claimed complete.


### Derived restart and request budgeting (2026-11-06)

Fresh Core now restores an unfinished matching background run instead of creating a replacement.
The actual known-result prefix regression passed Red/Green: one run, two attempts, one work round,
old result in model history, no repeated MEMORY.md mutation. Its internal channel/cache scope derives
from durable run identity. Later changed-override/cache-affinity assertions are post-implementation
coverage in the next owning run. New background jobs preserve the existing explicit override/current
selected model; unfinished jobs keep their saved choice. A separate override Red/Green verifies the
request and stored model while retaining original foreground provenance. Shutdown blocks new derived
admissions before awaits and cancels registered runs. Autodream failure propagation/retry passes its
actual two-pass regression. No startup scan/controller for all outstanding derived jobs is claimed.

Native context budgeting is implemented before beginRequest, after final schema narrowing, with the
existing configuration switch, provider/catalog/default limits and output reserve. Its real embedded
host Red/Green passes enabled/disabled cases and verifies zero attempts/effects for impossible input.
The original public AgentLoop initializer is retained. The first full portable run crashed because stale
callers used the old stored layout; recompiling unchanged mirrored test callers produced a complete
115-function/eight-suite pass (5.228s). The original crash and first failed linker run remain retained.
Automatic compaction/archive/context recovery remain open. The latest earlier Core aggregate passed
51 functions/seven suites (106.826s); later Autodream/model/restart changes need their current owning run.


### Bounded plain-history compaction (2026-11-06)

The common loop can now reserve one context recovery, request a tool-free summary through its shared
RunState, and commit a compatible projection checkpoint only if the original prefix still matches and
the complete protected candidate fits. Summary purpose/usage are typed and hidden. A successful main
step clears this context-recovery allowance. The initial scope is older plain conversation text; typed
runs, images, tool transactions and input lifecycle records remain protected. Broader compaction and
artifact handling are still open. Core protects both profiles atv4 before new compaction metadata.

The actual embedded/file-journal positive Red/Green passes, including shared attempts, original/raw
history and protected objective/current/recent inputs. Initial Green had an enum-key compile error,
retained before unchanged Green. A fresh-scratch portable suite passes116 functions/8suites9.025s.
A subsequent actual background regression reproduced two unintended summary-request assertions:
its separate projection did not contain the foreground history. Derived compaction is now refused
before any summary request; unchanged Green passes. Three additional post-implementation failure cases
(authentication, forbidden tool call and insufficient reduction) pass and preserve the previous
projection. The seven-function portable-host group passes1.603s. Current full portable/Core aggregates
are running; no full migration/platform/rollout completion is claimed.

### Compaction projection and recovery follow-up (2026-11-06)

Protected image bytes now use the same loader in ordinary and compacted projections, with exact
image-array equality checked before checkpoint commit. Minimal synthetic summary metadata prevents
presentation-only checkpoint markers from hiding their model summary. Auxiliary responses are
excluded from embedded chat history, previews and counts; summary cache version5 invalidates old
counts. A real old-cache fixture verifies reconstruction without changing canonical bytes.

The original image cycle retained a mistaken whole-text assertion alongside the actual missing-image
failure. Its exact fixture is archived; the corrected first-line assertion is post-implementation
coverage, not an unchanged Green. Separate summary-metadata and visible-history cycles have retained
unchanged Greens. The complete portable suite then passed120 functions/eight suites (3.371s).
Current Core consumers passed27 functions/five suites (18.051s); documentation built in23.46s.

Two further retained Red/Green cycles cover context recovery. The allowance remains spent until
the entire model/tool step has settled, including durable results. Typed provider context overflow
can compact once even when local preflight fits. A repeated overflow stops, authentication does not
compact, and a subsequent transport retry keeps the compacted projection and correct attempt
identity. The provider fixture passes all four cases (5.376s). Broader typed-history compaction,
artifact archival and the remaining queue/background/legacy migration work remain open.

## Continuation: queues, durable approvals and output artifacts (2026-11-06)

The contributor again requested implementation without a reviewer and a separate issue register.
The approval of all seven stages remains in force. No reviewer was launched, and no commit or
publication was made. The remaining register is [native-agent-loop-issues.md](native-agent-loop-issues.md).

Delivered behavior:

- Embedded follow-ups are journaled before waiting, serialized by stored session across UI channels,
  restored by client identity and retired on queued cancellation. Separate live hosts still require
  application-level ownership; callbacks are supplied again on restart.
- Structured Core steering enters at completed step boundaries, is rechecked after either compaction
  path, settles with its original owner and does not supersede the original input on restart. Normal
  follow-ups remain excluded. Accepted completion and cancellation retain priority.
- Approval requests/decisions are durable and fail closed on corrupt storage. Native permissions bind
  their original call, arguments, declaration and resource restrictions. JSON Schema required sets are
  canonicalized without weakening authority. The loop resumes original requested calls only when
  neither a start nor a result exists; known results and unknown started effects cannot be replayed.
- Old large outputs have verified, session-scoped full artifacts. Current observations remain complete
  until a subsequent response consumes them. Fresh readers and corrupt blobs preserve canonical
  fallback; full result bytes remain in JSONL for compatibility.
- Self-improvement proposal review uses the common source-bound background owner, pinned settings,
  restricted declarations, current-policy checks, late scalar outcomes and settled-source deduplication.
  Workflow agent, goal and ACP-native requests already enter the session facade; their remaining
  controller/rollout evidence is still open.

Retained TDD includes embedded-follow-up-queue, embedded-queue-cancel, native-steering-boundary,
core-steering-owner-resume, native-steering-provider-compaction, native-tool-output-artifact,
native-artifact-protected-current-read, native-self-improvement-consumer, native-approval-persistence
and native-approval-original-effect-v2. The malformed original approval fixture and aggregate timing/
platform fixture exceptions are documented with original bytes and logs in the applicability record.
No historic Red, full-profile success or independent review was manufactured.

Validation for the current implementation:

- Complete portable owning rerun: 128 tests, eight suites, 20.614 seconds; log
  `.artifacts/contribution/native-loop-queues-approvals-artifacts-owning-rerun.log`.
- Core native/derived/coordinator/worker/storage/receipt/permission and proposal integration selection:
  77 tests, ten suites, 140.240 seconds; log
  `.artifacts/contribution/native-loop-queues-approvals-artifacts-core-native.log`.
- Expanded legacy/runtime/downstream selection: 186 tests, twelve suites, 189.149 seconds, one issue
  in the ten-second stream-start watchdog of abortChannelCancelsActiveInlineResponseTask. All directory
  approval cases pass after moving fixtures outside the implicitly allowed temporary root. The failed
  aggregate is retained in `native-loop-queues-approvals-artifacts-core-final.log`. The unchanged
  stream-abort test passes alone in 0.013 seconds (`native-loop-abort-isolated.log`); this is not a
  claim that the aggregate passed.
- The guide built in 28.81 seconds before this plan update; final documentation is rebuilt afterwards.
- A complete review-profile attempt reported existing trailing whitespace, 25 secret-scanner findings
  and unavailable SwiftLint. Its Windows compile was interrupted after those prerequisite failures;
  no passing compile or full report is claimed. The final quick report is only a current local gate
  diagnostic, not full validation. Required release/full-suite/client/platform/rollout evidence remains open.

The seven overall migration checkboxes remain open against their full acceptance criteria. Broad
transaction compaction, remaining provider routing/fallback/configuration gates, separately versioned
planner/evidence freshness policies, universal derived startup recovery and final old-owner removal
are not silently replaced by these scoped successes. Pilot samples and supported-platform evidence
are still required before widening rollout. The issue register records these gaps explicitly.


## Final functionality continuation (2026-11-06)

The contributor requested finishing implementation with tests, deferred review and a separate issue
register. Existing approval remains in force. No reviewer, commit, publication or default rollout was
introduced. The earlier checkpoints above are historical; the current functional status follows.

Implemented against the remaining code inventory:

- Whole historical typed transactions participate in bounded compaction. Canonical history, current
  task context, unresolved effects, evidence, images and verified artifact references stay recoverable.
- Runtime/profile settings pin planner version 1 and evidence version 1 or 2. Strict completion requires
  evidence from the latest tracked mutation revision; durable start tails restore that revision.
- Native automatic admission routing filters single-step capability and stores routing mode in RunState.
  OpenAI Chat compatibility fallback selects Responses for the next counted attempt. Auxiliary model
  requests share recovery budgets and persist successful attempt attribution.
- Startup discovery restores pending native memory/proposal jobs and proactive attention. Reservations
  join concurrent scheduler calls, known results are reused, and saved scopes/model/prompts remain pinned.
  Eligible provider failures resume the original owner in a new generation without resetting budgets;
  explicit cancellation revokes that recovery, including before terminal settlement.
- Proactive review uses a canonical protected heartbeat job, source/configuration digests and the ordinary
  Core pipeline scoped to heartbeat.report. Successful reports survive a restart without repeated effects.
- Embedded send exposes steering through the existing durable queue. Actual workflow/goal/ACP-origin
  and heartbeat entries have canonical-owner integration fixtures. Legacy configurations remain compatible.

Named retained behavioral cycles include typed-history-compaction, evidence-freshness-policy,
conservative-evidence-revision, derived-startup-controller, unified-model-routing,
auxiliary-request-recovery, native-proactive-owner, native-background-credential-resume and
background-cancel-revokes-recovery. The format-fallback and heartbeat-token fixture corrections have
explicit applicability explanations and archived original bytes; their failed cycles are not represented
as unchanged Green. Embedded public-API coverage was extended after the shared queue implementation.

Final test results and remaining external validation are recorded below and in
[native-agent-loop-issues.md](native-agent-loop-issues.md). Seven-stage rollout acceptance is distinct
from completing this functional code inventory: real live pilot measurements, supported-platform/release
checks, independent review and conditional legacy removal are not inferred from offline fixtures.


Final broad Core serial validation: 299 executed tests in 32 suites passed (749.927s), including
native coding with real Swift compilation, session recovery, routing, strict evidence, supported
consumer entries, proactive/derived work, permissions and downstream workflow controllers. Log:
.artifacts/contribution/native-final-core-serial.log. The final stopped-source assertion and startup
fixture synchronization are verified by a separate final background owning rerun below.


Final source-refreshed background owning rerun: 9 tests in two suites passed (48.238s), including
same-owner credential recovery, known-result reuse, persisted stopped-source deduplication and
startup recovery synchronized with its actual Task. Log:
.artifacts/contribution/native-final-background-owning.log. Final portable offline evidence is
304 executed tests / 72 conditional skips (376 selected, 47 suites, 29.797s) in
.artifacts/contribution/native-final-portable-serial.log. No independent review was performed.
The final guide/plan/issues documentation build and quick code-stage content check are run after
these records. They do not establish live pilot, release, Apple/client or hosted CI acceptance.


## Automated failure closure, 2026-11-06

The source-refreshed affected Core suite passed 608 tests in 52 suites (1018.445s), including
all AgentRuntime, agent-session, native/consumer/derived/proactive, workflow, approval, checkpoint,
heartbeat, cron, strict-evidence and storage-compatibility selections. Log:
`.artifacts/contribution/native-suite-combined-final.log`. This is an affected selection, not an
unfiltered repository suite. Portable SDK/AnyLanguageModel validation passed 318 executed tests
(391 selected, 73 existing conditional skips, 49 suites, 43.763s), recorded in
`.artifacts/contribution/native-suite-portable-final.log`. Earlier failed aggregates remain retained.
Live/platform acceptance and historical full-profile prerequisites are separate in
[native-agent-loop-issues.md](native-agent-loop-issues.md). Independent review remains deferred
at the contributor's explicit request.
