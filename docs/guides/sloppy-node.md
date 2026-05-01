---
layout: doc
title: SloppyNode
---

# SloppyNode

`SloppyNode` is Sloppy's local computer-control executor. The reusable Swift library lives in `Packages/SloppyComputerControl`; Sloppy can call that library in-process, while the standalone `sloppy-node` command wraps the same implementation behind a small JSON protocol.

Use standalone `sloppy-node` when another app, helper, or external process needs local computer control. The macOS client can bundle a helper on macOS; iOS, iPadOS, and visionOS remain remote clients.

## Install standalone node

### macOS

```bash
bash scripts/install-sloppy-node.sh
```

Or with Homebrew:

```bash
brew tap teamsloppy/sloppy https://github.com/TeamSloppy/Sloppy
brew install --cask teamsloppy/sloppy/sloppy-node
```

### Windows

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install-sloppy-node.ps1
```

Add the printed install directory to `PATH` if `sloppy-node` is not found in a new terminal.

## Verify

```bash
printf '{"action":"status","payload":{}}' | sloppy-node invoke --stdin
```

On Windows PowerShell:

```powershell
'{"action":"status","payload":{}}' | sloppy-node invoke --stdin
```

## JSON protocol

The v1 process API is intentionally small:

```bash
sloppy-node invoke --stdin
```

It reads a `NodeActionRequest` JSON object from stdin and writes a `NodeActionResponse` JSON object to stdout. Supported actions:

- `status`
- `exec`
- `computer.click`
- `computer.typeText`
- `computer.key`
- `computer.screenshot`

## Sloppy integration

The `sloppy` server uses `SloppyComputerControl` in-process by default for its `computer.*` tools. Set `SLOPPY_NODE_PATH` to force those tools through a standalone node process instead:

```bash
SLOPPY_NODE_PATH=/path/to/sloppy-node sloppy run
```

This keeps local Sloppy fast while preserving the process boundary for helpers, clients, and remote-control deployments.

## Permissions

macOS requires explicit permissions before a process can control input or capture the display:

- Accessibility: click and key events.
- Input Monitoring: keyboard event delivery on some systems.
- Screen Recording: screenshots.

Grant permissions to the built `sloppy-node` binary, the app-bundled helper, or the terminal app that launches it, then restart the launcher before retrying.

Windows support uses the active desktop session. Clicks, keyboard input, and screenshots only work reliably when `sloppy-node` runs in an interactive user session.

Linux currently builds the shared package but returns `unsupported_platform` for computer-control actions.
