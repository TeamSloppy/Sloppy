---
layout: doc
title: Install
---

# Install

Two ways to get Sloppy running: directly from the terminal or with Docker Compose.

## Terminal

### Prerequisites

| Dependency | Notes |
| --- | --- |
| Swift 6 toolchain | macOS 14+ or Linux |
| `sqlite3` | Runtime dependency |
| Node.js + npm | For Dashboard |

On Ubuntu/Debian install SQLite headers first:

```bash
sudo apt-get update && sudo apt-get install -y libsqlite3-dev
```

### Quick start

```bash
git clone https://github.com/TeamSloppy/Sloppy.git
cd Sloppy
swift package resolve
swift package --allow-writing-to-package-directory --allow-network-connections all sloppy-run
```

This builds the Dashboard, compiles `sloppy` in release mode, and starts it.

Verify the installation and check connectivity:

```bash
sloppy --version
sloppy status
```

For details see [Build From Terminal](/guides/build-from-terminal) and the [CLI Reference](/guides/cli).

## Docker

### Prerequisites

| Dependency | Notes |
| --- | --- |
| Docker | Engine + CLI |
| Docker Compose | v2 plugin |

### Quick start

```bash
git clone https://github.com/TeamSloppy/Sloppy.git
cd Sloppy
docker compose -f utils/docker/docker-compose.yml up --build
```

| Service | URL |
| --- | --- |
| `sloppy` | `http://localhost:25101` |
| `dashboard` | `http://localhost:25102` |

For details see [Build With Docker](/guides/build-with-docker).

## Environment variables

Create a `.env` in the repository root to configure API keys:

```bash
OPENAI_API_KEY=your_key
GEMINI_API_KEY=your_key
ANTHROPIC_API_KEY=your_key
BRAVE_API_KEY=your_key
PERPLEXITY_API_KEY=your_key
```

Environment values take precedence over empty `sloppy.json` keys but are overridden when a config key is explicitly set. See [Model Providers](/guides/models) for provider-specific setup.
