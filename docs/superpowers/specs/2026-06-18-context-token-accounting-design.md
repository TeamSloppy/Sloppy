# Context Token Accounting and Lean Bootstrap Design

## Goal

Reduce real per-turn input token cost and make context usage understandable and correct enough to drive compaction. Sloppy should distinguish context-window occupancy from newly billed input, cached input, cache creation, completion, and reasoning tokens.

## Problem

Agent sessions currently build a large bootstrap that can include agent documents, project context, installed skills, memory, and runtime rules. Runtime sessions cache this bootstrap in memory and providers may report cached input, but the UI and compaction logic mostly expose aggregate prompt/completion usage. This makes small turns look expensive, obscures whether caching worked, and can trigger compaction from the wrong signal.

## Non-Goals

- Do not remove agent documents or skills support.
- Do not rely on phrase heuristics to decide what the model intends.
- Do not make provider billing assumptions when a provider does not report cache details.
- Do not change model behavior by default without tests covering prompt content and session recovery.

## Approach

Implement a context accounting layer that records the shape of each model request in stable categories:

- `system_instructions`
- `bootstrap_static`
- `tools_schema`
- `session_transcript`
- `current_turn`
- `attachments`
- `memory`
- `planner`
- `tool_results`
- `reserved_output`

Each category should carry estimated tokens, source label, and whether it is cacheable, cached by provider report, or uncached. Provider-reported usage remains authoritative for actual turn billing fields when available.

## Metrics

Use separate metrics for separate decisions:

- `contextWindowUsedTokens`: estimated effective occupancy of the current model context window.
- `contextWindowFreeTokens`: context window minus used tokens and reserved output.
- `lastTurnInputTokens`: provider-reported input tokens for the last call.
- `lastTurnCachedInputTokens`: provider-reported cache read tokens.
- `lastTurnCacheCreationInputTokens`: provider-reported cache creation tokens.
- `lastTurnUncachedInputTokens`: `max(0, input - cached)`.
- `lastTurnCompletionTokens`
- `lastTurnReasoningTokens`

Compaction should use effective context-window occupancy, not cumulative historical token usage and not uncached billing alone. Cached input can be cheaper, but it still occupies context.

## Lean Bootstrap

Add a lean bootstrap policy for ordinary agent-session turns. The bootstrap should contain a compact manifest for large documents and skills instead of always embedding full contents:

- agent document names, paths, and short descriptions
- installed skill names, descriptions, paths, and entrypoints
- project context availability and refresh marker
- memory availability and retrieval instructions

Full contents should be embedded when they are small, explicitly required by the mode, required for first-turn safety, or loaded through a typed file/tool action. The policy should be explicit and testable, not inferred from localized text.

## Provider Cache Strategy

Keep stable cache prefixes stable across turns:

- Anthropic-compatible providers should keep `cache_control` on stable high-value content.
- OpenAI OAuth should keep stable `prompt_cache_key` values and include a fingerprint that changes when bootstrap/tool/schema content changes.
- Provider cache details should be persisted through existing `cachedInputTokens` and `cacheCreationInputTokens` fields.

If a provider does not report cache details, UI should label cached values as unavailable instead of showing false zeroes when possible.

## UI and User Explanation

Update `/context` to show two sections:

1. Context window occupancy by category, including free space and reserved output.
2. Last-turn token economics, including input, cached, uncached, cache creation, output, and reasoning.

The display should make these cases obvious:

- Large context, low uncached input: cache is helping but window still fills.
- Small context, high uncached input: current turn or tools are expensive.
- Unknown provider cache data: billing split is unavailable.

The composer status line can stay compact, but `/context` should be the source of truth.

## Architecture

Add a `ContextLedger`-style value in runtime or a nearby service boundary. It should be created when preparing a model call, before invoking `LanguageModelSession`, and updated with provider usage after the call completes. Persist only stable summaries needed for UI and compaction; avoid storing full prompt text in token accounting records.

Runtime compaction should consult the latest ledger snapshot for a channel. If no ledger exists, fall back to the current estimator and provider-reported prompt usage.

## Testing

Add focused tests for:

- bootstrap categories are counted separately from current user messages
- cached and uncached last-turn tokens are displayed separately
- compaction uses context-window occupancy, not cumulative usage
- lean bootstrap replaces large skill/document bodies with manifest entries
- provider cache fingerprints change when bootstrap/tool/schema inputs change
- session recovery still restores enough context after process restart

## Rollout

1. Add ledger types and internal snapshots without changing behavior.
2. Wire `/context` to display ledger data with current token usage fallback.
3. Move compaction pressure to ledger occupancy.
4. Enable lean bootstrap behind a config flag or agent setting.
5. Make lean bootstrap the default once tests and manual sessions show no quality regression.
