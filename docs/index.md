---
layout: doc
title: What is Sloppy?
---

# Sloppy

Local-first control plane for observable AI workflows.

Sloppy is a self-hosted runtime you run on your own machine or server. It becomes the coordination layer between your AI agents, your conversation channels, and your tools — keeping every step inspectable, persisted, and under your control.

Who is it for? Developers and teams who want AI agents they can observe, extend, and trust — without giving up their data or relying on a hosted black box.

## What is Sloppy?

Sloppy combines a Swift HTTP server and actor-based orchestration kernel with a React operator dashboard. You deploy a single `sloppy` process; it handles everything from message ingestion to model calls, background task execution, memory maintenance, and event emission.

Entry points (Terminal UI, Telegram, Discord, HTTP API) deliver messages to the runtime. The runtime decides how to respond — inline, via a spawned worker, or through a focused branch — and keeps a complete typed record of every decision. The dashboard lets you watch it all happen in real time.

## What makes it different?

- **Local-first**: runs on your hardware, your rules, your data stays put
- **Actor-isolated concurrency**: channels, workers, branches, and memory each run in isolation — no shared mutable state
- **Observable by design**: every action becomes a typed runtime entity and a persisted event you can inspect or replay
- **Multi-channel**: one process serves Telegram, Discord, and the HTTP API simultaneously
- **Plugin-extensible**: add model providers, tools, memory backends, and gateway channels via `PluginSDK`
- **Open source**: AGPL-3.0-only server/runtime with MIT SDK and native-client surfaces

## How it works

```mermaid
flowchart LR
  telegram["Telegram"]
  discord["Discord"]
  api["HTTP API"]
  core["Core\n(Swift server)"]
  runtime["AgentRuntime"]
  workers["Workers"]
  branches["Branches"]
  memory["Memory"]
  dashboard["Dashboard\n(React)"]

  telegram --> core
  discord --> core
  api --> core
  core --> runtime
  runtime --> workers
  runtime --> branches
  runtime --> memory
  dashboard --> core
```

Core is the single entry point. All traffic — from channels, the CLI, or the dashboard — flows through it. The `AgentRuntime` owns scheduling and supervision; everything downstream is handled internally.

## Key capabilities

### Multi-channel gateway

A single Sloppy instance handles Telegram, Discord, and HTTP API channels concurrently. Each channel is an isolated runtime context with its own message history and context tracking.

### Agent runtime

The orchestration kernel decides how to process each message: respond inline, spawn a background worker for long-running tasks, or fork a branch for focused sub-task execution. Workers and branches run in actor isolation.

### Memory and compaction

Sloppy maintains persistent memory across sessions. When a channel's context window approaches capacity, the compactor automatically summarizes history and stores the result in memory — keeping the agent effective without manual intervention.

### Visor supervision

Visor runs continuously in the background, monitoring worker health, detecting timeout conditions, maintaining memory freshness, and publishing status bulletins so agents always have current system context. See [Visor overview](/visor/overview).

### Web dashboard

The React operator dashboard shows live channel activity, agent state, memory, workers, and configuration. It connects directly to the Core API.

### Terminal UI

The `sloppy` command opens a full-screen terminal UI for local project chat. It restores the last agent/session for the current directory, supports multi-session tracking, model and provider pickers, slash commands, and inline project files with `@path`. See [Terminal UI](/tui/overview) and [Multi-session TUI](/tui/multi-session).

### Plugin system

Model providers (OpenAI, Anthropic, Gemini, Ollama), tools, memory backends, and gateway channels are all loaded via the `PluginSDK` plugin contracts — no core changes required.

## Quick start

On macOS (Apple silicon) or Linux (x86_64), install the ready-to-run CLI and Dashboard:

```bash
curl -fsSL https://sloppy.team/install.sh | bash
```

No Swift, Node.js, or Git is required. On Windows, paste into PowerShell:

```powershell
irm https://sloppy.team/install.ps1 | iex
```

Windows installs a prebuilt package with runtime DLLs; no development tools are needed. A release containing the full Windows archive must be published first. Open a new terminal, then run:

```bash
sloppy       # terminal UI
sloppy run   # server + Dashboard
```

Prefer an app? [Download for macOS](https://github.com/TeamSloppy/Sloppy/releases/download/v2.5.0/SloppyClient-macos-universal-2.5.0.pkg)
or open the [iOS App Store page](https://apps.apple.com/app/id6811777701) after publication.

See [Install](/install) for supported platforms and options, [Build From Terminal](/guides/build-from-terminal)
for source builds, or [Build With Docker](/guides/build-with-docker).

## Dashboard

`sloppy run` serves the operator dashboard automatically. Open it in your browser at:

- Local default: `http://localhost:25102`

The dashboard shows channels, agent activity, memory, and configuration in real time. For the approved visual identity, wordmark, typography, and design rules see [Sloppy Visual Design](/dashboard-style).

## Configuration (optional)

API keys go in a `.env` file at the repository root:

```bash
OPENAI_API_KEY=your_key
GEMINI_API_KEY=your_key
ANTHROPIC_API_KEY=your_key
SLOPPY_CA_CERTS=/path/to/extra-ca.pem
```

Runtime configuration lives in `sloppy.json`. If you do nothing, Sloppy uses sensible defaults and picks up any API keys from the environment.

See [Model Providers](/guides/models) for provider-specific setup, [Terminal UI](/tui/overview) for interactive local chat, and [CLI Reference](/guides/cli) for all runtime commands.

## Start here

| Guide | Description |
| --- | --- |
| [Install](/install) | Get Sloppy running from the terminal or with Docker |
| [Terminal UI](/tui/overview) | Use the full-screen local terminal chat, multi-session list, model picker, and slash commands |
| [CLI Reference](/guides/cli) | All `sloppy` subcommands and flags |
| [Relay Deployment](/guides/relay) | Connect work and home Sloppy instances through a personal VPS |
| [Model Providers](/guides/models) | Configure OpenAI, Gemini, Anthropic, and Ollama |
| [Channels](/channels/about) | How channels work and how to set up Telegram and Discord |
| [Agents](/agents/runtime) | Runtime internals: workers, branches, and scheduling |
| [Visor](/visor/overview) | Supervision, health monitoring, and system bulletins |

## Learn more

| Resource | Description |
| --- | --- |
| [Project Design](/architecture/project-design) | Full architecture: modules, runtime flows, persistence, and design goals |
| [API Reference](/api/reference) | HTTP endpoints grouped by resource with parameters and responses |
| [Specifications](/specs/channel-plugin-protocol) | Channel plugin protocol and runtime PRD |
| [Plugins](/guides/plugins) | How to build and load plugins via PluginSDK |
