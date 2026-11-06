---
layout: doc
title: Native Agent Execution
---

# Native agent execution

A native Sloppy session uses your selected model to read context, call tools and return an answer. Tool access follows the agent's policy and any required approvals. Selecting a coding mode does not grant additional filesystem or command permissions.

## Model transport and single-step generation

Native HTTP generation uses the vendored AnyLanguageModel single-step API for OpenAI
Responses and Chat Completions, Anthropic, Gemini/Code Assist, and Ollama. The library
owns HTTP, streaming framing and provider codecs. Sloppy supplies account headers,
credential refresh, proxy/trust settings and usage observation, then handles approvals,
tool execution, retries and the next model step in its own runtime.

Library callers can request one generation with schema-only tools:

```swift
import AnyLanguageModel

let provider: any LanguageModelStepProvider = HTTPModelStepProvider(
    providerID: "my-account", model: "my-model", baseURL: endpoint,
    token: { apiKey }, session: transport
)
let request = LanguageModelStepRequest(
    messages: [.init(role: .user, text: "Inspect this project")],
    tools: [.init(name: "inspect", parameters: .object(["type": .string("object")]))]
)
for try await event in provider.streamStep(request) {
    if case .final(let response) = event {
        // Persist this settled response before deciding whether to execute its tool calls.
        print(response.stopReason, response.toolCalls)
    }
}
```

`endpoint`, `apiKey` and `transport` are caller-provided configuration. No executable
tool closure enters this API. A returned tool call, including malformed argument text,
does not trigger another generation. Preserve `response.continuation` with the next
assistant message when staying on the same provider/account/model. Cancellation stops
the underlying HTTP request. `SingleStepTests` verifies this example's request and tool
declaration shape against a local HTTP fixture, including JSON and SSE responses.
Existing `LanguageModelSession.respond` and `streamResponse` remain available with
their existing tool orchestration behavior.

New journal formats require compatible profile protection before Core writes them. Partial profile upgrades do not permit a write. Saving ordinary settings or choosing the legacy selector preserves existing protection, so an older Core cannot resume history it does not understand.

In an ordinary native session, a queued message saves its original request settings, ordered attachment references and content digests together. Admission retains that context and assigns its execution owner; response delivery is recorded separately. Explicit empty files remain distinct from attachments without uploaded bytes. New input identities compare decoded attachment bytes, while previously accepted legacy identities keep their original comparison rules. Queued inputs existing at an interrupt's admission boundary are cancelled in its first durable control record. A later message remains independent. Cancelled and failed never-admitted inputs stay read-only after loss of the queue cache.

Core reconstructs known native queues from the journal when `inbox.json` is absent, corrupt or unwritable. Receipt order and unfinished ownership survive a restart: a waiting B cannot overtake unfinished A. Native acknowledgement follows the journal write, so an unavailable cache also permits a new follow-up. A corrupt cache is preserved separately when possible; if that copy fails, Core keeps its original bytes and handles known canonical receipts in memory. Unknown legacy payloads are never guessed. Readable previous-format queued requests acquire canonical context before dispatch, preserving their displayed text, interpreted mode command and attachment references. Legacy requests without canonical protection still require their authoritative cache write.

A native form action records its accepted surface and semantic payload with its first receipt. Surface reads and duplicate submissions recover from that context after cache loss; the model projection uses the structured action body while history keeps readable labels. Reusing an ordinary input's ID through a form or peer message is rejected before changing the journal or consuming the form. These receipt/projection checks are separate from the Auto execution policy; ordinary Auto and the supported native consumers use the shared loop. The legacy native selector remains readable and forwards to the common execution owner.

For a peer conversation with a delegated session, command interpretation and its restricted Ask mode are fixed before queueing. Sloppy retains the sender's original submission for retries alongside the prepared execution request; delivery does not change the saved identity. This conversation cannot grant the worker additional tool access. An explicit empty delegated scope exposes no schemas and authorizes no tools, including after recovery narrows the scope.

## Completing coding work

Ordinary native Build and Debug sessions require an accepted `session.complete` result. Long-chat coordinators finish through their handoff contract, and delegated workers use their worker finalizer. For ordinary sessions, the model supplies a summary, a typed status and verification evidence IDs returned by successful tools in the current task. Build accepts build/test/run evidence; Debug also accepts screenshot evidence. A sentence saying that a check succeeded does not create evidence.

For example, ask the agent to change a small file and run the project's existing focused check. After that tool returns valid verification evidence, the agent may complete with this payload shape:

```json
{
  "status": "completed",
  "summary": "Updated the requested behavior and ran its focused check.",
  "verificationEvidenceIds": ["verification-1"]
}
```

The ID is illustrative: the agent must use an ID actually returned in that task. An unknown ID is rejected. A failed command is not successful verification. A background process starting does not establish that every task requirement was tested.

The other completion statuses are `blocked` and `waiting_input`. A blocked result includes a concrete limitation. Answering a native Plan/Debug question resumes the same run and user turn in a new execution generation, retaining work counters, settings and verification. The answer and resumed state are saved together before dispatch; repeating the same answer returns its existing receipt. A conflicting answer is rejected. Answer summaries remain visible without creating a second model task or incrementing the user-turn count again. Completion recovery must not bypass approval or user-input boundaries.

When a tool-round limit is enabled, the original user turn keeps the same ceiling across completion recovery and transport retries. Recovery does not grant a fresh budget. For example, a turn limited to two tool rounds cannot execute four rounds by continuing after each answer. Disabled limits and existing TUI/onboarding exemptions retain their behavior.

An admitted unified turn also keeps its original transport retry schedule and resolved reasoning effort after restart. Changing the agent's profile does not change those settings for unfinished work. An absent effort override is preserved too. Older snapshots that never saved these settings bind them when first resumed; Sloppy cannot reconstruct unknown historical values.

Usage returned by an unobserved provider is saved with the complete response before tools execute. Startup rebuilds its accounting records from that journal without generating another answer or counting the same response twice. Historical fork records do not charge the new session. These records retain reported totals and mark unavailable component attribution as incomplete. Observed HTTP requests retain their existing accounting path and also carry run and user-turn identity. `/v1/usage/breakdown` accepts optional `runId` and `userTurnId` filters together or individually; older unscoped records remain in the unfiltered totals. The Core fixtures `fallbackUsageIsDurablePerRunAndRebuildsWithoutGeneration` and `nativeUsageQueriesScopeRealSQLiteByRunAndTurn` verify replay, filters and deduplication through the actual API and SQLite backend respectively.

An accepted `session.complete` is a barrier in ordinary native Core sessions. Later calls receive a correlated `not_executed_after_completion` result and cannot change the workspace. Completion itself remains available after the last allowed work round; skipped calls do not spend another work round. Acceptance comes from the typed tool result, never from the assistant saying that it is finished.

## Interrupted operations

If execution started but its durable result was not recorded, the operation may already have changed files or an external service. Sloppy preserves the call and marks its outcome unknown. Inspect the target before deciding whether another execution is appropriate. Owner reconciliation records what happened; it does not itself execute a tool. Repeating the same request is not a safe substitute for reconciliation.

Cancellation stops new work and requests cancellation of active operations. It cannot guarantee that an already sent external operation had no effect. A tool-loop stop or denied approval is not permission to retry through a different model or transport.

Timeout observations use documented tool/approval/provider error codes, or the `timedOut` flag on an interrupted owned effect. Quoted log text and localized error descriptions do not determine runtime recovery state.

The session journal preserves append order even when event clocks differ. A reader rejects unsupported journal/runtime versions before extending the file; pagination and cached summaries do not waive that check. Compatible checkpoints retain the original task, pending input and call/evidence provenance. A requested call without a durable start marker is recorded as not started; a started or legacy call without a durable result remains unknown.

Core has a storage compatibility gate for agents selected for unified execution: both agent storage files receive a discriminator that older Core readers reject. The public runtime type remains `native` or `acp`. Explicit rollback to `runtime.nativeEngine: "legacy"` preserves the storage guard for existing unified journals; an older client omitting the field preserves the current engine. An active run keeps its pinned engine when that profile setting changes, and its actual results can still be recorded. A new legacy run must use a compatible legacy journal: an existing unified journal is rejected rather than reinterpreted by the old loop. Create a fresh legacy chat, or select a compatible unified engine to continue that journal. The fixture `activeEngineStaysPinnedAndRollbackRequiresANewLegacyJournal` verifies both boundaries and a working fresh legacy response. Do not remove the storage discriminator to downgrade. The embedded host uses an explicitly selected unified engine and a separate versioned store instead of the Core catalog gate; see the embedded-host example below.

Once the paired storage guard is installed, readiness checks verify both profiles without rewriting them. Partial activation still requires both protected files before native journal writes. The fixture `protectedProfileVerificationDoesNotRewriteEitherFile` checks unchanged contents and modification dates while readers hold the actual files open.

## Migration status

The [unified native loop](../designs/native-agent-loop.md) owns native Ask, Plan, Build, Debug and
Auto chats. Omitted, `legacy` and `unified` engine selectors all resolve to that owner. A supported
single-step provider and trusted Core tool invoker are required. Automatic semantic routing filters
for single-step capability. Ask does not run the separate planner, even when a planner is configured.
An unsupported provider fails before generation or tool effects.

The optional planning policies are `legacy`, `executor` and `separate`. Omission retains existing planning behavior; older config updates that omit this field preserve an explicit selection. `executor` starts directly in the execution loop and skips the separate planner. `legacy` and `separate` retain the existing planner trigger rules: Build/Debug plan first; Plan/Auto do so when a dedicated planner is configured. On unified execution that planner is a tool-free single step, sharing the parent turn's request accounting and cancellation. Its saved output supplies scoped executor context and is reused after restart. It never executes tools. Existing `plannerModel` values are retained. The following configuration fields match the real Core coding fixture (use your supported model and preserve the other required config fields):

```json
{
  "automaticModelRouting": false,
  "runtime": {
    "type": "native",
    "sharedMemoryEnabled": false,
    "nativeEngine": "unified",
    "planningPolicy": "executor"
  }
}
```

The fixture `executorPolicyUsesRealVerificationAndRequiredCompletion` runs `swift build` against a prepared Swift package through the actual Core tool boundary, records verification and completes Build/Debug through `session.complete`. A missing finalizer exhausts the original turn's three completion-recovery requests and stops. Debug `planning.request_input` commits a typed pause linked to the persisted question; a later command in the same model response receives `not_executed_after_completion` and does not start. This coding fixture disables automatic shared-memory work to keep its verification assertions scoped to the coding turn.

Single-step adapters currently support OpenAI OAuth, API-key Responses configurations (`apiVariant: responses` or the existing `useOpenResponsesLanguageModel` provider setting), and default API-key Chat Completions configurations. Use an endpoint and model supporting the configured format; native cross-format fallback is still pending. HTTP fixtures cover exactly one upstream generation per step, raw arguments, opaque continuation, terminal responses, observed usage, OAuth authentication refresh, network cancellation and JSON/SSE parity. The API-key fixture `responsesAPIKeyStepPreservesProviderItemsAndDoesNotScheduleTools` also checks the configured endpoint, bearer authorization, output ceiling and ordered continuation across a tool result. Chat fixtures verify indexed argument fragments, images, reasoning content, usage following the final choice, output limits and real network cancellation. Unsupported changing opaque delta fields fail explicitly instead of losing provider state. Both API-key formats share the HTTP transport, failure classification and bounded SSE framing with OAuth. These fixtures do not establish live-account behavior or rollout readiness. Remote Sloppy steps and Core worker/coordinator contracts now have focused integration coverage. The standalone host and other remaining consumers still retain their migration gates.

Ollama also has a single-step adapter for chat JSON and NDJSON. It waits for `done: true`, preserves indexed calls, thinking and loaded image bytes, and supplies unique native call IDs when the server omits them. Native setup discovers model metadata before generation and excludes those queries from generation usage. Named thinking levels must match `/api/show`; models declaring on/off controls receive `think: true` for an explicit positive effort. An undeclared effort fails before generation instead of silently using a server default. The `ollamaStepPreservesIndexedCallsThinkingUsageAndContext` fixture checks both formats and both thinking-control types, including cached input tokens; separate fixtures cover incomplete/length-limited responses, unsupported effort and actual HTTP cancellation. These are local HTTP fixtures, not validation against a running Ollama server.

Anthropic Messages has a single-step JSON/SSE adapter. It keeps thinking signatures and redacted blocks in source order, accumulates tool input fragments and cumulative usage, and waits for closed blocks plus `message_stop`. Canonical journal projection carries a typed tool-error flag into `tool_result.is_error`; payload wording does not decide it. Fixtures cover signed continuation, cache read/creation accounting, images, input/output correlation, output limits, OAuth preflight and actual HTTP cancellation. Explicit effort uses the adaptive-thinking API, so the configured model must support those settings. Unsupported binding-control extensions fail explicitly instead of discarding continuation state. These are local HTTP and file-store fixtures; live provider/account compatibility is still pending.

HTTP response buffering uses the byte ceiling rather than a fixed count of network callbacks. Small chunks can accumulate while a consumer is busy without losing a valid response. The fixture `tinyHTTPChunksSurviveASlowConsumerWithinTheByteLimit` verifies a delayed consumer receiving 128 KiB in 17-byte chunks; existing fixtures still verify cancellation reaches the actual request. Oversized responses remain bounded at 32 MiB.

OpenAI OAuth continuation also binds the configured endpoint, alongside its account/model scope. Changing the host or tenant path cannot send saved opaque response items to that other endpoint. `oauthContinuationCannotCrossTheConfiguredEndpoint` verifies rejection before HTTP; a compatible continuation or explicit normalization is required.

The bounded model-event queue also waits for its consumer. A burst of preview events cannot discard the final answer or turn into an extra generation. `burstEventsWaitForTheConsumerWithoutLosingTheFinal` exercises 800 SSE text fragments in one network chunk through both OpenAI OAuth and API-key adapters while deliberately slowing consumption. Cancellation remains active while the producer waits.

Gemini API-key generation uses the Generate Content API directly. Original response parts, including empty parts carrying thought signatures, stay in order through the next request. Function results preserve API call IDs, images use inline bytes, and usage includes thinking/cache counts. The fixtures `geminiStepPreservesOrderedSignedPartsAndFunctionResults` and `geminiPartialAndLengthLimitedCallsNeverBecomeExecutable` cover JSON/SSE, continuation and terminal limits; another fixture cancels the actual generation. Explicit low/medium/high effort uses `thinkingLevel` and requires a compatible model. Unsupported effort fails before HTTP; omitted effort retains the server's thinking depth. The Core API-key path bypasses the legacy shared signature store.

Gemini OAuth uses a separate Code Assist request envelope and bearer/client headers. Native credential/project preparation uses its configured proxy session, and its project binding stays with that provider instance. It does not read or update the legacy process-wide project/signature caches. `codeAssistBindsProjectBeforeSendingSignedContinuation` checks nested JSON/SSE responses, the dedicated refresh callback, usage once per generation and rejection of signed continuation after a project change before HTTP. Foreign continuations and unsupported effort also fail before HTTP. These are local fixtures; live OAuth account/backend compatibility remains pending.

Gemini usage attribution reads declarations and skill catalogs from both API-key and Code Assist requests. When the API supplies function-call IDs, arguments and results link to those IDs across subsequent steps. If IDs are omitted, totals remain available and attribution stays explicitly incomplete. `geminiUsageAttributesWrappedSchemasAndOnlyRealWireCallIDs` verifies both transports with and without wire IDs; synthetic runtime IDs are not presented as observed API links.

Observed direct requests keep token usage with their owning session, including a reused request carrying an older internal observation header. Native HTTP transports retain their explicit request scope. The fixtures `actualRequestsCompleteOnlyAfterAccountingAndRemainSessionScoped` and `observedSessionOwnsAReusedRequestEvenWithAnotherScopeHeader` verify accounting before completion and isolation across sessions. Linux execution also covers the complete portable loop/provider suite; live-backend and remaining platform gates are separate.

The admitted ordinary chat paths use the actual Core access, approval and invocation services. Complete model responses, requested calls, durable starts and correlated results form their canonical JSONL history. Bootstrap contains instructions and scoped context without a rendered copy of the conversation. The final message shown in chat is marked as presentation, so it is not inserted into the next model request a second time.

The production-path fixture `sessionUsesRealCoreToolsAndCanonicalHistoryAcrossTurns` reads an actual file, changes it externally, reads it again, and checks the complete new content. It exercises both a warm session and a fresh store/orchestrator, with no legacy generation calls and one displayed final answer per turn. Providers without the capability are separately checked by `unsupportedUnifiedEngineCannotFallBackToLegacyGeneration`.

An interrupt holds an admission barrier across its target sessions until cancellation and queue cleanup settle. The barrier covers both new posts and inbox drains, including after approval waits. Queued IDs captured at control admission are cancelled; later submissions wait and then receive their own turn. Core owns each admitted post's preparation and actor dispatch task, so cancellation before RunState creation cannot start the model after the control reply. A partial interrupt-tree failure still cancels captured inputs for targets whose control records were durably written. A default interrupt preserves unanswered input: the orchestrator makes the skip decision before cancelling the admitted task. The real Debug fixture holds paused delivery after saving planning.request_input and verifies its task, generation and question link remain intact. Full canonical queued-input lifecycle and restart reconciliation remain in progress.

Messages accepted while an ordinary session is busy remain queued for their own turn. The current request uses a fixed journal snapshot and excludes undelivered user messages. The fixture `queuedFollowUpWaitsForItsOwnTurnInTheRealCoreInbox` verifies real Core enqueue, later delivery exactly once under the original message ID, and no legacy request. Bootstrap refresh updates the instruction slot rather than adding another conversation message. Explicit steering is still pending. A typed Auto route changes the current completion policy without resetting its budget. Choosing Build or Debug therefore retains the required verified finalizer, including after restoring its saved route.

`queuedFollowUpCannotSupersedeAnUnfinishedInputAfterRestart` covers retained, missing and corrupt inbox caches. `canonicalQueueContinuesWithAnUnavailableCacheDirectory` and `canonicalIngressAcceptsNewInputWithoutAWritableCache` cover an unavailable cache directory. `legacyQueuedInputMigratesBeforeItsCacheIsDiscarded` checks previous-format input, mode-command and attachment recovery through a second Core. `uiReceiptOwnsItsAcceptedSurfaceWithoutTheCache` checks a first-receipt crash prefix, duplicate action and actual semantic projection with dispatch held. `canonicalReceiptCannotBeReboundThroughAnotherIngress` and `unpreservedCorruptCacheCannotBlockOrOverwriteCanonicalReceipts` verify immutable receipt identity and preservation when the backup operation fails.

A fork determines input eligibility from the complete source journal before copying its chosen history. Queued, cancelled and failed inputs that never acquired an owner cannot become model context by cutting before their later status records. Untagged legacy history remains available. `forkCannotResurrectNeverAdmittedInput` verifies persisted copies and actual model requests for all three dispositions.

Retrying an already accepted active `clientMessageId` with the same payload returns its existing receipt with `replayed: true`. It does not add another inbox entry or hide the original task from the next model step. A changed payload is rejected. Before the original input is present in the canonical journal, the active retry is rejected rather than acknowledged as a second task. Core assigns an omitted input UUID before registering active ownership, so retrying the ID observed in the journal follows the same rules. The gated Core fixture `retryOfAnActiveInputDoesNotQueueOrHideTheOriginalTask` covers supplied and Core-generated IDs and checks the unchanged journal, one read/user row/count and the original task in both model requests. Distinct message IDs still use the ordinary follow-up queue.

Retrying a delivered `clientMessageId` with the same payload returns its saved presentation events with `replayed: true`. It does not request the model, execute another tool, append to the journal or count another user turn. A changed payload under that ID is rejected. The fixture `retryOfDeliveredClientMessageDoesNotExecuteAnotherTurn` checks both a warm service and a fresh Core/store. An unfinished accepted input with a compatible durable checkpoint can continue the same run and user turn. It restores the pinned model, counters, limits and recorded results without adding another user row or scoped context. The first complete acceptance record contains the pinned run snapshot and all scoped turn context together. A valid JSONL prefix ending there can resume even if the remaining initial status records were not written. Pre-persisted inbox messages retain their original user row. A settled Ask response can be published from its canonical saved response without another generation. Recovery that needs another generation still checks its pinned model and the current step capability. A settled answer or accepted completion can be published from the compatible journal even when that capability is no longer available. If only the authoritative completion result or its intermediate finalizing checkpoint survived, Core first writes a settled checkpoint and then publishes; no provider request or tool execution is needed. A missing checkpoint or newer user input still rejects unsupported recovery boundaries instead of granting a fresh turn. The filesystem-fault fixture `acceptedInputResumesFromTheDurableResultWithoutAnotherUserTurn` verifies fresh-Core recovery after a known result and a failed subsequent append. The parameterized fixture `acceptedInputRecoversOtherDurableBoundaries` also checks a fully written initial acceptance, valid first-record prefixes for new and pre-persisted messages, and a settled answer before presentation. Its prefix fixtures verify zero provider requests before the fault and the original task/context exactly once after restart. The same fixture disables the current step capability after saving either the end-turn answer or an accepted `session.complete`, and verifies delivery with no new generation or effect. A new interrupt of an unfinished unified run stores its stopping snapshot and generation in the control record before acknowledgement. A fresh Core returns that interruption without another model call. Older typed interrupt records without runtime metadata are bound to their live accepted input and take priority over a saved completion result. The recovery fixture verifies both formats, including no Done resurrection. Torn incomplete JSON records and durable approvals remain under integration; cancellation after an existing policy stop still notifies owned child work exactly once. The interrupt admission barrier and its cutoff are verified by the gated Core inbox fixture. Model projection places a queued input after the preceding task's saved responses and results, directly before its own scoped context. A compatible checkpoint retains active admission and standalone instruction records; the same restart fixture verifies both. When a later run compacts history, the projection also retains admission boundaries for kept user messages. The real inbox fixture verifies the previous answer, queued input and its answer remain in that order after a later checkpoint.

A distinct follow-up saved in the inbox waits for the accepted input after a restart. The journal retains that input's ownership until its terminal presentation is durable. Retrying it bypasses the waiting queue, restores its known result and keeps the follow-up out of its model context. Only never-admitted queued messages are excluded from the later-user conflict guard. `queuedFollowUpCannotSupersedeAnUnfinishedInputAfterRestart` verifies one original result, one original user row and a separate subsequent turn for the follow-up through a fresh Core. A fork retains immediate source agent/session/event provenance in the optional forkOrigin field. The shared runtime treats those copied records as historical context, rather than pending operations, checkpoints or completion authority. An ordinary new native fork turn and its historical answer/read content are verified by `forkedNativeHistoryCannotOwnTheForkedSession`. `deliveredInputRetryCannotEnterAnotherActiveTurnsQueue` verifies read-only replay while a different input is active. The inbox binds its ID to the full effective submission, including user, mode, model, effort, references, UI support and attachments; `queuedInputIdentityIncludesTheEntireEffectivePayload` checks conflicting reuse and unchanged saved bytes. `historicalUUIDCannotConsumeOrHideALiveQueuedInput` also verifies a new queued input reusing the source message's UUID: its live user row is retained, the old task stays visible to the current turn, and the new command appears once in its own turn. Copied messages receive independent presentation UUIDs, so existing clients can merge or reopen the transcript and subsequent fork-before/fork-through requests remain unambiguous. An actual historical presentation UUID cannot be claimed as a fresh direct, peer or UI input: `historicalPresentationIDsCannotBeClaimedByNewSubmissions` verifies rejection before acknowledgement, journal changes, queue insertion or an additional model request. `forkHistoryCannotSetRoutingOrWorkerAuthority` checks that historical finalizers and routes cannot restrict an independent session, establish its Auto mode or clear a live route. Gate-arrival and inbox-completion signals synchronize these fixtures without timing-based polling.

Repeated native reads execute through the common pipeline and return their actual results. The work ledger remains a bounded historical summary for compaction.

The common loop has filesystem/journal fixtures for failed writes, source-order projection, safe-read concurrency, bounded completion recovery, tool-free empty-answer repair, original turn budgets, unknown outcomes and durable cancellation. Core boundary fixtures cover failed durable starts, revoked policy, cancelled approval waits, owned deadlines and late actual results. A late result cannot accept a completion candidate, and a timeout placeholder cannot replace an already known actual result. Native selector aliases share this deadline and late-result handling.

A typed completion candidate is now committed with its result. A fresh journal reader can recover it if the following state checkpoint was lost, after checking the original invocation and finalizer policy. An identical scalar late-result payload cannot acquire that authority. The filesystem fixture `completionAuthoritySurvivesResultSnapshotGap` checks that recovery does not issue a second provider request or repeat the effect.

Results after the latest state checkpoint also restore their original policy stops and product-validated verification. Verification has a separate typed journal envelope: a similarly named field in an external tool's ordinary payload is not authoritative. The fixture `settledOutcomeTailRestoresOnlyProductAuthority` checks successful verification, a denied operation and a late scalar observation against a fresh file store. Work counters remain those committed before execution; replay does not charge them again or grant another budget.

A custom native host must supply a journal supporting typed product outcomes. A scalar-only journal can retain the actual tool result, but cannot accept a completion or discard verification silently: the loop stops with `durable_outcome_journal_required`. Core uses the typed journal implementation.

Summary caches are disposable. A failed cache update is logged without rejecting an outcome already synchronized to JSONL. History pages can rebuild their summary and control-state events from the canonical journal while the cache remains unavailable. Canonical write and validation failures still stop execution. `unavailableSummaryCacheCannotRejectADurableOutcomeOrHistoryPage` verifies the durable outcome, fresh history/control reads and unchanged JSONL while a directory blocks the cache file.

Canonical restart, durable approvals, steering/follow-up ownership and bounded transaction compaction are implemented for the supported unified entries. The sections below describe their contracts and owning fixtures. Existing planning defaults remain unchanged.

Current verification includes local Windows Core session fixtures and the portable runtime suite, plus Linux execution of selected full-Core integration tests and the portable/SDK suites in source-verified isolated copies. The full-Core copy keeps the production package manifest unchanged and resolves only its own platform dependency pins. Live-backend, supported-platform and independent final review gates remain outstanding. The [design](../designs/native-agent-loop.md) records those migration and rollout gates.

The Dashboard activity projection ignores historical calls, results and terminal statuses when calculating live tool indicators. A copied unfinished call remains visible without an active shimmer, and a historical result cannot settle a current call. Correlated results use callEventId before legacy name/order matching, so parallel calls of the same tool can complete out of order without marking the wrong call inactive. An unknown explicit correlation does not fall back to a different invocation. The production helper is exercised by `Dashboard/tests/sessionActivity.test.ts`; this changes activity calculation without changing layout or tool outcome labels.


Mock provides a single deterministic text response and never schedules tools. Claude Code has a native
single-step adapter using its existing official-CLI subscription gateway. That gateway admits one
upstream Messages generation with CLI tools disabled; Sloppy alone can schedule the next step or
execute a returned call. The adapter keeps signed thinking, raw arguments, usage and output limits,
and rejects continuation from another provider/model before generation. The actual process/admission
fixture `claudeCodeStepReturnsOneAdmittedGenerationAndReplaysSignedHistory` checks two successive
steps. It does not establish compatibility with every installed official CLI version or a live account.

## Delegated and remote execution

A native delegated worker keeps its own completion contract: `agent_delegate.finish`,
including in Ask mode. The accepted typed result ends the run before later calls in the same response
can execute. Missing completion receives bounded recovery using the original counters. A saved worker
or coordinator scope includes tool names, policy, working directory and additional filesystem roots.
An empty tool list authorizes no tools. Missing resource authority blocks restoration. Current policy
is rechecked, and a policy change requires a new authorized assignment. A closed worker's peer
conversation remains a separate restricted Ask turn.

A unified long-chat coordinator uses its existing assignment contract. Correctable tool failures or
Build/Debug without an accepted assignment may receive at most two continuations in the same run.
Its factual report check uses one tool-free native request with the same owner and request accounting.
The verdict stays internal; the verified answer is saved before settlement. An accepted assignment
confirms delegation, while worker reports establish what was actually delivered.

Remote Sloppy providers advertise `model_step_v1` before native use. HTTP uses the authenticated
`/v1/providers/step` endpoint; Console and Mesh use their existing trusted grants and cancellation
ownership. Unsupported protocol versions and continuation from another server, account or model are
rejected. Provider credentials remain on the serving computer; tools run on the requesting computer.
Legacy-only peers are rejected before native generation instead of silently selecting another loop.

HTTP and Linux Console fixtures verify tool rounds, signed continuation, authorization and cancellation.
The Mesh server's grant and cancellation fixtures pass, but the complete two-computer Mesh client
fixture remains unverified: Linux explicitly lacks its WebSocket implementation, and the Windows
fixture could not connect. Windows Console fixtures report an unsupported platform. These results
are platform limits on validation, and do not establish a successful live remote deployment.

Worker notifications retain their persisted system-message identity. In the unified engine they open
an internal report run, with the source ID and full-content fingerprint saved in its settings. They
create no user turn and expose no tools. Retrying a delivered source reads its existing result; a
changed payload cannot take over that source. The report and factual check share native accounting.
Hidden planning and report-review responses keep their own durable usage records while staying out
of ordinary assistant model history.

Memory checkpoint input follows the canonical admission rules. Never-admitted queued or cancelled
messages are excluded; admitted commands use their saved prepared meaning. Facts retain physical
journal order even when their displayed timestamps differ. Legacy untagged history remains available,
and thinking text remains excluded.


Automatic memory checkpoints for a unified session now use the common loop. Their canonical records
retain a typed reference to the completed foreground run, a separate run/turn, pinned model and
resource authority, and an explicit memory-tool scope. They do not enter the ordinary chat or model
history. A pending question, unfinished foreground task, unresolved effect or revoked source prevents
new automatic work. New user input and interrupt cancel registered background runs; current authority
is checked again immediately before an effect, including after approval. A failed native checkpoint
does not reset the foreground turn counter.

The scripted Core fixture `nativeMemoryUsesDurableCommonLoopWithoutChangingForegroundHistory`
completes a foreground Ask turn, runs its checkpoint, then opens the JSONL with a fresh store. It verifies
a separate settled checkpoint, one model attempt, no legacy generation and unchanged public history.
The three-case `automaticMemoryRequiresACompletedCurrentSource` fixture also checks pending input,
a newer active source, and a real approved file write that is denied after source replacement.
Startup restoration is additionally covered by `derivedRestartKeepsItsRunBudgetAndKnownToolResult`;
proactive attention has its own persisted source-review contract described below.


Manual checkpoint requests for unified sessions use the same source checks and native loop. The
public receipt and checkpoint status report failure when native execution fails or no eligible source
exists. A failed checkpoint preserves its source's user-turn count. The three-case fixture
`nativeMemoryPublicCompletionMatchesDurableOutcome` verifies manual success, a saved authentication
failure and a real user-scoped MEMORY.md update, including paired tool start/result and paged history.


## Embedded host

All native sends use the common engine. The optional `nativeEngine` argument remains source compatible;
`legacy`, `unified` and an omitted selector now choose the same native owner:

```swift
let host = SloppyRuntimeHost(nativeEngine: .unified)
```

Configure the host through its existing OpenAI or OAuth configuration method before starting new
work. `send` retains the project-scoped file/build tools and additional host capabilities. Keep a UUID
in its optional `clientMessageID` argument when a caller needs retry/restart identity. The same ID
requires the same prompt and image bytes. A completed retry reads its saved response without model
credentials or another build. An unfinished retry retains the saved model, budget and workspace.

Unified embedded history lives under `.ada/workspace/native-agent-v1/agents`, with a checked
compatibility marker beside it. Legacy `.ada/workspace/agents` history remains separate. A future or
missing marker is rejected rather than overwritten. A started effect without a durable result requires
explicit reconciliation; the host does not assume cancellation undid that effect. The owning host
saves follow-ups before waiting and serializes them by stored conversation, including different UI
channels pointing at the same session. Cancelling a queued caller retires its input without executing
it or blocking the next follow-up. After restarting the host, retry saved client message identities in
journal order with the original prompt and images; the application supplies its build/tool callbacks.

`embeddedHostUsesDurableSharedLoopAndIsolatesLegacyStorage` executes an actual project file write
and build handler through the shared loop and verifies durable paired results and unchanged legacy
history. `embeddedRestartRetainsReceiptAndNeverReplaysUnknownEffects` cuts that real journal at a
settled checkpoint or started effect, then uses a fresh public host without credentials. It checks
durable terminal delivery, read-only repeated delivery, no unknown-effect replay, and rejection of a
future format. These are scripted host checks, not evidence of a live mobile/provider rollout.


An unfinished native memory checkpoint resumes its saved internal run after a restart. Known tool
results, attempts, work rounds, original context, model and provider/cache scope remain attached to that
run. `derivedRestartKeepsItsRunBudgetAndKnownToolResult` cuts a real checkpoint after a saved MEMORY.md
result, applies an external correction and resumes with a fresh Core; the old effect is not repeated.
A new checkpoint retains the existing explicit model override (including Autodream configuration).
Changing that override does not replace the model of an unfinished checkpoint. Autodream records a
failed checkpoint as failed and keeps the source eligible for its later pass. Core shutdown cancels
registered background owners and blocks new derived admissions during shutdown.

Embedded provider/cache scope includes both the canonical workspace and stored conversation, even
when two callers reuse a UI channel ID. The two-workspace fixture
`embeddedCacheScopeIncludesWorkspaceAndStoredConversation` verifies this with actual file/build work.

With existing context preparation enabled, the common loop checks the final prepared messages,
continuation, schemas and image estimate against the configured model input budget after output
reservation. A request that cannot fit fails before generation or tools, retaining its journal and typed
context failure. The existing disabled preparation setting remains disabled. Bounded compaction of eligible older plain text and completed typed transactions is available as described below.
Older large tool outputs can use verified artifact references.


When protected input can fit after reducing eligible older history, the common loop can request a
tool-free summary under the same owner. Summary attempts and usage belong to that run. A checkpoint
is appended only after validating its original prefix and verifying that the complete candidate
projection fits. Canonical JSONL records are retained. The original objective, recent user input and
current task remain in the projection. Core upgrades its paired storage protection before this format
is written.

Compaction covers complete historical transactions and preserves unresolved tool transactions,
verification evidence, images, input lifecycle records and the active owner. Summaries can include
typed response/call/result content and verified artifact references. A derived run cannot borrow hidden foreground history for summarization. Unsupported or
insufficient compaction stops explicitly instead of sending empty history. An authentication error,
tool call from the summarizer or oversized candidate leaves the previous projection unchanged.
`nativeCompactionKeepsCanonicalHistoryAndProtectedTask` and
`backgroundCompactionCannotBorrowHiddenForegroundHistory` exercise the actual runtime and file
journal. `failedCompactionRetainsItsPreviousProjection` covers all three failure paths. This does not
yet claim archival or compaction of every supported history shape.

A typed context-overflow response from the provider can use the same single compaction allowance,
even when the local estimate fits. The retry retains the same run and step with a fresh attempt ID.
A transport retry after compaction keeps the compacted projection. Repeated context overflow stops;
authentication errors do not trigger compaction. The allowance is persisted before summarization
and renewed only after the entire model/tool step settles, including its durable tool outcomes.
`providerContextOverflowCompactsOnceAndKeepsRetryProjection` checks these four provider paths.
`contextRecoveryRemainsSpentUntilTheWholeToolStepSettles` holds a real file-read effect and inspects
both live and durable counters before allowing its result to settle.

Compaction preserves attached image bytes in the protected projection. Hidden summary responses
remain available in the raw journal for usage and recovery, but do not appear as chat messages or
affect session previews and message counts. Older disposable summary caches are rebuilt from the
canonical journal before serving those counts.

## Steering an active unified session

Omitting `deliveryIntent`, or choosing `follow_up`, keeps the message for the next task. An explicit
`steering` message joins the current owner at a completed model/tool step. For example, post this body
to `/v1/agents/<agentId>/sessions/<sessionId>/messages`, using a fresh UUID for `clientMessageId`:

```json
{
  "userId": "local",
  "content": "Use the corrected requirement.",
  "clientMessageId": "9ea4c07a-c16f-419c-bd6b-c37ede4d0fe2",
  "deliveryIntent": "steering"
}
```

Omit model, mode and reasoning overrides on steering. It changes task context without expanding the
run's authority. Peer messages and UI-form actions cannot acquire steering authority through this
field. Accepted completion and cancellation take priority; input after accepted completion belongs to
the next run. The loop rechecks steering after compaction before freezing a request. Transport retries
keep the frozen request. Steering receipts settle with their original owner and do not supersede its
restart identity. `coreSteeringUsesTheCurrentRunAndSettlesItsReceipt` verifies the Core example;
`steeringDuringCompactionEntersTheNextFrozenRequest` covers both compaction entry paths.

## Durable approvals and original effects

Core saves pending approvals and decisions under `.runtime/tool-approvals-v1.json` before publishing
or releasing a waiter. A compatible fresh Core restores them. Corrupt or unsupported storage cannot
authorize a new request. A native permit binds the original run, step, attempt, call, arguments, tool
declaration and resource restrictions; it cannot transfer to another run or changed arguments or
directories. JSON Schema `required` ordering is normalized as a set, without relaxing restrictions.

An unfinished requested call with no durable start or result can continue through the common tool
pipeline with its original identity and deadline. Current policy and cancellation are checked again.
Known results are retained; started effects without outcomes still require reconciliation and cannot
be replayed automatically. `restartContinuesTheOriginalApprovedEffectWithoutAnotherToolResponse`
uses a real file write and crash prefix to verify one original start/result and no repeated model tool
response. `savedApprovalCannotTransferToChangedAuthorityArgumentsOrRun` exercises rejected transfers.

## Archived tool output

A complete tool observation larger than 16 KiB is synchronized to a generated JSON artifact before
its reference enters the journal. This path has no 25 MiB upload ceiling: the filesystem fixture covers
a 26 MiB output. New schema-2 references replace duplicate inline data/error bytes in JSONL. Public
session readers hydrate the original result; missing, corrupted or mismatched canonical blobs cause an
explicit read error. Schema-1 inline journals remain readable. Core requires both protected profiles at
writer version 8; embedded journals use marker version 4 and accept version-3 readers for migration.

The blob includes the complete invocation result, including typed verification/completion data. Its
reference binds the agent, conversation, size and SHA-256 digest. Current observations and authority
remain protected in model projection. A compact older observation does not discard its full artifact.

Core supports `Range: bytes=start-end` on the session attachment endpoint, with at most 1 MiB per
response. Valid ranges return 206 and `Content-Range`; unsupported/out-of-bounds ranges return 416.
Embedded callers use the verified APIs below without running Core:

```swift
let outputs = try await host.toolOutputArtifacts(
    workspaceURL: workspace, persistedSessionID: conversationID)
if let output = outputs.first {
    let preview = try await host.readToolOutput(
        workspaceURL: workspace, persistedSessionID: conversationID,
        artifactID: output.attachment.id, limit: 16_384)
    print(String(decoding: preview.data, as: UTF8.self))
    let stream = try await host.streamToolOutput(
        workspaceURL: workspace, persistedSessionID: conversationID,
        artifactID: output.attachment.id)
    for try await chunk in stream {
        // Consume each bounded Data chunk before asking for the next one.
        consume(chunk)
    }
    try await host.exportToolOutput(workspaceURL: workspace,
        persistedSessionID: conversationID, artifactID: output.attachment.id,
        to: destination)
}
```

`workspace`, `conversationID`, `destination` and `consume` belong to the embedding application.
The stream verifies a private snapshot once and pulls at most 64 KiB per iteration. Cancellation or
sequence disposal removes that snapshot. Export verifies the same bytes it copies and refuses to
replace an existing destination. Chunk reads capture bytes during their verification pass.
`ArtifactStorageTests` exercises these public APIs, exact bytes, corruption and cancellation.

On Apple platforms, `SloppyToolOutputArtifactView(host:workspaceURL:artifact:)` supplies a 16 KiB preview
and a complete-output save/share action. `SloppyChatMessage.artifacts` links outputs to host transcript
rows. The SwiftUI branch still requires Apple build/UI validation; Linux filesystem tests do not compile it.

Settled turns attempt cleanup of generated, unreferenced artifacts older than 24 hours. The explicit
`cleanupToolOutputs` API accepts a cutoff at least one hour old. Cleanup holds an exclusive session
lease and keeps every canonical artifact and message attachment, including verification/completion
roots. Arbitrary user files and active-session blobs are not eligible.

## Native self-improvement proposals

An explicitly unified agent's proposal review now uses the same durable background owner as native
memory checkpoints. It borrows a completed current source and pins its model, tool scope, restrictions,
context and failure-review setting. Proposal submissions create or update reviewable tasks through the
existing handler; they do not edit source code. Interrupted work retains known outcomes, and a settled
review of the same source does not automatically repeat its effects. Background generations stay out
of ordinary chat history. `nativeProposalReviewUsesTheDurableOwnerAndRestrictedTools` verifies the
native entry point and its structured `nothing` decision. Workflow agent nodes, goal continuations
and ACP-origin session requests already enter through `postAgentSessionMessage`; their entry-point fixtures verify the canonical owner. External ACP agents keep their own loop.
Goal scheduling and product controllers remain separate from model-step ownership.


## Pinned policy versions and fresh verification

New unified admissions pin `planningPolicyVersion` (currently 1) and `evidencePolicyVersion`.
Omitting the evidence version preserves version 1 behavior. To require verification after the most
recent tracked mutation, set these fields in the agent runtime configuration:

```json
{
  "type": "native",
  "planningPolicyVersion": 1,
  "evidencePolicyVersion": 2
}
```

Keep the agent's existing unified engine selection. This fragment changes policy versions only.
Version 2 binds evidence to a persisted work revision. Unknown or mutating effects advance it before
execution; only explicitly whitelisted safe reads preserve it. Build/Debug completion rejects stale
evidence and requires a fresh successful check. Starts after the last state checkpoint restore the
revision too. This detects tracked effects, not unobserved external filesystem changes. Unsupported
versions are rejected; older clients omitting these fields do not erase saved versions.
`EvidenceFreshnessTests`, `EvidenceRecoveryTests`, `StrictEvidencePolicyTests` and the strict native
coding fixture cover state, journal and Core completion paths.

## Routing, format fallback and auxiliary requests

Automatic model selection runs before admission, excludes models without single-step capability and
pins its selected model. It does not change the model of an unfinished owner. Unified routing state
lives in the run configuration. Native routing remains in the pinned run state; legacy configuration spelling does not enable another loop.

For OpenAI Chat Completions with Responses fallback enabled, an eligible typed compatibility failure
selects Responses for the next counted loop attempt. One step attempt performs one HTTP generation;
fallback consumes the saved retry schedule and can be disabled. Compatible Chat content survives the
format change, while foreign continuation state remains rejected. Planner, compactor and report-review
requests also use the owner's recovery budget and persist the actual successful attempt identity.

## Startup and proactive attention

Core scans canonical sessions once during startup and resumes pending memory checkpoints,
self-improvement reviews and proactive source reviews through their existing owners. Concurrent
scheduler requests join the same operation. Saved prompts, scopes, model, known results and consumed
budgets survive. Unknown started effects require reconciliation. Explicit cancellation is terminal.
After an eligible provider/credential failure, a later invocation may continue the same run in a new
generation; it cannot reset its budgets or repeat known effects.

A unified proactive source review stores its frozen snapshots, source/configuration digests and
restricted `heartbeat.report` scope in a protected heartbeat session (journal format `native_v7`).
Reports pass ordinary Core declaration, schema, policy and approval checks. Recovery reads successful
correlated reports from the journal rather than assistant prose. Repeated requests for the same source
within the heartbeat interval reuse a completed review. Normal/checklist heartbeat, workflow agent
nodes, goal starts and ACP-origin native prompts are covered by `NativeConsumerEntryTests`;
`NativeProactiveWorkTests` covers report recovery and expired startup credentials.

## Embedded steering

`SloppyRuntimeHost.send` accepts the optional `deliveryIntent: .steering` argument alongside the
existing prompt/session/build callbacks. Omission or `.followUp` keeps the durable next-turn behavior.
Steering joins the active owner at the next completed step. Both native selector spellings support it. The parameterized embedded fixture checks both delivery modes with a held tool effect.
Applications still resupply executable callbacks on restart. Independent hosts/processes contend on
an OS-held session lease and fail before enqueueing another owner's work. Same-host callers share
that lease and preserve FIFO. An awaited callback that sends to its own conversation receives
`HostError.reentrantSend`; publish a later input from the surrounding application instead of recursively
waiting inside the current callback. This guard covers inherited task-local callback contexts, not
arbitrary dependency cycles deliberately created with detached tasks.


## Storage ownership and compatibility

One Core owns approval and native journal writes per workspace. A second Core can read existing data,
but cannot approve or execute native work. Its message endpoint returns 409 `workspace_unavailable`.
Shutdown cancels its workers before dropping ownership. Outstanding factual late-result writes retain
the original lease; a successor cannot take the workspace until those writes finish. A closed store
cannot regain write authority when another Core opens the same path. Lockfiles remain in place;
the operating system releases ownership when the last handle closes, including process exit.

The old native provider scheduling implementations have been removed. `RuntimeSystem` compatibility
entry points forward to `AgentLoop`; their low-level tool callback API uses a transient journal, while
Core and embedded hosts use durable file journals. Built-in native providers implement
`ModelStepProviderFactory`. A third-party provider must implement that capability before native use;
unsupported providers fail before tool effects. The standalone AnyLanguageModel `respond` and
`streamResponse` APIs remain unchanged.

On first send, an embedded host imports eligible old plain history into the isolated native store as
historical records, copying attachments and leaving the original files unchanged. Unresolved old calls
are rejected for reconciliation instead of replayed. Original conversation identities and callbacks
remain application responsibilities.


Core forks and checkpoint continuations copy eligible factual history into the new journal on first
preparation. Copied tool correlations and attachment files belong to the destination; source run
controls and input-delivery authority are not inherited. Removing the source does not remove the copy.

Tool-free compatibility calls also use the common loop's bounded provider retry and empty-answer
repair. Context diagnostics describe the actual prepared typed frame. A policy stop retains its
specific exit reason, and failed transient turns retain their history for the next request.

An effect that finishes after cancellation can append its factual result, but cannot supply a new
completion candidate or verification authority. Structural argument errors return typed correction
feedback to the same bounded recovery policy as other argument validation failures.
