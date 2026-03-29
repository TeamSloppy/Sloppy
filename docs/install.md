---
layout: doc
title: Install
---

# Install

Two ways to get Sloppy running: from the source installer or with Docker Compose.

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

### Source installer

From a local checkout:

```bash
git clone https://github.com/TeamSloppy/Sloppy.git
cd Sloppy
bash scripts/install.sh
```

Or bootstrap from GitHub without cloning first:

```bash
curl -fsSL https://sloppy.team/install.sh | bash
```

The installer will:

- build `sloppy` and `SloppyNode` in release mode
- build the Dashboard bundle by default
- install `sloppy` and `SloppyNode` symlinks into `~/.local/bin`

Useful modes:

```bash
bash scripts/install.sh --server-only
bash scripts/install.sh --bundle --no-prompt
bash scripts/install.sh --dry-run
curl -fsSL https://sloppy.team/install.sh | bash -s -- --server-only
```

If you want the script to clone or update Sloppy for you instead of running from a checkout:

```bash
bash scripts/install.sh --dir ~/.local/share/sloppy/source
curl -fsSL https://sloppy.team/install.sh | bash -s -- --dir ~/.local/share/sloppy/source
```

Verify the installation and check connectivity:

```bash
sloppy --version
```

Then start the server:

```bash
sloppy run
sloppy status
```

If `sloppy` is not in `PATH`, add `~/.local/bin` to your shell profile.

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
