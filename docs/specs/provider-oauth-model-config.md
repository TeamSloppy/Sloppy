# Provider, OAuth, and Model Configuration Spec

## 1. Document Status
- Version: `0.1`
- Date: `2026-06-03`
- Status: `Draft for product and implementation alignment`
- Owners: `sloppy`, `Dashboard`, `Provider Integrations`
- Primary code areas: `Sources/sloppy/CoreService+Providers.swift`, `Sources/sloppy/Providers/*`, `Sources/sloppy/Gateway/Routers/ProvidersAPIRouter.swift`, `Dashboard/src/features/config/ConfigView.tsx`, `Dashboard/src/features/config/configModel.ts`

## 2. Product Context
Sloppy supports multiple language-model providers and authentication modes. Operators need a safe way to configure provider endpoints, API keys, OAuth credentials, default models, search providers, and ACP targets without editing runtime files by hand.

## 3. Goals
1. Centralize provider configuration for Dashboard, TUI, CLI, and runtime workers.
2. Support first-party OAuth/device-code flows where available.
3. Probe provider health and model catalogs before an operator commits settings.
4. Keep secrets out of logs, events, transcripts, and Dashboard payloads.
5. Allow local OpenAI-compatible providers and hosted APIs to coexist.

## 4. Non-goals
1. Managing organization billing or quotas at provider side.
2. Guaranteeing model availability after provider-side changes.
3. Implementing every provider-specific feature in the generic config UI.
4. Storing plaintext secrets in project docs or session history.

## 5. Supported Provider Categories
| Category | Examples | Notes |
| --- | --- | --- |
| OpenAI-compatible HTTP | OpenAI API, OpenRouter, LM Studio, local servers | Usually uses `/v1/models` and chat/responses-compatible endpoints. |
| OAuth-backed providers | OpenAI OAuth, Anthropic OAuth, Gemini OAuth | Uses browser/device-code flows and stored credentials. |
| Local providers | Ollama, LM Studio, custom OpenAI-compatible URLs | API key may be optional. |
| Search providers | Brave, Perplexity-style integrations | Exposed to tools such as web search/fetch where configured. |
| ACP targets | External coding-agent transports | Probed separately from normal LLM APIs. |

## 6. Functional Requirements

### FR-1: Runtime config read/write
- Clients can fetch and update runtime configuration through `/v1/config`.
- Config updates validate provider entries, required fields, and known enum values.
- Updates must not echo secrets unless intentionally represented as redacted placeholders.

### FR-2: Provider probe
- Clients can probe a provider with candidate settings before saving.
- Probe returns actionable status, errors, and discovered models when available.
- Probe should distinguish network failure, authentication failure, unsupported endpoint, and empty catalog.

### FR-3: Model catalog discovery
- OpenAI-compatible model discovery resolves `/v1/models` even when the base URL includes or omits `/v1`.
- Provider-specific catalog fetchers normalize results into common model option records.
- Dashboard model pickers should display provider, model ID, and any useful capability hints.

### FR-4: OAuth flows
- OAuth start endpoints return the URL or device-code instructions needed by UI/CLI.
- OAuth complete/poll endpoints store credentials and return connection status.
- Disconnect endpoints revoke or remove local credentials where supported.
- Import endpoints can reuse local credentials from companion CLIs when supported.

### FR-5: Channel and agent model selection
- Agents can have default model/provider configuration.
- Channels can override model selection for inbound channel sessions.
- Task and worker execution may carry selected model metadata for auditability.

### FR-6: Secret handling
- Secrets must be encoded or stored via the configured secret codec/store.
- API responses, logs, system logs, stream events, debug payloads, and generated specs must redact secret values.
- Replacing a config entry should not accidentally delete an existing secret unless the request says so.

## 7. Public API Surface
Representative endpoints:
- `GET /v1/config`
- `PUT /v1/config`
- `POST /v1/providers/probe`
- `POST /v1/providers/openai/models`
- `GET /v1/providers/openai/status`
- `POST /v1/providers/openai/oauth/device-code/start`
- `POST /v1/providers/openai/oauth/device-code/poll`
- `POST /v1/providers/openai/oauth/disconnect`
- `POST /v1/providers/anthropic/oauth/start`
- `POST /v1/providers/anthropic/oauth/complete`
- `POST /v1/providers/gemini/oauth/start`
- `POST /v1/providers/gemini/oauth/complete`
- `GET /v1/providers/search/status`
- `GET /v1/channels/{channelId}/model`
- `PUT /v1/channels/{channelId}/model`
- `DELETE /v1/channels/{channelId}/model`

## 8. Dashboard UX
1. Config view groups provider settings by provider/category.
2. Operators can test settings before saving.
3. OAuth buttons show clear connection state: disconnected, waiting, connected, expired, or error.
4. Model pickers avoid stale options by allowing refresh/probe.
5. Secret inputs show redacted saved state and an explicit replace/clear affordance.

## 9. Edge Cases
- A base URL ending in `/v1` must not become `/v1/v1/models`.
- Local providers may accept empty API keys; hosted providers generally should not.
- OAuth device-code polling can expire; UI must show retry instructions.
- Provider probe may succeed while generation fails due to model-specific limitations; errors should include model ID.
- Config write conflicts should be resolved by last-write-wins only if no versioning exists; otherwise clients should include version.

## 10. Acceptance Criteria
1. An operator can add an OpenAI-compatible provider, probe it, save it, and select a model for an agent.
2. OAuth connection flow completes and provider status changes to connected without exposing tokens in API responses.
3. Clearing a channel model override returns the channel to inherited defaults.
4. A bad provider URL produces a specific, user-actionable probe error.
5. Dashboard never renders raw secrets after refresh.

## 11. Tests / Verification
- Backend: provider probe tests, OAuth service tests, secret codec tests, config read/write tests, channel model store tests.
- Dashboard: config form, OAuth redirect, model picker and provider status behavior.
- Manual: configure local LM Studio/OpenAI-compatible endpoint, connect OAuth provider, run one agent session on selected model.
