# Model Selection and Routing Current Flow Spec

## 1. Document Status
- Version: `0.1`
- Date: `2026-06-05`
- Status: `Current-state reference before planner/executor model changes`
- Owners: `sloppy`, `Dashboard`, `Agent Runtime`
- Primary code areas: `Dashboard/src/features/config/ConfigView.tsx`, `Dashboard/src/features/config/components/ModelRoutingEditor.tsx`, `Dashboard/src/features/agents/components/AgentChatTab.tsx`, `Sources/sloppy/CoreService+Providers.swift`, `Sources/sloppy/Providers/CoreModelProviderFactory.swift`, `Sources/sloppy/Agent/AgentSessionOrchestrator.swift`, `Sources/sloppy/Tools/AgentTools/Agents/WorkersSpawnTool.swift`, `Sources/AgentRuntime/RuntimeSystem.swift`

## 2. Product Context
Sloppy lets operators configure multiple language-model providers, select default models for agents, override models for individual chat turns, and define model aliases for skill-driven workers. The current system already exposes `fast` and `heavy` aliases in Dashboard, but those aliases are simple string substitutions rather than an automatic planner/executor policy.

This document describes the current behavior only. It is intended to be the baseline for a future PRD where a stronger model may plan work and a cheaper or faster model may execute planned steps.

## 3. Goals
1. Document how configured provider rows become runtime model IDs.
2. Document where Dashboard displays and persists model selection state.
3. Distinguish agent default model selection from `modelRouting` aliases.
4. Explain when `modelRouting.fast` and `modelRouting.heavy` are actually used.
5. Identify current gaps before designing planner/executor routing.

## 4. Non-goals
1. Designing the future planner/executor architecture.
2. Changing provider authentication, probing, or model catalog behavior.
3. Changing how skills declare preferred models.
4. Adding automatic model-quality, cost, or latency classification.
5. Guaranteeing model availability after provider-side catalog changes.

## 5. Core Concepts
| Concept | Description |
| --- | --- |
| Provider row | An entry in `CoreConfig.models` with title, API URL, auth data, provider catalog ID, model, and disabled state. |
| Runtime model ID | Canonical model identifier used by runtime, usually prefixed as `openai-api:...`, `openai-oauth:...`, `openrouter:...`, `ollama:...`, `gemini:...`, `anthropic:...`, `opencode:...`, or `mock:...`. |
| Available models | Server-side model picker source returned to clients from configured providers and inferred fallbacks. |
| Agent selected model | The persisted default model on an agent config. Used for normal agent session turns unless a valid per-turn override is supplied. |
| Per-turn selected model | Optional `selectedModel` on a chat request. Used only when it exactly matches an available model for the agent. |
| Model routing alias | A flat string map in `CoreConfig.modelRouting`, for example `fast -> openai-api:gpt-5.4-mini`. |
| Skill preferred model | Optional `model:` frontmatter in a skill `SKILL.md`. When a worker is spawned with `skillId`, this value may be mapped through `modelRouting`. |
| Runtime default model | The first supported/resolved model used by `RuntimeSystem` when no explicit model is provided. |

## 6. Current Functional Flow

### FR-1: Runtime config loading in Dashboard
- `ConfigView` fetches runtime config through the API, normalizes it, and stores both `savedConfig` and `draftConfig`.
- A local unsaved draft may be restored from `localStorage`.
- Config saves call `updateRuntimeConfig`, then refresh provider status records.
- Provider-row changes in the Providers section can auto-save independently from the global Save button.

### FR-2: Provider rows and model catalogs
- Dashboard provider presets create or edit rows under `draftConfig.models`.
- Provider rows include auth mode, API URL, selected model, disabled state, and optional `providerCatalogId`.
- Provider model pickers can probe providers through backend endpoints before a row is saved.
- Disabled provider rows are skipped by catalog aggregation.

### FR-3: Runtime model ID resolution
- Backend resolves configured rows into prefixed runtime model IDs.
- Rows that already contain a supported prefix are preserved.
- Unprefixed model names are prefixed by inferred provider type when possible.
- `openai:` legacy IDs are rejected by the resolver.
- If model inference is enabled, environment-backed fallbacks may be added for OpenAI API, OpenAI OAuth, or OpenRouter.
- If no available model options exist, the agent model list falls back to `openai-api:gpt-5.4-mini`.

### FR-4: Available model list
- The server-side source of truth for model pickers is `listAvailableProviderModels`.
- Available model options include canonical IDs, display titles, inferred capabilities, and context window hints where known.
- OpenAI OAuth model cache can enrich or extend the available model list after OAuth catalog fetches.
- Dashboard may merge server-side available models with live provider probe results for config pickers.

### FR-5: Agent default model selection
- Agent configuration stores `selectedModel`.
- When reading an agent config, the store canonicalizes the persisted model against available models.
- If a native-runtime agent has no selected model, it is assigned the first available model.
- Persisted model values may be retained if allowed by the persisted-model policy.

### FR-6: Normal agent session model selection
- A posted agent session message may include `selectedModel`.
- The per-turn model override is accepted only if it is present in the agent's available model IDs.
- If the override is missing, empty, or unavailable, the session uses the agent config `selectedModel`.
- `modelRouting` aliases are not applied to normal session messages.
- Reasoning effort is passed only when the selected model advertises a `reasoning` capability and the agent runtime is native.

### FR-7: Runtime default fallback
- `CoreService` builds the active model provider from current config and resolved model IDs.
- `RuntimeSystem` receives both the provider and a default model.
- For direct inline runtime responses, an explicit model wins; otherwise runtime uses its default model.
- If no model provider/default model is configured, runtime emits a static fallback response.

### FR-8: Model routing aliases in Dashboard
- The Model routing settings section edits `draftConfig.modelRouting`.
- The UI exposes two first-class aliases: `fast` and `heavy`.
- Both aliases are selected from the same aggregated model catalog used for agent default model picking.
- Clearing an alias removes that key from `modelRouting`.
- Additional aliases can be edited only through the raw Config JSON view.

### FR-9: Model routing aliases in workers
- `workers.spawn` accepts an optional `skillId`.
- When `skillId` is present, the tool reads the installed skill's `SKILL.md`.
- If the skill frontmatter declares `model: <value>`, that value is treated as the worker's preferred model.
- If `<value>` matches a key in `CoreConfig.modelRouting`, the mapped concrete model ID replaces it.
- The resulting non-empty string becomes `WorkerTaskSpec.selectedModel`.
- If no skill model is declared, no routing alias exists, or the skill cannot be read, the worker is spawned without a selected model and falls back to normal runtime defaults.

## 7. Current End-to-End Examples

### Example A: Normal agent chat
1. Operator configures provider row `openai-api` with model `gpt-5.4-mini`.
2. Backend resolves it as `openai-api:gpt-5.4-mini`.
3. Agent config stores `selectedModel = openai-api:gpt-5.4-mini`.
4. User sends a chat message without `selectedModel`.
5. Session orchestrator uses the agent config selected model.
6. `modelRouting.fast` and `modelRouting.heavy` are not consulted.

### Example B: Per-turn override
1. Agent has available models `openai-api:gpt-5.4-mini` and `anthropic:claude-sonnet-4-6`.
2. Dashboard sends a message with `selectedModel = anthropic:claude-sonnet-4-6`.
3. Session orchestrator checks that the ID is available.
4. That model is used for this turn only.
5. The agent config selected model remains unchanged.

### Example C: Skill-driven worker with alias
1. Config contains `modelRouting.heavy = anthropic:claude-sonnet-4-6`.
2. Installed skill `SKILL.md` declares `model: heavy`.
3. Agent calls `workers.spawn` with that `skillId`.
4. `WorkersSpawnTool` reads the skill model value `heavy`.
5. The tool resolves `heavy` through `config.modelRouting`.
6. Worker is created with `selectedModel = anthropic:claude-sonnet-4-6`.

### Example D: Skill-driven worker without alias
1. Installed skill `SKILL.md` declares `model: anthropic:claude-sonnet-4-6`.
2. Agent calls `workers.spawn` with that `skillId`.
3. The model value does not need alias resolution.
4. Worker is created with `selectedModel = anthropic:claude-sonnet-4-6`.

## 8. Dashboard UX
1. Providers section manages provider rows, auth status, model probing, and selected provider model values.
2. Agent chat and agent configuration surfaces use available model options for normal model selection.
3. Model routing section labels aliases as shortcuts for `model:` in skill frontmatter and `workers.spawn` with `skillId`.
4. Model routing does not present itself as automatic task planning or model delegation.
5. Raw Config view is the escape hatch for advanced alias keys beyond `fast` and `heavy`.

## 9. Edge Cases
- A provider row may be saved with a model that later disappears from the provider catalog.
- Live Dashboard probes may show models that differ from server-side available models if credentials or provider status change between requests.
- A per-turn model override is ignored unless it exactly matches an available model ID.
- An alias can point to a model string that is not currently available; current worker alias resolution does not validate the mapped model against available models.
- A skill can declare a concrete model ID directly, bypassing alias mapping.
- A worker without `skillId` does not use skill preferred model metadata.
- A worker with `skillId` but missing/corrupt `SKILL.md` silently falls back to no selected model.
- `fast` and `heavy` names are conventional UI aliases, not semantic runtime roles.

## 10. Known Gaps Before Planner/Executor Design
1. There is no typed concept of `plannerModel` or `executorModel`.
2. There is no automatic split where one model writes a plan and another model performs tool steps.
3. There is no runtime policy that classifies tasks by complexity, cost, latency, or risk.
4. There is no validation that `modelRouting` values are currently available or compatible with requested capabilities.
5. There is no explicit handoff contract between a planning model and an execution model.
6. There is no eval suite measuring whether a heavy-planner/fast-executor split improves quality, cost, or latency.

## 11. Acceptance Criteria for This Current-State Spec
1. A reader can distinguish provider configuration, agent selected model, per-turn override, runtime default, and model routing aliases.
2. A reader can explain why `fast` and `heavy` aliases do not currently implement planner/executor behavior.
3. A reader can trace how a skill `model: heavy` becomes a concrete worker `selectedModel`.
4. Future PRD work can reference this document as the baseline behavior.

## 12. Tests / Verification References
- Backend model resolution: `CoreModelProviderFactory.resolveModelIdentifiers`, `CoreService.availableAgentModels`.
- Agent config model persistence: `AgentCatalogFileStore`.
- Normal session selection: `AgentSessionOrchestrator` selected model handling.
- Worker skill model routing: `WorkersSpawnTool.resolveSpawnSelectedModel`.
- Dashboard config behavior: `ConfigView`, `ModelRoutingEditor`, `AggregatedModelPicker`, `aggregateProviderModels`.
