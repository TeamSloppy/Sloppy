# Agent Information Saturation Evaluation

Status: in progress  
Date: 2026-09-19  
Scope: Sloppy native agent runtime and offline session evaluation

## Progress

- Task 1 implementation complete: typed offline analyzer and deterministic fixtures added.
- Task 2 implementation complete: terminal diagnostics are embedded in the final
  `run_status` event as a backward-compatible optional field.
- Source parsing and `git diff --check` pass.
- Focused SwiftPM tests are currently blocked by a pre-existing mixed-toolchain cache:
  `Protocols.swiftmodule` was built with Swift 6.3.2 while the active CLI is Swift 6.2.4.
  The shared `.build` directory was not deleted or reset.
- A separate scratch build was attempted first and stopped because SwiftPM was waiting on
  the recursive `swift-acp` TypeScript SDK submodule checkout.

## Goal

Determine whether weak agent outcomes come from missing evidence, failed context delivery,
poor use of delivered evidence, or inefficient execution after enough evidence has already
been collected.

The evaluation must not infer state from natural-language phrases. It uses typed session
events, explicit fixture definitions, runtime metrics, verification evidence, and externally
scored task outcomes.

## Pilot evidence

The first retrospective trace used session
`session-d4931568-4658-4a2d-a212-07b3083b16f8`.

- The agent inspected 19 unique source paths and reached the relevant plan publication,
  protocol, browser-panel, and chat view-model layers.
- Two delegated research tasks failed because their selected model was unsupported.
- The parent continued with 61 tool rounds against a configured limit of 60.
- The trace contains 14 separate edits to `ChatModels.swift` and no final verification or
  `session.complete` call.
- The runtime reported `did_reset_context=false`; the failure was the tool-round limit, not
  a compaction failure.
- Other successful sessions completed in 6-49 tool rounds. One completed with 140 tool calls
  in 25 rounds, showing that raw tool-call volume is not the limiting factor.

Initial hypothesis: this failure was caused primarily by poor phase and budget management,
not by a lack of retrieved information.

## Evaluation model

For each benchmark task, track the following typed pipeline:

1. Evidence is available in an identified source.
2. The agent invokes the tool needed to inspect that source.
3. The resulting evidence is delivered to the model context.
4. The evidence survives any compaction or session transition.
5. The agent applies the evidence to the implementation or answer.
6. External verification confirms the final decision.

An evidence slot is satisfied only by an explicit fixture rule, such as a tool name plus an
exact argument value. The evaluator must not guess whether a fact was found by matching
localized prose in model output.

## Benchmark conditions

Run every golden task at least three times under the same model settings.

1. **Baseline**: current production agent and normal tools.
2. **Oracle context**: the same task plus a compact packet containing all required evidence.
3. **Forced acquisition**: normal tools, but implementation is blocked until all required
   evidence slots have been observed.

Optional fourth condition: a second model under the same oracle context to estimate the
reasoning ceiling independently from retrieval.

## Metrics

- Evidence coverage: satisfied required slots / all required slots.
- Delivery coverage: evidence included in the actual model input / evidence acquired.
- Utilization: correctly applied evidence / evidence delivered.
- Tool calls and model/tool rounds by explicit phase.
- Calls per round and repeated mutation concentration per resource.
- Failed tool and delegated-task counts.
- Remaining round budget when mutation and verification begin.
- Verification evidence and final externally scored outcome.
- Scope leakage, conflict resolution, and post-compaction retention.

## Work items

### Task 1: Offline typed trace analyzer

- Add a pure analyzer over `[AgentSessionEvent]`.
- Require callers to provide the tool-to-phase map and evidence-slot definitions.
- Report phase counts, failed results, exact resource concentration, evidence coverage,
  completion observation, and optional typed runtime round metrics.
- Add deterministic Swift Testing coverage.

Definition of done: fixture events produce stable metrics without reading model prose or
service log strings.

### Task 2: Persist typed terminal run metrics

- Add a backward-compatible session event for terminal run diagnostics.
- Persist `toolRoundsUsed`, `maxToolRounds`, exit reason, context reset/compaction state,
  tool error counts, duration, and explicit completion state.
- Stop requiring service-log parsing for evaluations.

Definition of done: new and old session JSONL files decode, and a completed or limited run
contains one typed diagnostics event.

### Task 3: Expose evaluation reports

- Add a read-only Core service/API operation for evaluating an existing session.
- Return machine-readable metrics and a compact Markdown rendering.
- Keep session contents and credentials out of the report unless explicitly requested.

Definition of done: the pilot session can be evaluated without direct filesystem or log
inspection.

### Task 4: Golden fixtures

- Add direct recall, multi-source integration, correction precedence, project isolation,
  compaction retention, and implementation evidence fixtures.
- Include at least one real coding trace and synthetic traces for precise failure attribution.
- Record expected evidence slots and external outcome assertions.

Definition of done: deterministic coverage catches missing acquisition, failed delivery,
cross-project leakage, and premature finalization.

### Task 5: Controlled live runner

- Run Baseline, Oracle, and Forced-acquisition conditions in isolated evaluation sessions.
- Use the same model, reasoning effort, tool policy, repository state, and task fixture.
- Store results separately from normal user sessions and memory.

Definition of done: repeated runs produce a comparison report with variance and no writes to
normal agent memory.

### Task 6: Budget policy experiment

- Compare the current global round limit with explicit acquisition, mutation, verification,
  and finalization reserves.
- At the warning threshold, require a typed phase transition instead of natural-language
  self-assessment.
- Do not ship a runtime policy change until golden tasks show improved completion without
  reduced correctness.

Definition of done: the policy is selected from measured results rather than the single pilot
failure.

## Validation boundary

Deterministic tests establish event accounting and context-delivery contracts. They do not
prove that a live model makes better decisions. Product claims require the controlled live
matrix and external scoring.
