# Native agent loop remaining issues

Updated: 2026-11-06. Independent review is deferred at the contributor's explicit request.
This file records implementation gaps and adjacent findings; it is not a completion attestation.

## Current verification scope

The source-refreshed Linux serial Core selection PASSED: 608 tests in 52 suites, no failures,
1018.445s. No automated failures remain in this verified selection. Log:
`.artifacts/contribution/native-suite-combined-final.log`. It includes all AgentRuntime tests,
agent-session, native ownership/loop/consumer/derived/proactive tests, workflows, approval paths,
strict evidence, storage compatibility, and explicitly selected checkpoint/heartbeat/cron fixtures.
This is an affected-suite selection, not an
unfiltered root `swift test` or a release/platform acceptance claim.

Portable/PluginSDK/AnyLanguageModel offline tests passed: 391 selected in 49 suites, 73 existing
conditional skips, 318 executed, 43.763s. Log: `.artifacts/contribution/native-suite-portable-final.log`.
The harness excludes the existing multiline `@Guide` compiler fixture and eleven Ollama tests that
require localhost:11434. Skips are not counted as executions.

## Automated defects fixed in this continuation

- Public shutdown releases native workspace ownership after joining work; crash fixtures separately
  suspend inbox dispatch so that they can preserve a real durable effect before process loss.
- Workflow waiting state is published only after its pending action is durable. Tool approval becomes
  publicly visible after the session pause and linked-task waiting status have been persisted.
- Tool-free runtime calls use the shared retry/empty-response recovery loop and retain history seeds
  and failed-turn history. Prepared-frame context diagnostics and specific policy-stop outcomes remain visible.
- Parent/checkpoint context is copied as factual historical events with destination-owned attachment
  bytes and remapped correlations, without inheriting source input/run authority.
- Native planning presentation and current mode come from the active loop. Late cancelled effects
  retain factual results but cannot grant completion/evidence authority. Structural argument failures
  supply typed bounded correction feedback.
- Legacy provider fixtures now declare single-step capability and their actual schemas. Usage tests
  check canonical records, history tests check physical append order, and heartbeat fixtures declare
  the configured model. Production authority checks were preserved.

## Live and platform scenarios (separate from automated defects)

- Live backend/OAuth/credential-refresh pilots and repeated fixed-task token/cost/latency/solve-rate measurements.
- Apple SwiftUI artifact preview/share compilation and UI interaction; client builds/tests.
- Supported Windows products, release products, Linux/macOS CI parity and hosted CI execution.
- Live Ollama backend and provider/platform cases skipped by the offline harness.

## Other validation boundaries

- Independent review is deferred explicitly by the contributor; no review was performed.
- The unfiltered root repository suite has not been run to completion in this continuation.
- Content-only code-stage validation and documentation build are recorded separately. They do not
  resolve historical full-profile SwiftLint availability, unrelated whitespace or heuristic secret
  scanner findings listed below. Those are automated validation prerequisites/findings, not live scenarios.

## Closure requested in response annotation 1

Implemented on 2026-11-06:

- Cross-process embedded session ownership uses OS-held leases. Same-host queued callers share the
  lease; late factual effects keep it alive. Core approval persistence and native stores share one
  workspace owner. A contender cannot authorize/write; stopped stores cannot adopt successor authority.
- Awaited same-conversation callback sends fail with a typed reentrant-send error before enqueueing.
  Independent callers retain FIFO/steering. Arbitrary detached-task dependency cycles are outside this guard.
- Schema-2 artifacts remove duplicated full JSONL payloads; readers hydrate verified full results.
  Outputs over 25 MiB, bounded chunks, verified snapshot streaming/export and reference-aware old-blob
  collection are implemented. Evidence/completion and message attachments are retained as roots.
- Public embedded discovery/read/stream/export APIs, transcript artifact links and a SwiftUI preview/share
  component are implemented. Apple compilation/UI checks remain external validation below.
- Native selector omission and legacy/unified spellings resolve to AgentLoop. Duplicate native generation,
  streaming, reconnect and context-reset owners were removed. Standalone AnyLanguageModel APIs remain.
  Third-party native providers must implement ModelStepProviderFactory; no provider-owned scheduling fallback.

## Historical implementation and test findings (before automated closure)

- The first expanded Core run failed (248 selected tests, 264 recorded issues). Some restart fixtures
  instantiated a second live Core without releasing the original lease. They now stop the old owner and
  restore the exact injected crash image before starting the successor. This does not bypass leases.
- Native bootstrap refresh initially removed the channel snapshot expected by the public API. The initial
  system/bootstrap snapshot is now created once; later projection refreshes do not grow channel history.
- Shutdown now stops/joins inbox runners before releasing workspace ownership and keeps resumable
  queued inputs instead of converting shutdown cancellation into an input rejection.
- The broad run also selected old provider mocks lacking single-step capability, history-in-bootstrap
  assertions, and unrelated fixture/config/cache failures. Its failed result is retained. Passing narrower
  owning results must not be described as a successful full repository suite.
- agentSessionStoreDecodedEventsStayCurrentAcrossAppendsAndForeignWrites expects createdAt-sorted
  history after appending one/three/two. Native canonical readers now preserve physical journal order.
  That legacy expectation needs migration while retaining both foreign-write invalidation assertions;
  its failed run is not evidence of a passing cache check or, by itself, proof of stale reads.
- The SwiftUI artifact component has not been compiled or exercised on Apple platforms.
- The portable parallel cancellation fixture hit its three-second HTTP-start watchdog. The source-identical
  serial run passed; the parallel aggregate remains failed evidence.

## Implemented before this closure

- Durable embedded FIFO follow-ups, stored-session serialization across UI channels, queued identity recovery and cancellation retirement.
- Actor-owned steering selection at completed steps and after compaction, stable owner/receipt settlement and the original-input restart guard.
- Durable pending approvals and decisions; exact native call/argument/declaration/resource binding; original never-started effect recovery without another model tool response. Unknown started effects are not replayed.
- Full tool-output artifacts with digest/session validation, protected current observations, references for older consumed results and canonical fallback on corrupt blobs.
- Native self-improvement proposal reviews on the shared derived-work owner, with pinned restrictions/settings, current-source checks, hidden internal history and settled-source deduplication.

## Functional closure in the final continuation

- Completed historical typed transactions now enter bounded compaction. Current input, unresolved calls,
  verification and image records remain protected; canonical records are unchanged.
- Automatic admission routing filters single-step capability; OpenAI Chat-to-Responses fallback is an
  explicit counted loop retry. Auxiliary generations share the owner's recovery and attempt identity.
- Planning version 1 and evidence versions 1/2 are pinned; strict evidence checks the latest tracked work
  revision, including durable starts after a checkpoint. Unknown read-only MCP annotations are conservative.
- Startup scans canonical derived/proactive jobs, joins scheduler ownership and retains known results.
  A credential failure previously caused a fresh proactive job and repeated reports; the regression now
  retains its original run/budgets. Explicit cancellation revokes recovery even while already stopping.
- Embedded send now exposes steering. Workflow, goal, ACP-origin and normal/checklist heartbeat have
  real Core entry fixtures. The heartbeat session-kind gate and proactive legacy-only path were fixed.
- Proactive review now stores frozen source context and authority, uses scoped heartbeat.report through
  ordinary Core tool checks, and restores successful correlated reports without repeating their effects.

## Outstanding rollout and external validation

- Fixed-task live pilot measurements (at least three repetitions), token/cost/latency and solve-rate
  evidence require configured live backends. Mock fixtures cannot establish those acceptance gates.
- Apple/client, supported Windows products, full release products and hosted CI parity remain unverified
  in this continuation. The local Linux owning suites are not substitutes for those platform results.
- Legacy configuration/API compatibility now forwards to the common native owner. Broad live rollout
  measurements and platform evidence remain separate acceptance work.
- Independent review is deferred by the contributor. No review or approval record has been invented.

## Known limitations and adjacent findings

- Embedded recovery requires the application to resupply build/tool callbacks and retry saved clientMessageID values in journal order. Executable closures are not persisted. The host send API now exposes steering; the application must preserve the stored conversation identity.
- Embedded active-turn cancellation/failure receipt coverage is narrower than queued-caller cancellation coverage; do not claim all restart/cancellation shapes are complete.
- Approval storage enforces one live Core owner per workspace with an OS-held lease. Resolved decision retention is bounded to 1,024 records; original deadlines still apply. Imported unbound records do not acquire native invocation authority.
- Provider-facing generated schema required arrays may vary in order. Approval fingerprints normalize this semantic set; broader provider-prefix determinism is not established by that fix.
- The first broad portable run exposed an existing scheduler-dependent effect fixture: a real 30 ms timeout could expire before its held operation entered. The fixture now uses the existing injected clock and explicit arrival/late-result signals, retaining all effect assertions and production deadlines. Original source/logs are preserved.
- The first approval-resume fixture omitted the required provider started event. That incomplete cycle is retained; the corrected v2 cycle has its own actual behavioral Red and unchanged Green.
- Existing dependency-identity/compiler warnings are recorded in build logs and have not been turned into additional implementation work.

## Validation

The continuation retains named Red/Green cycles for its behavioral slices. Final owning/profile results are recorded in docs/plans/native-agent-loop.md and .artifacts/contribution/; independent review and full migration completion are not claimed here.

## Historical validation boundary (before annotation-1 closure)

- Portable owning rerun: 128 tests in eight suites passed (20.614s).
- Native Core/derived/coordinator/worker/permission/receipt selection: 77 tests in ten suites passed (140.240s).
- Expanded selection: 186 tests in twelve suites, one stream-start watchdog issue (189.149s). The unchanged abortChannelCancelsActiveInlineResponseTask passes alone (0.013s). This aggregate is not claimed green; its scheduler-sensitive ten-second readiness check remains a known fixture issue.
- All legacy directory-approval cases in that expanded run pass after moving disposable fixtures to the user cache, outside automatically permitted temporary roots. The original fixtures and failed run remain archived.
- Complete validation remains blocked by SwiftLint availability, existing trailing whitespace in CoreService+Swarm.swift and CoreRouterTests.swift, and 25 heuristic secret-scanner findings in existing fixtures. Scanner output is redacted; findings have not been suppressed or declared safe without triage.
- The full profile's Windows compile was explicitly interrupted after those prerequisite failures. It supplies no successful build evidence. Release products, full-suite, client and supported-platform gates remain outstanding.


## Historical test-fixture findings (before annotation-1 closure)

- The first format-fallback fixture used collectStep, intentionally a one-attempt collector. Its failed
  Green remains retained. The corrected test invokes the actual AgentLoop and asserts counted attempts,
  endpoints and final continuation. Original bytes: .artifacts/contribution/native-format-fallback-original-collector-fixture.swift.
- The first heartbeat entry fixture emitted HEARTBEAT_OK instead of CoreService.heartbeatSuccessToken
  (SLOPPY_ACTION_OK). The original failed attempt remains retained; the corrected fixture uses the
  protocol constant. Original bytes: .artifacts/contribution/native-entry-original-heartbeat-token-fixture.swift.
- Initial proactive fixture setup omitted the required analysisModel configuration. It was corrected
  before behavioral Red. An initial Green then exposed a real proactive-admission reader gate; that
  production gate was fixed and the unchanged behavioral fixture passed.
- Embedded steering API coverage was extended after the shared queue implementation existed. No
  missing-API compiler failure is claimed as behavioral Red.
- The offline AnyLanguageModel harness excludes the existing multiline @Guide macro fixture that does
  not compile on the available Swift 6.2.4 Linux compiler, and eleven Ollama tests requiring localhost:11434.
  Seventy-two selected live/platform-dependent tests are skipped by their existing conditions.


## Historical local validation notes (before annotation-1 closure)

- Final portable/SDK/AnyLanguageModel offline serial run: 376 selected tests in 47 suites,
  72 existing conditional skips, 304 executed successfully (29.797s). Log:
  .artifacts/contribution/native-final-portable-serial.log.
- The simultaneous broad parallel rerun is retained as failed: the portable cancellation fixture did
  not receive its HTTP-start signal within three seconds; the broad Core aggregate reported 103 issues
  dominated by workflow time limits and readiness checks. Logs: native-final-portable-parallel-failed.log
  and native-final-core-parallel-failed.log. Serial results are separate evidence, not a rewrite of those runs.
- The derived startup fixture's three-second polling was replaced with awaiting the actual recovery Task;
  all ownership, model, budget and single-effect assertions remain. A persisted stopped proactive source
  also has explicit coverage preventing a fresh replacement job.
- The quick content check initially found trailing whitespace at CoreService+GatewayPlugins.swift:159.
  That whitespace was removed and the quick code-stage check passed. Full-profile external prerequisites
  and unrelated earlier findings listed above remain outside that content-only success.


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


## Historical annotation-1 closure evidence

- Portable final offline serial run: 390 selected / 49 suites, 73 conditional skips (including the
  subprocess-child fixture), 317 executed successfully, 44.201s. Log:
  .artifacts/contribution/native-ownership-portable-final.log. The previously failed parallel run is retained.
- Retained behavioral Red/Green cycles: embedded-exclusive-owner, approval-exclusive-owner,
  complete-artifact-storage, native-engine-alias, core-workspace-exclusive-owner,
  stopped-core-writer-authority and unified-context-diagnostics. Initial incomplete infrastructure/fixture
  attempts are retained separately; they are not claimed as successful behavioral Red evidence.
- A later broad Core regex also selected old non-step mocks through source filenames. These still fail:
  runtimeRecordsContextLedgerForNativeModelCall, agentSessionMarksTurnIncompleteWhenNativeToolRoundLimitIsReached,
  tuiAgentSessionDoesNotEnforceNativeToolRoundLimit, and
  agentSessionInterruptPreventsLateNativeToolCallbacksFromAppendingEvents,
  childApprovalSurvivesRestartAndDeletedLiveDefinition, approvalContinuesBeforeSiblingModelCompletes and
  failedToolCancelsPendingNativeQuestion.
  The workflow fixtures also reach invalidPayload before model/tool work. Their provider fixtures require
  migration to explicit single-step declarations/signals. The actual common path's context ledger now
  has a separate Red/Green test. These automated-test failures are not live/platform uncertainty.
- Migration history assertions now inspect a real captured single-step request, keeping imported history
  out of bootstrap while preserving it as model input. Approval-default fixtures now use workspace-local
  config paths instead of sharing a nonexistent default .sloppy directory. Their rerun is recorded below.
- Documentation build passed (25.66s); quick code-stage content validation passed. Neither is a release,
  full repository suite, platform or independent review attestation.


Expanded Core result for the annotation-1 implementation: 199 tests / 28 suites, 13 issues,
709.192s; .artifacts/contribution/native-ownership-core-final.log. This aggregate is FAILED.
Its native coding, consumer entry, coordinator, derived, proactive, delegated authority, session
integration (35 tests), effect boundary and strict completion suites passed. The known restart,
migration and isolated-config fixture fixes are rerun separately below; no aggregate result is rewritten.


Final affected-Core rerun: 17 tests / 6 suites passed, 8.819s,
.artifacts/contribution/native-ownership-core-fixes.log. This covers provider failure restart,
actual imported-history model projection, isolated approval defaults, paired profile protection,
bootstrap/lifecycle compatibility, exclusive approval owners and durable approval reload/corruption.
It fixes those five failures from the 199-test aggregate; that aggregate itself remains failed.
The seven legacy-provider/workflow tests and the separate timestamp-order cache fixture listed above
remain automated-test migration/diagnostic work, not unverified live/platform scenarios.
The full repository suite is not claimed green. Apple SwiftUI, Windows/release products, live pilots,
hosted CI and independent review remain external validation/deferred review, separately from those failures.
Final documentation build and content-only code-stage check are rerun after this record.


## Historical automated-suite closure work log (2026-11-06)

User explicitly requested closing automated failures without review, keeping live/platform gates separate.
During implementation, named workflow lifecycle Red/Green covers durable pending action publication before
waiting status and release of workspace ownership through public CLI/TUI shutdown. A separate named
native-lowlevel-shared-recovery Red/Green covers tool-free retries, empty-answer repair and history seeds
using AgentLoop, replacing the one-attempt compatibility collector. Typed frame context diagnostics and
policy-stop presentation were restored after the expanded owning run exposed them.

Legacy fixture migration retains actual effect, cancellation, budget, evidence and restart assertions.
Model-call-shaped plain assistant text has no tool authority; JSONL remains in physical append order.
Generated schemas close objects, so fake declarations now describe their actual argument examples rather
than assuming additionalProperties=true survives GenerationSchema encoding. Intermediate failures remain
in .artifacts/contribution/native-suite-*.log; none are counted as successful final suite evidence.

The attempted help invocation of the test binary started a parallel run, which was interrupted. It is
not valid final suite evidence. Full-suite mirror setup now also copies the repository's bench fixtures.


## Final automated-suite closure result (2026-11-06)

- Core affected suite: 608 tests / 52 suites passed, 1018.445s;
  `.artifacts/contribution/native-suite-combined-final.log`.
- Portable SDK/AnyLanguageModel: 391 selected / 49 suites, 73 conditional skips,
  318 executed successfully, 43.763s; `.artifacts/contribution/native-suite-portable-final.log`.
- Prior aggregate: 575 tests / 51 suites, 44 issues; retained in
  `.artifacts/contribution/native-suite-combined.log`. The 48-test diagnostic rerun fixed all original
  failures and exposed four heartbeat fixture assertions; both successful and unsuccessful attempts
  remain in `native-suite-final-fixes*.log`. The final 608-test aggregate includes those heartbeat cases.
- Fixture compiler errors, the invalid WSL argv attempt and the interrupted accidental help run
  remain failed/incomplete evidence. They are not counted as executions or behavioral Red cycles.
- No independent review was performed. Live/platform scenarios and other validation boundaries are
  listed separately near the top. Affected-suite success does not claim an unfiltered repository run.


## Windows build and installation smoke, 2026-11-07

- Built Windows debug `sloppy` and `SloppyNode`, rebuilt Dashboard and passed its TypeScript check.
  The source was installed into the existing per-user Sloppy location and its scheduled-task service
  restarted. The installed server hash matches the build; service status is Running, `/health` and
  Dashboard return HTTP 200. This verifies this Windows debug installation, not release/Apple/CI parity.
- The first Windows build exposed mixed WinSDK integer types in `FileOwnershipLease` access flags.
  Casting each flag to DWORD before OR fixes compilation. A Windows smoke compiles the actual source
  and verifies exclusion of a second owner and reacquisition after release. This was a compiler
  prerequisite fix, not a manufactured behavioral Red cycle. Evidence:
  `.artifacts/contribution/windows-install-build.log`, `windows-install-build-v2.log`,
  `windows-install-apply.log`, and `windows-lease-smoke/result.log` in the same directory.
- Startup logs report HTTP 401 from the configured embedding backend (missing API key). Server and
  Dashboard start successfully; embedding configuration still needs valid credentials. This is a live
  configuration issue, separate from automated suite failures. Credentials were not changed.
- SwiftPM dependency-identity/pkg-config warnings, Swift 6.3 warnings, and a macro diagnostic about
  corrupted JSON remain in the successful build log; no clean-warning or full Windows-suite claim.
- Independent review remains deferred. No release was published.
