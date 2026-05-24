---
layout: doc
title: Multi-session TUI
---

# Multi-session TUI

The Sloppy TUI can keep several project sessions close at hand: the main chat, forked child sessions, subagent sessions, and background worktree sessions. The goal is to let you start or monitor parallel agent work without leaving the terminal.

Multi-session state is TUI-local. It tracks the sessions you have opened or created from the TUI for the current project, while the actual agent sessions, messages, events, and files remain persisted in the shared Sloppy workspace.

## Session List

Open the session list with:

```text
/sessions
```

When the composer is empty, you can also press `Left Arrow`. The list opens as a side pane beside the current chat. Press `Left Arrow` again to expand it to a full-width list.

The list is grouped by live state:

| Section | Meaning |
| --- | --- |
| `Waiting inputs` | The session has an unanswered structured input request, such as a plan question |
| `Working` | The TUI is posting to the session, or the latest run status is thinking, searching, or responding |
| `Completed` | No unanswered input request or active run is visible |

Within each section, pinned sessions appear first, then sessions are sorted by most recent update.

## Session List Keys

| Key | Action |
| --- | --- |
| `Left Arrow` | Open the side list from an empty composer; expand side list to full list |
| `Up` / `Down` | Move through session rows |
| `Enter` | Open the selected session, or create a new session from the text typed below the list |
| `Right Arrow` | Open the selected session |
| `Space` | Open the selected session for a reply and clear the composer draft |
| `Ctrl+X` | Hide the selected session from the TUI list |
| `?` | Show the quick reference |
| `Esc` | Close the session list |

Typing while the list is open goes into the normal composer. Press `Enter` with text in the composer to create a fresh session and immediately send that text as the first message.

`Ctrl+X` only removes the row from the TUI's tracked-session list. It does not delete the persisted agent session from Sloppy.

## Tracking and Persistence

The TUI stores tracked sessions in:

```text
<workspace-root>/tui/state.json
```

Tracked sessions are scoped by project. A session is added to the list when you:

- start the TUI on an existing session
- send the first message in a draft session
- switch to a session from the TUI
- create a background worktree session with `/bg`

The list is not a full database browser for every session ever created by the API or Dashboard. If a valid session is missing from the TUI list, resume it directly:

```bash
sloppy -s <sessionId>
```

After it opens successfully for the current project, the TUI tracks it for later.

## Pinning Sessions

Pin the current session with:

```text
/pin
```

Pinned sessions stay above unpinned sessions inside their state group. Run `/pin` again to unpin the current session. Pin state is saved in `tui/state.json`.

## New Sessions and Forks

Use `/new` to leave the current chat and return to a draft session:

```text
/new
```

The draft is not persisted until you send its first message. If you use `/new` from an existing session, the TUI keeps a checkpoint reference so the next persisted session can start from the previous chat's checkpointed context.

Use `/fork` when the new thread should explicitly branch from the current session:

```text
/fork investigate the flaky dashboard test
```

`/fork` creates a child session with `parentSessionId` set to the current session. If you include a task after `/fork`, the TUI switches into the child and sends that task immediately.

## Subagent Sessions

When an agent spawns subagent work, the parent timeline shows a subagent row. You can enter child sessions without losing the parent:

| Command or key | Action |
| --- | --- |
| `Ctrl+G` | Enter the newest subagent session |
| `Ctrl+Right` | Enter the newest subagent session |
| `/subagents` | Pick from child subagent sessions spawned by the current session |
| `Ctrl+P` | Return from a child session to its parent |
| `/parent` | Return from a child session to its parent |

The status line shows `parent: ctrl+p` when the current session has a parent. Subagent rows include their own live status, so you can see whether a child is starting, working, waiting, done, failed, or interrupted before entering it.

## Background Worktree Sessions

Use `/bg` for local background work that should run in a separate source-control worktree:

```text
/bg upgrade the dashboard route tests
```

The TUI creates a new session, asks the project's source-control provider for a managed worktree, attaches that worktree path as the session directory, and sends the task there in the background. The background row appears in the session list with a `bg` marker and usually shows the worktree path as its detail.

Background worktree sessions are available only against the local Sloppy instance in v1. Remote TUI connections reject `/bg`.

## Interrupting Work

Use `/stop` to interrupt the active run tree for the current session:

```text
/stop
```

This targets the current session and its run tree, not every tracked session in the list. Switch to another running session if you want to interrupt that one.

## Resume Shortcuts

Use `/status` in any persisted session to get the exact command for returning to it:

```text
/status
```

The status card includes:

```bash
sloppy -s <sessionId>
```

Draft sessions do not have a resume command until the first message creates the persisted session.
