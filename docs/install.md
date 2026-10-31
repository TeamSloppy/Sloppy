---
layout: doc
title: Install
---

# Install

Start with one command, or download the native app.

## Quick install

### macOS and Linux

Paste into Terminal:

```bash
curl -fsSL https://sloppy.team/install.sh | bash
```

This downloads the latest prebuilt CLI and web Dashboard, verifies SHA-256, and installs
into `~/.local`. No Swift, Node.js, Git, or Homebrew is needed. Prebuilt CLI packages are
available for **macOS Apple silicon** and **Linux x86_64**; other architectures require
[a source build](#build-from-source). On Linux, use a glibc distribution compatible with
the Ubuntu release build; Alpine/musl requires a source build.

The installer adds the command directory to your zsh or bash profile when it is missing
from PATH. Open a new terminal, then run:

```bash
sloppy       # terminal UI
sloppy run   # server + web Dashboard at http://localhost:25102
```

Rerun the same install command to update. For a specific version, or to leave your shell profile unchanged:

```bash
curl -fsSL https://sloppy.team/install.sh | bash -s -- --release-tag v2.5.0
curl -fsSL https://sloppy.team/install.sh | bash -s -- --no-path
```

### Windows

Paste into PowerShell:

```powershell
irm https://sloppy.team/install.ps1 | iex
```

This installs the prebuilt **Windows x64** CLI, web Dashboard, and runtime DLLs under
`%LOCALAPPDATA%\Sloppy`. It verifies SHA-256 before replacing files. You do not need
Swift, Git, Node.js, Visual Studio Build Tools, or the Windows SDK. Runtime libraries
ship beside the executable; no machine-wide runtime installation or administrator
permission is required.

Open a new terminal and run `sloppy` or `sloppy run`. Rerun the same command to update.
Close a running Sloppy process before replacing its files. Workspace data and
configuration outside the managed `bin`, `dashboard`, and `share` directories are preserved.

::: info Windows release availability

The release must include `Sloppy-windows-x86_64.zip` and its checksum in `SHA256SUMS.txt`.
Older releases, including v2.5.0, only contain SloppyNode for Windows. Version v2.5.1 introduces the full package. If the full archive
is absent, the installer stops and leaves your installation unchanged. It does not
fall back to installing build tools. The release workflow now builds and packages the
full Windows distribution; v2.5.1 and later provide the full Windows install path.

:::

To inspect the plan, choose a directory, or explicitly build from source:

```powershell
Invoke-WebRequest https://sloppy.team/install.ps1 -OutFile install.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -InstallRoot D:\Sloppy
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -FromSource
```

`-FromSource` is for developers. It installs missing build prerequisites and keeps a
source checkout under `%LOCALAPPDATA%\Sloppy\source`. Windows may request administrator
permission or a restart for that explicit source build.

See [Windows setup](/guides/build-from-terminal#windows-powershell) for details.

## Native apps

- [Download for macOS](https://github.com/TeamSloppy/Sloppy/releases/download/v2.5.1/Sloppy-macos-universal-2.5.0.dmg) — macOS 26+, Apple silicon and Intel. Open the signed and notarized disk image, drag Sloppy into Applications, then launch it.
- [iOS App Store](https://apps.apple.com/app/id6811777701) — the assigned product page; available after App Store publication.

## Other installation methods

Homebrew, source builds, and Docker remain available below.

## Homebrew

[Install Homebrew](https://brew.sh) if you do not already have it. The Sloppy tap files live in this repository ([`Casks/sloppy.rb`](https://github.com/TeamSloppy/Sloppy/blob/main/Casks/sloppy.rb) and [`Formula/sloppy.rb`](https://github.com/TeamSloppy/Sloppy/blob/main/Formula/sloppy.rb)); add the tap once, then install the cask or formula below.

### macOS (Cask)

```bash
brew tap teamsloppy/sloppy https://github.com/TeamSloppy/Sloppy
brew install --cask teamsloppy/sloppy/sloppy
```

This installs the `sloppy` binary and copies the Dashboard bundle to `~/.local/share/sloppy/dashboard`, matching the layout used by the source installer. Install `sloppy-node` separately when you need a standalone local computer-control executor.

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

## Build from source

### Windows from a checkout

From a checkout or an extracted source ZIP, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

This installs missing Git, Node.js LTS, Swift 6.3.1, C++ Build Tools, and Windows SDK;
builds Sloppy and Dashboard; installs binaries, runtime DLLs, resources, and Dashboard
under `%LOCALAPPDATA%\Sloppy`; and adds `sloppy` to your user PATH.
Windows may request administrator permission for system components.

Open a new terminal, then run `sloppy` for the TUI or `sloppy run` for the server and Dashboard.
Use `scripts/dev.ps1 start`, `stop`, `restart`, `status`, and `logs` for a background server.
See [Windows setup](/guides/build-from-terminal#windows-powershell) for options and troubleshooting.

### macOS/Linux prerequisites

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
bash scripts/install.sh --bundle
```

Or build from GitHub without cloning first:

```bash
curl -fsSL https://sloppy.team/install.sh | bash -s -- --bundle
```

The installer will:

- build `sloppy` in release mode
- build the Dashboard bundle by default
- install the `sloppy` symlink into `~/.local/bin`

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
curl -fsSL https://sloppy.team/install.sh | bash -s -- --bundle --dir ~/.local/share/sloppy/source
```

For source installs, `sloppy update` checks the upstream branch and `sloppy update --install`
pulls and reinstalls from the current branch of that checkout:

```bash
sloppy update
sloppy update --install
sloppy update --install --server-only
sloppy update --install --dir ~/.local/share/sloppy/source
```

Verify the installation and check connectivity:

```bash
sloppy --version
```

### Standalone SloppyNode

`sloppy` can use computer-control tools in-process. For a separate node executable, install `sloppy-node`:

```bash
bash scripts/install-sloppy-node.sh
```

On Windows:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install-sloppy-node.ps1
```

For permissions, protocol details, and client helper notes, see [SloppyNode](/guides/sloppy-node).

Then open the terminal UI for local project chat:

```bash
sloppy
```

Or start the server and Dashboard:

```bash
sloppy run
sloppy status
```

For source installs, add `~/.local/bin` to your shell profile if needed.

## Run as a background service

Once `sloppy` is in your `PATH`, you can install it as a persistent background service that starts automatically on login and restarts if it crashes.

```bash
sloppy service install
```

On Linux, `sloppy` also checks `systemd` lingering during install so the user service can keep running after logout. If enabling lingering needs `sudo`, the install output prints the exact `loginctl enable-linger` command to run once.

The server is now running in the background and will start again on every login.

To verify:

```bash
sloppy service status
sloppy status
```

To follow the live log:

```bash
sloppy service logs
```

To stop or remove the service:

```bash
sloppy service stop        # stop now, keep registered
sloppy service uninstall   # stop + remove entirely
```

::: tip Custom config path

If your `sloppy.json` is not in the default location (`~/.sloppy/sloppy.json`), pass it at install time:

```bash
sloppy service install --config-path /path/to/sloppy.json
```

The path is embedded in the service definition so every restart picks it up automatically.

:::

::: details Platform notes

**macOS** — registers a LaunchAgent at `~/Library/LaunchAgents/com.sloppy.server.plist`. The OS uses `KeepAlive` to restart the process if it exits. Logs go to `~/.sloppy/logs/service.log`.

**Linux** — creates a systemd user unit at `~/.config/systemd/user/sloppy.service` and enables it with `systemctl --user`. Install also checks `loginctl` lingering so the service can survive logout; if auto-enabling lingering is not permitted, `sloppy` prints the one-time `sudo loginctl enable-linger <user>` command. Logs are available via `journalctl --user -u sloppy.service`.

**Windows** — registers `Sloppy.Server.<user SID>` in Task Scheduler for the current user,
starts it immediately, and starts it again at login. The task runs without elevation or
a password in the user's interactive session, following [Windows task security](https://learn.microsoft.com/en-us/windows/win32/taskschd/security-contexts-for-running-tasks).
The runner restarts a failed server after five seconds, allows continuous execution on battery power, and
stops at logout. The runner and saved executable/config paths live in
`%USERPROFILE%\.sloppy\service`; stdout and stderr logs are in its `logs` subdirectory.
The installed service does not depend on the repository's `scripts/dev.ps1`.
`stop` keeps the login task registered; `uninstall` removes it and preserves logs.

:::

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

For details see [Build From Terminal](/guides/build-from-terminal), [Terminal UI](/tui/overview), and the [CLI Reference](/guides/cli).

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

To install the server as a public relay for multiple Sloppy computers, see [Relay Deployment and Multi-Instance Access](/guides/relay).

## Environment variables

Create a `.env` in the repository root to configure API keys:

```bash
OPENAI_API_KEY=your_key
GEMINI_API_KEY=your_key
ANTHROPIC_API_KEY=your_key
SLOPPY_CA_CERTS=/path/to/extra-ca.pem
BRAVE_API_KEY=your_key
PERPLEXITY_API_KEY=your_key
```

Environment values take precedence over empty `sloppy.json` keys but are overridden when a config key is explicitly set. See [Model Providers](/guides/models) for provider-specific setup.
