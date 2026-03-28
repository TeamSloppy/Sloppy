---
layout: doc
title: Build From Terminal
---

# Build From Terminal

This guide covers the direct local workflow for building and running Sloppy without Docker.

## Supported environments

| Platform | Status | Notes |
| --- | --- | --- |
| macOS 14+ | Supported | Primary local development environment |
| Linux | Supported | CI runs on Ubuntu with Swift 6.2 and `libsqlite3-dev` |

## Prerequisites

### Swift runtime

- Swift 6 toolchain
- `sqlite3` runtime available on the machine

### Dashboard runtime

- Node.js
- npm

### Linux packages

On Ubuntu or Debian-based systems, install the SQLite development headers before building:

```bash
sudo apt-get update
sudo apt-get install -y libsqlite3-dev
```

## Resolve dependencies

From the repository root:

```bash
swift package resolve
```

## Build the Swift targets

Development build:

```bash
swift build
```

Release builds:

```bash
swift build -c release --product sloppy
swift build -c release --product Node
swift build -c release --product App
```

## Preferred local launcher

From the repository root:

```bash
swift package --allow-writing-to-package-directory --allow-network-connections all sloppy-run
```

This command:

- builds `Dashboard` with `npm run build` by default
- builds `sloppy` in release mode
- launches `sloppy` in the foreground

Useful variants:

```bash
swift package --allow-writing-to-package-directory --allow-network-connections all sloppy-run --no-dashboard
swift package --allow-writing-to-package-directory --allow-network-connections all sloppy-run --config-path sloppy.json
swift package --allow-writing-to-package-directory --allow-network-connections all sloppy-run --no-dashboard --oneshot
```

The plugin requires SwiftPM permission flags because it writes the Dashboard bundle into the package directory and may run `npm install` when `Dashboard/node_modules` is missing or unusable.
Direct forwarding without `--` is intentionally supported only for common `sloppy` flags: `--oneshot`, `--run-demo-request`, and `--config-path`.
Use `--` for any other `sloppy` arguments.

## Run the Swift targets manually

Start the sloppy runtime directly:

```bash
swift run sloppy
```

Useful runtime variants:

```bash
swift run sloppy --oneshot
swift run sloppy --run-demo-request
swift run sloppy --config-path sloppy.json
```

Run the other executables when needed:

```bash
swift run Node
swift run App
```

## Run the Swift tests

Full suite:

```bash
swift test --parallel
```

Run a single test or group:

```bash
swift test --filter sloppyTests.postChannelMessageEndpoint
swift test --filter sloppyTests
swift test --filter AgentRuntimeTests
```

List tests:

```bash
swift test list
```

## Run the dashboard

From `Dashboard/`:

```bash
npm install
npm run dev
```

Production build:

```bash
npm run build
```

Preview the production bundle:

```bash
npm run preview
```

## Typical local development loop

1. Start `sloppy` from the repository root with `swift package --allow-writing-to-package-directory --allow-network-connections all sloppy-run`.
2. If you need the Vite development server, start the dashboard from `Dashboard/` with `npm run dev`.
3. Make a focused code change.
4. Run the smallest relevant verification first.
5. Before opening a PR, run the CI-parity checks listed below.

## CLI commands

Once the server is running you can interact with it from any terminal using the `sloppy` CLI:

```bash
sloppy --version          # verify the binary is in PATH
sloppy status             # check server connectivity
sloppy update             # check for a newer version
sloppy agent list         # list configured agents
sloppy config get         # inspect runtime config
```

See the [CLI Reference](/guides/cli) for the full command set.

## CI-parity checks

These are the commands the repository expects contributors to keep green:

```bash
swift test --parallel
swift build -c release --product sloppy
swift build -c release --product Node
swift build -c release --product App
cd Dashboard
npm install
npm run build
```

## Notes

- On first `swift package sloppy-run` or `swift run sloppy`, Sloppy can create a workspace layout and a default `sloppy.json`.
- The generated config includes `visor.scheduler.enabled`, `visor.scheduler.intervalSeconds`, `visor.scheduler.jitterSeconds`, and `visor.bootstrapBulletin`.
- Model providers use environment variables for API keys when no key is set in config. See the [Model Providers](./models.md) guide for details.
- Ollama uses the local endpoint by default and requires no API key.
- The plugin only builds the production Dashboard bundle; it does not start the Vite dev server.

### Environment variables

| Variable | Purpose |
| --- | --- |
| `OPENAI_API_KEY` | OpenAI model provider |
| `GEMINI_API_KEY` | Google Gemini model provider |
| `ANTHROPIC_API_KEY` | Anthropic Claude model provider |
| `BRAVE_API_KEY` | Brave web search tool |
| `PERPLEXITY_API_KEY` | Perplexity web search tool |

Environment values take precedence over empty `sloppy.json` keys but are overridden when a config key is explicitly set.
