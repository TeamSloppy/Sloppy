---
layout: doc
title: Terminal UI
---

# Terminal UI

Sloppy ships with a full-screen terminal UI for local agent work. It uses the same runtime, workspace, project resolution, providers, agents, sessions, MCP servers, and persistence as the rest of Sloppy, but keeps the main chat loop inside your terminal.

Use it when you want the fastest local path: open a project directory, start Sloppy, ask questions, attach files, switch models, inspect changes, keep several sessions in view, and resume the same session later without opening the Dashboard.

## Start the TUI

From a project directory:

```bash
sloppy
```

The explicit command is:

```bash
sloppy tui
```

Useful variants:

```bash
sloppy tui --config-path /path/to/sloppy.json
sloppy -s <sessionId>
sloppy tui -s <sessionId>
sloppy models
```

`sloppy` with no subcommand opens the TUI. `sloppy tui` does the same thing explicitly. `sloppy -s` and `sloppy tui -s` resume an existing agent session for the current directory. `sloppy models` opens the same terminal picker directly in model-selection mode and exits after a model is chosen.

The TUI bootstraps Sloppy in-process, so you do not need a separate `sloppy run` server for a local terminal chat. It still uses the same `sloppy.json` and workspace files.

## Startup Behavior

On startup the TUI:

- resolves or creates a Sloppy project for the current working directory
- restores the last selected agent and session for that project when they are still available
- creates a default `sloppy` agent when no user agents exist
- opens a draft chat when there is no saved session selection; the session is persisted when you send the first message
- applies the saved TUI theme from `tui/state.json`
- stores TUI-only state under the workspace root at `tui/state.json`

The opening screen shows the active mode, model, project, agent, and provider. The bottom composer is where you type messages or slash commands.

## Core Keys

| Key | Action |
| --- | --- |
| `Enter` | Send the current message or apply the selected picker item |
| `Tab` | Cycle chat mode when typing normally; complete or apply a picker item when a command, model, session, agent, provider, theme, task, or file picker is open |
| `Esc` | Close the active picker or command palette |
| `Up` / `Down` | Move through active picker suggestions |
| `PageUp` / `PageDown` | Scroll chat history by pages |
| `Option+Up` / `Ctrl+Up` | Scroll history upward by a few lines |
| `Option+Down` / `Ctrl+Down` | Scroll history downward by a few lines |
| `Option+Home` / `Ctrl+Home` | Jump to the start of history |
| `Option+End` / `Ctrl+End` | Jump back to the bottom |
| `Ctrl+C` | Exit the TUI |

Chat modes cycle as `Ask -> Build -> Plan -> Debug -> Ask`. The selected mode is sent with the next user message.

## Models and Providers

Switch models with the picker:

```text
/model
```

Or set a model directly:

```text
/model openai-api:gpt-5.4-mini
/model anthropic:claude-sonnet-4-6
```

Configure providers from inside the TUI:

```text
/provider
/provider openai-api <api-key> [model]
/provider openrouter <api-key> [model]
/provider gemini <api-key> [model]
/provider anthropic <api-key> [model]
/provider ollama
/openai-device
/anthropic-oauth
```

`/provider` opens a provider picker. API-key providers save a model entry into `sloppy.json`. `ollama` uses the local Ollama server. `/openai-device` starts Codex device auth. `/anthropic-oauth` starts the Anthropic browser OAuth flow and expects the callback URL to be pasted back with `/anthropic-callback <url>`.

## Sessions, Agents, and Context

The TUI now has a dedicated multi-session workflow. Open the side session list with `/sessions` or press `Left Arrow` from an empty composer. It groups tracked sessions as `Waiting inputs`, `Working`, and `Completed`, supports pinned sessions, and lets you create a new session by typing a task below the list and pressing `Enter`.

See [Multi-session TUI](/tui/multi-session) for the full workflow, including list keys, `/bg` worktree sessions, `/fork`, and subagent navigation.

| Command | Purpose |
| --- | --- |
| `/agents` | Switch agent |
| `/sessions` | Open the tracked-session side list for the current project |
| `/subagents` | Open a child subagent session |
| `/parent` | Return to the parent session |
| `/new` | Return to a draft session; the next message creates the persisted session |
| `/bg <task>` | Create a background worktree session |
| `/pin` | Pin or unpin the current session |
| `/fork <task>` | Create a child session and optionally send the task immediately |
| `/status` | Show project, agent, session id, resume command, model, provider, and pet state |
| `/compact` | Request a memory checkpoint for the current session |
| `/stop` | Interrupt the current run tree |
| `/restore`, `/up` | Nudge a live session or restore it after a failed run |

Use `/status` when you need the exact resume command:

```text
/status
```

The card includes a shortcut such as:

```bash
sloppy -s <sessionId>
```

## Attach Files and Project Paths

Use `@path` inside a message to inline project files as explicit context:

```text
Please review @Sources/sloppy/TUI/SloppyTUIScreen.swift
```

The TUI indexes project files and offers `@path` completions. Paths with spaces are escaped automatically. Up to eight `@path` references from a single message are expanded into the prompt context.

You can also attach files by pasting file paths into the composer. On macOS, `Ctrl+V` can attach file or image data from the clipboard. Individual pasted attachments are limited to 25 MiB.

For source-control context:

```text
/diff
/context changes
/context diff
```

`/diff` shows changes recorded in the current TUI session. `/context changes` attaches the latest watched change list to the next message. `/context diff` attaches the source-control diff to the next message.

## Themes

Open the theme picker with:

```text
/themes
```

`/theme` is accepted as an alias. The picker lists the built-in `Default` theme and any readable custom JSON themes found under:

```text
<workspace-root>/tui/themes
```

With the default workspace configuration, this is:

```text
~/.sloppy/tui/themes
```

Selecting a theme applies it immediately, saves the selected `themeID` in `tui/state.json`, and reapplies the TUI/editor palettes. The selection is restored the next time the TUI starts.

Custom theme files use JSON. The file name becomes the stable theme id with a `custom:` prefix, so `forest.json` becomes `custom:forest` and cannot collide with the built-in `default` theme.

```json
{
  "name": "Forest",
  "colors": {
    "accent": "#34d399",
    "accentBright": "#6ee7b7",
    "foreground": "#e5e7eb",
    "muted": "#94a3b8",
    "panelBackground": "#111827",
    "userMessageBackground": "#1f2937",
    "toolBackground": "#0f172a"
  }
}
```

`name` is optional; the file name is used as the display name when `name` is missing. `colors` may be partial. Missing color roles inherit from `Default`.

Supported color roles:

| Role | Purpose |
| --- | --- |
| `accent`, `accentBright` | Main chrome, headings, picker highlights, composer border |
| `foreground`, `muted` | Primary and secondary text |
| `blue`, `green`, `yellow`, `orange`, `red` | Semantic colors used by links, statuses, diffs, progress, and warnings |
| `panelBackground` | Composer metadata, pickers, session lists, and panels |
| `userMessageBackground` | User and queued-message blocks |
| `toolBackground` | Tool calls, tool results, workspace diffs, and subagent rows |
| `thinkingBackground` | Thinking/draft blocks |
| `attachmentBackground` | Attachment rows |
| `textBackground`, `truncatedBackground` | TauTUI text and truncation backgrounds |

Colors must be `#RRGGBB`. Invalid JSON files or invalid colors are skipped; the TUI reports skipped files when `/themes` opens.

The older `/bar <color>` command still works as a transient accent-only override. It does not change the saved theme selection.

## Slash Commands

| Command | Purpose |
| --- | --- |
| `/help` | Show TUI commands and scroll keys |
| `/keybindings`, `/shortcuts` | Show the quick reference |
| `/status` | Show current project, agent, session, model, provider, and resume command |
| `/workspace` | Show workspace roots and directory access |
| `/pet` | Toggle the terminal Sloppie pet and show its face/status |
| `/agents` | Switch agent |
| `/sessions` | Open the tracked-session side list |
| `/subagents` | Open a child subagent session |
| `/parent` | Return to the parent session |
| `/new` | Return to a draft session for the next message |
| `/bg <task>` | Create a background worktree session |
| `/pin` | Pin or unpin the current session |
| `/clear` | Clear local TUI cards |
| `/stop` | Interrupt the current run |
| `/restore`, `/up` | Restart the current session after a failed or interrupted run |
| `/undo` | Undo file changes from the last completed TUI turn |
| `/redo` | Redo the last undone TUI turn |
| `/btw <message>` | Ask a side question without changing the current main message flow |
| `/compact` | Request session compaction |
| `/add_dir <path>` | Add a working directory to the current session |
| `/fork <task>` | Branch the current conversation |
| `/themes`, `/theme` | Open the TUI theme picker |
| `/bar <color>` | Change the accent color for the current TUI run |
| `/copy` | Copy the last assistant response to the clipboard on macOS |
| `/diff` | Show changes recorded in the current TUI session |
| `/effort low\|medium\|high\|default` | Set reasoning effort for future messages |
| `/skills` | Show enabled agent skills and their slash aliases |
| `/editor` | Open the configured code editor |
| `/model [model]` | Open the model picker or switch directly |
| `/scrollback` | Configure timeline scrollback rendering |
| `/context changes\|diff` | Queue workspace changes or source-control diff for the next message |
| `/tasks` | Show project tasks |
| `/mcps` | Show MCP server statuses |
| `/provider [id key model]` | Configure or switch providers |
| `/remote` | Switch to a linked Sloppy instance |
| `/local` | Switch back to the local Sloppy instance |
| `/openai-device` | Start OpenAI Codex device auth |
| `/anthropic-oauth` | Start Anthropic OAuth |
| `/anthropic-callback <url>` | Complete Anthropic OAuth |
| `/quit` or `/exit` | Exit the TUI |

Skill-provided slash commands also appear in the command palette and are forwarded to the agent when invoked.

`/restore` and `/up` send a recovery message into the active session transcript. Use them after a transient failure, such as a lost network request, when you want the agent to continue the previous unfinished task without creating a new session.

Undo and redo history is scoped to the active session during the current TUI run. Switching sessions restores that session's own undo stack without mixing changes from other chats.

## State and Persistence

The TUI uses the configured Sloppy workspace, so sessions, messages, agents, tasks, memories, logs, MCP configuration, and provider configuration remain shared with the Dashboard and CLI.

TUI-only state is small and local:

- last selected agent and session per project
- unsent composer drafts per project, agent, and session
- added session directories
- tracked and pinned sessions
- terminal pet visibility
- welcome tip cursor
- scrollback mode and line limit
- selected `themeID`

This state is stored at:

```text
<workspace-root>/tui/state.json
```

Custom themes are stored at:

```text
<workspace-root>/tui/themes/*.json
```

The default workspace root is controlled by `workspace.basePath` and `workspace.name` in `sloppy.json`. With default settings, the workspace root is `~/.sloppy`.
