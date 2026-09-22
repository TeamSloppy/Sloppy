# Optional semantic decisions and JEV model routing

Status: initial implementation

## Goal

Sloppy may use a machine-oriented decision model to improve bounded runtime choices without making that service a prerequisite. The first use case is choosing an executor model profile for a user turn. Later use cases may include tool-approval review, completion review, and branch/worker routing.

The invariant is:

> Sloppy determines the permitted choices, the semantic provider evaluates those choices, and deterministic Sloppy policy decides whether to apply the result.

When semantic decisions are disabled, unconfigured, unavailable, invalid, or insufficiently confident, Sloppy follows the pre-existing model-selection flow.

## Architecture

`SemanticDecisionProvider` is separate from `ModelProvider`. A decision provider returns typed choices, scores, or probabilities; it never generates the agent response and never executes side effects.

The initial provider is JEV through either:

- TypeSafe: `POST https://api.typesafe.ai/v1/systemone`;
- Vercel AI Gateway's TypeSafe-compatible endpoint: `POST https://ai-gateway.vercel.sh/typesafe/v1/systemone`.

Both transports use the same normalized internal choice contract. Credentials are read from a configured environment-variable name and are never written to `sloppy.json`, logs, receipts, or session events.

## Executor model routing

JEV selects a stable profile, not an arbitrary model ID. Each configured profile contains:

- a profile ID such as `fast`, `balanced`, or `senior`;
- an exact Sloppy-routable model ID;
- a description of the work suitable for the profile.

Before calling JEV, Sloppy removes profiles whose models are unavailable to the agent. At least two eligible profiles are required.

Selection precedence is:

1. valid per-turn explicit model override;
2. JEV profile when routing is `active` and confidence meets policy;
3. agent catalog `selectedModel`;
4. existing runtime/provider default.

An explicit but unavailable per-turn override preserves the existing fallback behavior and does not invoke JEV. The selected model is fixed for the complete turn and its tool loop.

### Modes

- `disabled`: never call JEV;
- `shadow`: call and meter JEV, but keep the existing selected model;
- `active`: apply an eligible result at or above `minimumConfidence`.

Every error is fail-open to the existing model-selection flow. There is no fallback generative-model call.

## Request state and privacy

The first routing request contains only:

- current user request text;
- chat mode;
- attachment MIME types;
- eligible profile IDs and descriptions.

It does not contain credentials, tool results, full session history, memory contents, or file contents unless those are already present in the user's request. Future use cases must define their own minimal state contract.

## Usage and cost accounting

For every successful JEV response Sloppy records, per channel and for the current Core process:

- request count;
- input tokens;
- output tokens;
- total USD cost;
- the portion of cost that is estimated.

Vercel's `provider_metadata.gateway.cost` is treated as provider-reported cost. When the response does not include cost (including direct TypeSafe responses), Sloppy estimates input cost using `inputCostPerMillionTokensUSD`. The default is the public launch price of `$0.042` per million input tokens; users can override it as pricing changes. Estimated values are displayed with `~`.

The initial counter is process-lifetime telemetry. Persistence across Core restarts is intentionally deferred until a general inference-spend ledger is specified.

The `/v1/token-usage` response includes optional `semanticDecisionUsage`. The TUI `/context` card displays JEV calls, input tokens, and cost for the current session channel.

## Configuration

```json
{
  "semanticDecisions": {
    "provider": "vercel",
    "apiKeyEnvironmentVariable": "AI_GATEWAY_API_KEY",
    "executorModelRouting": "shadow",
    "minimumConfidence": 0.75,
    "inputCostPerMillionTokensUSD": 0.042,
    "modelProfiles": {
      "fast": {
        "model": "openai-oauth:gpt-6-luna",
        "description": "Routine questions and small, low-risk edits."
      },
      "balanced": {
        "model": "openai-oauth:gpt-6-sol",
        "description": "Normal implementation, debugging, and tool use."
      },
      "senior": {
        "model": "openai-oauth:gpt-6-astra",
        "description": "Architecture, broad changes, difficult debugging, and high-stakes correctness."
      }
    }
  }
}
```

For direct TypeSafe use, set `provider` to `typesafe` and expose `TYPESAFE_API_KEY`. `baseURL` and `model` are optional escape hatches; provider-specific defaults are used when omitted.

## Future use cases

The shared provider contract may later support:

- tool review: `approve`, `human_review`, `reject` without granting authorization;
- completion review: `complete`, `verify_more`, `continue`, `blocked`;
- route selection: `respond`, `spawn_branch`, `spawn_worker`, `request_input`;
- recovery: `retry_changed`, `alternate_tool`, `ask_user`, `stop`.

Permissions, sandbox checks, path validation, rate limits, actual test/build results, and side effects remain deterministic responsibilities of Sloppy.

