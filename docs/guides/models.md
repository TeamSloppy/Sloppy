---
layout: doc
title: Model Providers
---

# Model Providers

Sloppy supports multiple LLM providers. Each provider is configured as an entry in the `models` array inside `sloppy.json` (or via the Dashboard UI). At runtime, models are resolved by prefix (`openai:`, `gemini:`, `anthropic:`, `ollama:`) and routed to the corresponding provider implementation.

## Supported providers

| Provider | Prefix | Default API URL | Env variable | Auth |
| --- | --- | --- | --- | --- |
| OpenAI API | `openai:` | `https://api.openai.com/v1` | `OPENAI_API_KEY` | API key |
| OpenAI Codex (OAuth) | `openai:` | `https://chatgpt.com/backend-api` | — | OAuth device code |
| Google Gemini | `gemini:` | `https://generativelanguage.googleapis.com` | `GEMINI_API_KEY` | API key |
| Anthropic | `anthropic:` | `https://api.anthropic.com` | `ANTHROPIC_API_KEY` | Console API key (`sk-ant-api…`) |
| Anthropic (OAuth) | `anthropic:` | `https://api.anthropic.com` | `ANTHROPIC_API_KEY` | OAuth / setup token (see below) |
| Ollama | `ollama:` | `http://127.0.0.1:11434` | — | None |

## Environment variables

Environment variables provide a way to configure API keys without writing them into `sloppy.json`. When both an environment variable and a config key are set, the config key takes precedence.

| Variable | Provider | Description |
| --- | --- | --- |
| `OPENAI_API_KEY` | OpenAI | API key for OpenAI models |
| `GEMINI_API_KEY` | Gemini | API key for Google Gemini models |
| `ANTHROPIC_API_KEY` | Anthropic | Console API key or OAuth/setup token for Claude (direct `api.anthropic.com` only) |
| `BRAVE_API_KEY` | Search | API key for Brave web search tool |
| `PERPLEXITY_API_KEY` | Search | API key for Perplexity web search tool |

## Config file format

Each model entry in `sloppy.json` has four fields:

```json
{
  "models": [
    {
      "title": "openai-api",
      "apiKey": "",
      "apiUrl": "https://api.openai.com/v1",
      "model": "gpt-5.4-mini"
    }
  ]
}
```

| Field | Description |
| --- | --- |
| `title` | Identifier used to infer the provider when the model string has no prefix. Must contain the provider name (e.g. `openai-api`, `gemini`, `anthropic`, `ollama-local`). |
| `apiKey` | API key for authenticated providers. Leave empty to use the environment variable. |
| `apiUrl` | Base URL for the provider API. Override for proxied or self-hosted endpoints. |
| `model` | Model identifier passed to the provider. Can include a prefix (`openai:gpt-5.4-mini`) or be plain (`gpt-5.4-mini`). |

## Provider examples

### OpenAI

```json
{
  "title": "openai-api",
  "apiKey": "",
  "apiUrl": "https://api.openai.com/v1",
  "model": "gpt-5.4-mini"
}
```

With `OPENAI_API_KEY` set in the environment, `apiKey` can stay empty. Supports Chat Completions and Responses API variants with automatic fallback.

### Google Gemini

```json
{
  "title": "gemini",
  "apiKey": "",
  "apiUrl": "https://generativelanguage.googleapis.com",
  "model": "gemini-2.5-flash"
}
```

Get an API key from [Google AI Studio](https://aistudio.google.com/apikey). The probe endpoint fetches the full model list from the Gemini API.

### Anthropic

Sloppy supports two ways to authenticate against the **direct** Anthropic API (`https://api.anthropic.com`): a **Console API key** or an **OAuth / setup / subscription-style token**. The model prefix is always `anthropic:`; only the credential type changes.

#### Console API key

Use a key from [Anthropic Console](https://console.anthropic.com/). Console keys typically start with `sk-ant-api`.

```json
{
  "title": "anthropic",
  "apiKey": "",
  "apiUrl": "https://api.anthropic.com",
  "model": "claude-sonnet-4-20250514"
}
```

With `ANTHROPIC_API_KEY` set in the environment, `apiKey` can stay empty. Available models include Claude Sonnet 4, Claude 3.7 Sonnet, Claude 3.5 Sonnet, Claude 3.5 Haiku, and Claude 3 Opus.

#### OAuth, setup tokens, and Claude Code

If you use **Anthropic OAuth**, **setup tokens**, or tokens aligned with **Claude Code** (not the Console `sk-ant-api` keys), put that value in `apiKey`, or set `ANTHROPIC_API_KEY` to the same value. Sloppy sends the right headers for direct `api.anthropic.com` requests based on the key shape.

Example entry (same fields as above; the difference is the token you paste):

```json
{
  "title": "anthropic-oauth",
  "apiKey": "",
  "apiUrl": "https://api.anthropic.com",
  "model": "claude-sonnet-4-20250514",
  "providerCatalogId": "anthropic-oauth"
}
```

The optional `providerCatalogId` field is set automatically when you use the Dashboard preset; you can omit it if you edit JSON by hand.

**Dashboard:** open **Settings → Providers**, then add the **Anthropic (OAuth)** preset (or paste an OAuth/setup token into the API key field for an Anthropic row). The OAuth preset uses placeholder text that matches setup-style tokens.

**Third-party proxies** (Bedrock bridges, self-hosted gateways, etc.): point `apiUrl` at your proxy and use the **proxy’s** API key. Do not rely on OAuth-style heuristics for non-Anthropic hosts—Sloppy treats those endpoints as third-party and uses `x-api-key` with whatever secret you configure.

**Probe:** connection tests use `providerId` `anthropic` for both Console keys and OAuth tokens; the probe sends the same auth rules as runtime.

### Ollama

```json
{
  "title": "ollama-local",
  "apiKey": "",
  "apiUrl": "http://127.0.0.1:11434",
  "model": "qwen3"
}
```

No API key needed. Point `apiUrl` at any running Ollama instance. The probe endpoint queries `/api/tags` to list locally available models.

### Multiple providers

The `models` array supports multiple entries. `sloppy` builds a composite model provider that routes requests based on the model prefix:

```json
{
  "models": [
    {
      "title": "openai-api",
      "apiKey": "",
      "apiUrl": "https://api.openai.com/v1",
      "model": "gpt-5.4-mini"
    },
    {
      "title": "gemini",
      "apiKey": "",
      "apiUrl": "https://generativelanguage.googleapis.com",
      "model": "gemini-2.5-flash"
    },
    {
      "title": "anthropic",
      "apiKey": "",
      "apiUrl": "https://api.anthropic.com",
      "model": "claude-sonnet-4-20250514"
    }
  ]
}
```

## Model selection for agents

Each agent has a `selectedModel` field in its config that determines which model it uses. The value includes the provider prefix:

| Provider | Example `selectedModel` |
| --- | --- |
| OpenAI | `openai:gpt-5.4-mini` |
| Gemini | `gemini:gemini-2.5-flash` |
| Anthropic | `anthropic:claude-sonnet-4-20250514` |
| Ollama | `ollama:qwen3` |

Set this via:

- **Dashboard** — Agent settings page, model dropdown
- **API** — `PUT /v1/agents/:id/config` with `{ "selectedModel": "gemini:gemini-2.5-flash" }`
- **Onboarding** — model selection step during first-run setup

## Model resolution flow

1. `sloppy` reads the `models` array from config at startup.
2. Each entry is resolved to a prefixed identifier (e.g. `openai:gpt-5.4-mini`) using either an explicit prefix in the `model` field or by inferring the provider from `title` and `apiUrl`.
3. Factory classes build provider instances for each recognized prefix.
4. A `CompositeModelProvider` combines all active providers.
5. When an agent runs, its `selectedModel` is matched against supported models and routed to the correct provider.

## Adding providers via CLI

You can also manage providers directly from the terminal without opening the Dashboard:

```bash
# List currently configured providers
sloppy providers list

# Add a new provider
sloppy providers add \
  --title "openai-api" \
  --api-url "https://api.openai.com/v1" \
  --api-key "$OPENAI_API_KEY" \
  --model "openai:gpt-5.4"

# Test connectivity
sloppy providers probe --provider-id openai --api-key "$OPENAI_API_KEY"

# List models from an OpenAI-compatible endpoint
sloppy providers models \
  --api-url "https://api.openai.com/v1" \
  --api-key "$OPENAI_API_KEY"

# Remove a provider
sloppy providers remove "openai-api"
```

See the [CLI Reference](/guides/cli#provider-commands) for all provider commands.

## Adding providers via Dashboard

### Onboarding

The first-run onboarding wizard (step 2) shows all providers as cards. Select a provider, enter the API key, click **Test connection** to probe, then select a model from the returned list.

### Settings

Open **Settings → Providers** in the Dashboard. Use **Add provider** or a preset card. For Anthropic, choose **Anthropic** (Console API key) or **Anthropic (OAuth)** (OAuth / Claude Code–style token). Click **Manage** on a row to open the configuration modal. Enter the API key and API URL, select a model, and click **Save Provider**. The config is saved to `sloppy.json` immediately.

## Provider probe API

The `/v1/providers/probe` endpoint tests connectivity for any provider:

```bash
curl -X POST http://localhost:25101/v1/providers/probe \
  -H "Content-Type: application/json" \
  -d '{"providerId": "gemini", "apiKey": "YOUR_KEY"}'
```

Supported `providerId` values: `openai-api`, `openai-oauth`, `gemini`, `anthropic`, `ollama`.

The response includes `ok`, `message`, and a `models` array with available model options.
