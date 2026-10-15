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
| Windows 10 1809+ / Windows 11 | Supported | Swift for Windows, Visual Studio C++ tools and Windows SDK; Windows Terminal recommended |

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

### Windows (PowerShell)

From the checkout root (or an extracted source ZIP), install everything with one command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
# Open a new terminal:
sloppy run
```

The installer installs missing Git, Node.js LTS (24+), Visual Studio 2022 C++ Build Tools,
Windows SDK, and Swift 6.3.1 through WinGet. If WinGet is missing, it bootstraps Microsoft's
`Microsoft.WinGet.Client` module. It enables Windows Developer Mode for SwiftPM symbolic links.
Windows may request administrator permission for system components; if an installer requires
a restart, restart Windows and rerun the same command. Existing suitable tools are reused.
See the [Swift prerequisites](https://www.swift.org/install/windows/winget/) and
[Microsoft's WinGet bootstrap](https://learn.microsoft.com/windows/package-manager/winget/).
SQLite uses Windows SDK headers and the system `winsqlite3.dll`; a separate SQLite installation is unnecessary.

Sloppy, SloppyNode, Swift runtime DLLs, resource bundles, and Dashboard are installed under
`%LOCALAPPDATA%\Sloppy`. The installer adds its `bin` directory to the user PATH and sets
`CORE_DASHBOARD_PATH` to the installed Dashboard. It preserves your Sloppy workspace and configuration.
Open a new terminal to use the updated PATH.

`scripts/dev.ps1 setup` performs the same installation. Useful options:

```powershell
.\scripts\install.ps1 -DryRun                # show the installation plan
.\scripts\install.ps1 -InstallRoot D:\Sloppy # choose the installation directory
.\scripts\install.ps1 -SkipPrerequisites     # require tools to be already installed
.\scripts\install.ps1 -SkipBuild             # install existing build outputs
.\scripts\install.ps1 -NoPath                # leave the user environment unchanged
.\scripts\dev.ps1 start                     # background server
.\scripts\dev.ps1 status
.\scripts\dev.ps1 restart
.\scripts\dev.ps1 logs                      # follow the server log; Ctrl+C stops following
.\scripts\dev.ps1 stop
.\scripts\dev.ps1 autostart                 # opt in to starting at Windows login
.\scripts\dev.ps1 autostart-off
```

Use the same `-InstallRoot` (or `SLOPPY_INSTALL_ROOT`) for all commands with a custom installation.
`start`, `restart`, and `autostart` accept `-ConfigPath` for a specific server configuration.
Autostart references this checkout, so keep it at the same location. Setup itself does not start
the server or enable autostart. Rerun setup to update the installed build; a server started by
the script is stopped before replacement and restarted afterward.

For a build without installation, use `.\scripts\build-windows.ps1`, then
`.\.build\release\sloppy.exe run`. `-Configuration debug` and `-Jobs 4` control builds.

The server API listens on `http://127.0.0.1:25101` and the dashboard on
`http://127.0.0.1:25102`. Launch the interactive TUI in Windows Terminal with
`sloppy` (no subcommand), or use `sloppy tui`.
Use `run --no-gui` for the API alone. Keep `Dashboard/dist` in the checkout, or
set `CORE_DASHBOARD_PATH` to the Dashboard directory when running a relocated executable.

Run `./scripts/test-windows.ps1 -SkipBuild` to check the release server, dashboard assets,
and a real TUI session with Unicode input, resize and exit. For debug builds, add `-Configuration debug`.
Run `./scripts/test-windows-install.ps1` to test installation into a temporary directory,
runtime DLLs, resources, repeat installation, server management, and stale PID protection.
It uses existing build outputs and leaves the user PATH and autostart settings unchanged.
The Windows CI also runs the runtime/protocol suites and focused Windows, CLI parsing,
local owner authentication, and model transport regression tests.

The dashboard terminal uses ConPTY and the Windows command shell. macOS power controls,
launchd/systemd service management, CodexBar local cost estimates, secure remote console relay connections and optional OTLP exporters
are unavailable on Windows. Token counts and the runtime API remain available.

### macOS and Linux

From the repository root:

```bash
swift package resolve
```

## Source installer

If you want a one-command setup from a checkout, use:

```bash
bash scripts/install.sh
```

Remote bootstrap:

```bash
curl -fsSL https://sloppy.team/install.sh | bash
```

Installer modes:

```bash
bash scripts/install.sh --server-only
bash scripts/install.sh --bundle --no-prompt
curl -fsSL https://sloppy.team/install.sh | bash -s -- --server-only
```

The installer builds `sloppy`, optionally builds the Dashboard, and links the CLI into `~/.local/bin`. Install the standalone `sloppy-node` executor separately when you need a process boundary for local computer control.

## Build the Swift targets

Development build:

```bash
swift build
```

Release builds:

```bash
swift build -c release --product sloppy
swift build -c release --product SloppyNode
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
- serves the built dashboard on `http://localhost:25102` by default

Useful variants:

```bash
swift package --allow-writing-to-package-directory --allow-network-connections all sloppy-run --no-gui
swift package --allow-writing-to-package-directory --allow-network-connections all sloppy-run --config-path sloppy.json
swift package --allow-writing-to-package-directory --allow-network-connections all sloppy-run --no-gui --oneshot
```

`--no-dashboard` remains available as a compatibility alias for `--no-gui`.

The plugin requires SwiftPM permission flags because it writes the Dashboard bundle into the package directory and may run `npm install` when `Dashboard/node_modules` is missing or unusable.
Direct forwarding without `--` is intentionally supported only for common `sloppy` flags: `--oneshot`, `--run-demo-request`, and `--config-path`.
Use `--` for any other `sloppy` arguments.

## Run the Swift targets manually

Start the sloppy runtime directly:

```bash
swift run sloppy
```

With no subcommand, `swift run sloppy` opens the interactive terminal UI. To make the intent explicit, use:

```bash
swift run sloppy -- tui
```

Useful runtime variants:

```bash
swift run sloppy -- run
swift run sloppy -- run --oneshot
swift run sloppy -- run --run-demo-request
swift run sloppy -- run --config-path sloppy.json
swift run sloppy -- tui --config-path sloppy.json
swift run sloppy -- models
```

Run the node daemon when needed:

```bash
swift run SloppyNode
```

The user-facing installed command is `sloppy-node`; the SwiftPM product remains `SloppyNode`.

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

## Run the dashboard manually

From `Dashboard/`:

```bash
npm install
npm run dev
```

`sloppy run` already serves the production dashboard bundle on port `25102`. Use the Vite dev server only when iterating on frontend code.

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

## Terminal UI

For local project work, the fastest loop is often the TUI:

```bash
sloppy
```

It resolves the current directory as a Sloppy project, restores the last agent/session for that project, and lets you chat, switch models, configure providers, attach files with `@path`, inspect diffs, and resume sessions from the terminal.

See [Terminal UI](/tui/overview) for the full walkthrough.

## CI-parity checks

These are the commands the repository expects contributors to keep green:

```bash
swift test --parallel
swift build -c release --product sloppy
swift build -c release --product SloppyNode
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
| `SLOPPY_CA_CERTS` | Additional PEM Certificate Authority bundle for outbound HTTPS |
| `BRAVE_API_KEY` | Brave web search tool |
| `PERPLEXITY_API_KEY` | Perplexity web search tool |

Environment values take precedence over empty `sloppy.json` keys but are overridden when a config key is explicitly set.
