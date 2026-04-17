---
layout: doc
title: Install
---

# Install

Three ways to get Sloppy running: with Homebrew, from the source installer, or with Docker Compose.

## Homebrew

[Install Homebrew](https://brew.sh) if you do not already have it. The Sloppy tap files live in this repository ([`Casks/sloppy.rb`](https://github.com/TeamSloppy/Sloppy/blob/main/Casks/sloppy.rb) and [`Formula/sloppy.rb`](https://github.com/TeamSloppy/Sloppy/blob/main/Formula/sloppy.rb)); add the tap once, then install the cask or formula below.

### macOS (Cask)

```bash
brew tap teamsloppy/sloppy https://github.com/TeamSloppy/Sloppy
brew install --cask teamsloppy/sloppy/sloppy
```

This installs the `sloppy` and `SloppyNode` binaries and copies the Dashboard bundle to `~/.local/share/sloppy/dashboard`, matching the layout used by the source installer.

::: tip macOS architecture

Each release updates the cask to a single macOS tarball from [GitHub Releases](https://github.com/TeamSloppy/Sloppy/releases). If that build does not match your Mac, use the [source installer](#source-installer) or download the matching `Sloppy-macos-*.tar.gz` asset manually.

:::

### Linux (Formula)

The Homebrew formula ships a **Linux x86_64** tarball.

```bash
brew tap teamsloppy/sloppy https://github.com/TeamSloppy/Sloppy
brew install teamsloppy/sloppy/sloppy
```

### Verify, upgrade, and uninstall

```bash
sloppy --version
```

```bash
brew upgrade --cask teamsloppy/sloppy/sloppy   # macOS
brew upgrade teamsloppy/sloppy/sloppy           # Linux
```

```bash
brew uninstall --cask teamsloppy/sloppy/sloppy   # macOS
brew uninstall teamsloppy/sloppy/sloppy         # Linux
```

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
bash scripts/install.sh --release
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

### Uninstall

To remove installed binaries and dashboard assets:

```bash
bash scripts/uninstall.sh
```

To also remove the source checkout used for source installs:

```bash
bash scripts/uninstall.sh --remove-source-checkout
```

Preview removals without deleting anything:

```bash
bash scripts/uninstall.sh --dry-run
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
