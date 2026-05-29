# ADR 0001: Self-Improvement Loop

- Status: Proposed
- Date: 2026-05-29

## Context

Sloppy already has pieces of a self-improvement loop: memory checkpoints can preserve durable observations, proposal review can turn observations into reviewable tasks, and a weekly curator can group related proposals. These pieces need an explicit architecture boundary so runtime learning does not become direct self-mutation.

The system builds agents, so behavior decisions must come from typed runtime and tool signals rather than language heuristics. The loop must not classify state, progress, intent, completion, tool use, or branching by matching localized text fragments such as status filler or translated phrases. If intent matters, the signal must be represented through explicit runtime events, tool records, task state, structured model output, or persisted metadata.

## Decision

Treat self-improvement as a gated pipeline:

1. Capture durable facts through memory checkpoints.
2. Detect improvement signals from typed runtime and tool events.
3. Create or update proposal tasks with evidence and subsystem tags, always as `pending_approval` review artifacts.
4. Curate related proposals into patch-plan tasks.
5. Implement only after an operator approves a patch task.

Proposal review remains restricted to project and visor tools plus the internal typed proposal-submit tool. It may collect context, inspect tasks, and submit reviewable proposal intent, but it must not run shell commands, edit files, install skills or MCP servers, or change prompts directly.

Failure-triggered proposals must include a structured `Failure Classification`. Every proposal task must include evidence, affected subsystem, risk, definition of done, and verification notes so it can be reviewed independently of the chat that produced it.

The weekly curator remains responsible for duplicate grouping, prioritization, and patch-plan creation. The curator should produce patch-plan tasks that are still reviewable artifacts, not executable authority.

## Non-Decision

This ADR does not authorize autonomous self-patching. The self-improvement loop must not run shell commands, edit repository files, install skills or MCP servers, or mutate prompts directly from chat output, memory output, or proposal output.

## Implemented Now

- Memory checkpoints can capture durable observations from runtime activity.
- Self-improvement proposal review can create reviewable improvement tasks.
- A weekly curator can group duplicate or related proposals and prepare patch-plan tasks.
- Proposal review is intended to stay within project and visor tool boundaries.

## Next Changes

- Add a persistent review queue that makes proposal, curator, and patch-plan state explicit.
- Add a typed proposal-submit schema for action, confidence, durability, affected subsystem, evidence, failure classification, and verification commands.
- Ensure failure-triggered proposals consistently emit a structured `Failure Classification`.
- Ensure proposal and patch-plan records carry evidence, affected subsystem, risk, definition of done, and verification fields as first-class data.
- Add metrics for queued reviews, proposal-submit outcomes, curator grouping, retry counts, and approval latency.
- Keep implementation approval as an explicit operator action on a patch task.

## Consequences

Positive:

- Self-improvement becomes auditable from memory checkpoint to proposal to patch plan to approval.
- Duplicate observations can be grouped before they become implementation work.
- The runtime avoids accidental mutation caused by chat output, localized text, or ambiguous model phrasing.
- Operators can review evidence, risk, and verification before authorizing a change.

Negative:

- The loop is slower than fully autonomous self-patching.
- More metadata must be collected and maintained for each proposal.
- Some low-risk improvements still wait for curator grouping and operator approval.
