# SloppyClient

Native macOS/iOS client for Sloppy. Built on AdaEngine + AdaUI.

Current status: internal-first Apple client workspace with connection setup, local server discovery, deep-link connection, chat, websocket-backed notifications, and settings/config editing foundations.

## Build

```bash
cd Apps/Client
swift build
```

For interface development the package automatically uses the sibling `AdaEngine`
checkout (for example `D:\Development\AdaEngine` next to `D:\Development\Sloppy`).
Changes to that checkout are compiled directly into the client. If no sibling
checkout exists, it uses `Vendor/AdaEngine`.

To choose another checkout, set `ADAENGINE_PATH` to its absolute path before
running SwiftPM or launching Xcode. Set `ADAENGINE_LOCAL=0` to explicitly use the
vendored engine. The same package resolution applies to the XcodeGen project.

```powershell
$env:ADAENGINE_PATH = "D:\Development\AdaEngine"
swift build --product SloppyClient
swift test --filter WorkspaceNavigationTests
```

On Windows, SwiftPM's test build currently also compiles JavaScriptKit 0.59.0's
`PackageToJS` command plugin, which fails on its missing `stderr` import. This is
a dependency-level test-build limitation; it also affects `swift build --build-tests`.
Run the full client tests on macOS until that upstream plugin supports Windows.
On Windows, `./scripts/test-workspace-core.ps1` runs the workspace networking,
navigation, preference, and screen-state tests in an isolated SwiftPM package
using exact copies of the production sources. It does not cover AdaUI rendering.

## Generate Xcode project

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
cd Apps/Client
xcodegen generate
open SloppyClient.xcodeproj
```

## Workspace Notes

`Apps/Client` is the canonical Apple client workspace. It is built independently from the root server package and has its own package boundaries plus generated Xcode project flow.

## Structure

```
Apps/Client/
  Package.swift          # Standalone SwiftPM package (SloppyClient)
  project.yml            # XcodeGen spec for .xcodeproj generation
  Sources/
    SloppyClient/        # App entry point and product screens
```

## Current Feature Status

Implemented now:

- splash and connection setup flow
- saved server retry and local network discovery
- manual host/port connection
- `sloppy://connect` deep-link handling
- chat UI with session streaming
- notification socket integration and in-app banners
- settings and server config editing surfaces
- Client Native-style dark workspace with global chat/project search, agents, Priority, and chats grouped by project
- independent chat tabs with preserved drafts and streaming state
- project context and starter prompts on the new chat screen
- neutral dark theme matching the supplied Native references and the existing paper light theme
- Attention inbox with read, snooze, and dismiss actions
- pull request list, role filters, comments, and diff detail
- scheduled task list, search, active/paused filters, creation, and pause/resume
- project Kanban, chat list, canvas catalog/creation, and automation catalog/creation
- environment and source-control inspector, working-tree diff, and project file browser
- Kanban task details with Markdown, comments, editable title/description/status/priority/agent/tags, activity, logs, task diff, and clarification answers
- composer completion for `/` commands, `@` files/skills/session references, and `#` tasks, including caret-aware replacement and arrow/Tab/Enter/Escape handling
- project file search, with bounded directory traversal for older servers
- animated ASCII greeting and soft colored hover shadows
- selectable message text and clipboard shortcuts in local AdaUI; Markdown preserves list markers, nested lists, task lists, tables, quotes, and link destinations
- searchable settings sidebar with 21 working configuration sections, Native configuration models, validated JSON collection editing, and preservation of newer server fields during saves
- failed message sends report the error and restore the draft

The supplied Native screenshots guide the desktop shell and the listed surfaces.
The canvas editor, automation run management, embedded web browser, terminal,
voice input, and worker/token telemetry are still separate migration work. The
inspector shows actual API data and reports unavailable source control explicitly.
`ClientNative` remains the reference for these remaining features.

The local engine supplies `Text.textSelection`, text-field completion key/caret hooks,
Markdown structure and link attributes. These engine changes live in the sibling
AdaEngine checkout; they must be included when pinning a future Vendor revision.
Native account management, approvals, managed backend/update controls, remote/mesh
setup, and voice settings still need their dedicated platform integrations. Nested
configuration collections currently use a validated JSON editor rather than all of
Native's specialized editors.

Focused Windows verification after building the client:

```powershell
./scripts/test-workspace-core.ps1
python scripts/test-engine-ui.py
```

The second command links the real local engine's already-built debug objects with
its Markdown/selection suites and the client composer tests. This bypasses the
unrelated JavaScriptKit WASI command plugin that currently blocks `swift test` on
Windows; it does not replace engine code with stubs.

## Visual preview

A loopback-only sample backend exercises the screens without a running Core:

```powershell
python scripts/preview-workspace.py
```

In a second terminal, run the debug executable with isolated preview preferences:

```powershell
$env:SLOPPY_CLIENT_PREVIEW_URL = "http://127.0.0.1:25102"
swift run SloppyClient
```

The preview server keeps mutations in memory and never writes project files.
The environment override is accepted only in DEBUG builds and only for loopback
hosts. Normal launches keep the saved connection and preferences.

## Canvas, automations, browser, and terminal

Workspaces now open an AdaUI canvas editor. Add sticky notes, text, shapes, and
frames; drag elements, edit their text and bounds, zoom, save, and delete.
Transactions include document and element revisions. Conflicts reload the server
document and retain an error instead of silently overwriting another edit.
“Ask agent” opens a chat bound to the canvas; refresh the canvas after agent edits.
Image/widget rendering, connection drawing, Pencil input, and undo are still pending.

Project automations support manual execution and run history with status, summary,
timestamps, and task IDs. Refresh loads server-side progress. Creation supports
manual, schedule, webhook, GitHub PR/review triggers, task modes, and permissions.

Tools → Browser runs an isolated local Chromium page through the
[DevTools protocol](https://chromedevtools.github.io/devtools-protocol/).
AdaUI displays live page frames and forwards mouse, scroll, and keyboard events.
Back/forward/reload are supported. Browsers belong to individual chat tabs; existing
chat sessions can connect the same Native browser-tool bridge. This requires an
installed Edge/Chrome/Chromium executable (Settings → Browser). Mobile platforms,
downloads/uploads, browser extensions, and native permission dialogs are not implemented.

Tools → Terminal provides a local interactive shell using ConPTY on Windows and
PTY on macOS/Linux, with SwiftTerm rendering, ANSI colors, selection, paste,
scrollback, resize, restart, and stop. Start it explicitly in the chosen directory.
Ctrl+C interrupts; Ctrl+Shift+C/V copies/pastes on Windows. Remote/mesh shells and
multiple terminal tabs remain pending. The process host and AdaUI terminal renderer
are adapted from the local AdaEngine Editor implementation.

SwiftTerm is pinned to the same revision as AdaEngine Editor. To reuse a local checkout:

```powershell
$env:SLOPPY_SWIFTTERM_PATH = "D:/Development/AdaEngine/.build-tools/swiftterm-caa1bdd3f139"
swift build --product SloppyClient --jobs 4
```

Settings now include profile editing, tool approval decisions, channel access,
agent proactivity, session history, connection links, and mesh/voice status.
Managed Remote, backend installation/updates, migration, account recovery/tokens,
and full voice controls still need platform-specific work.

Integration checks against the loopback preview backend:

```powershell
$env:SLOPPY_BROWSER_INTEGRATION = "1"
./scripts/test-workspace-core.ps1
$env:SLOPPY_WORKSPACE_INTEGRATION = "1"
$env:SLOPPY_TERMINAL_INTEGRATION = "1"
python scripts/test-engine-ui.py
```

Still on the roadmap:

- APNs device registration and push delivery
- release/distribution hardening

## Notes

- AdaEngine is vendored as a git submodule at `Vendor/AdaEngine` (see ADR 0002).
- Requires macOS 15.0+ (driven by AdaEngine's minimum platform requirement).
- Push notification entitlements are already stubbed in `project.yml` per ADR 0005.
- More implementation status is tracked in [Apps/docs/current-state.md](../docs/current-state.md).

## Updating the pinned engine revision

The submodule is pinned to a specific commit. To update it:

```bash
cd Vendor/AdaEngine
git fetch origin
git checkout <target-commit-or-tag>
cd ../..
git add Vendor/AdaEngine
git commit -m "chore: bump AdaEngine to <commit>"
```

To initialize the submodule after a fresh clone:

```bash
git submodule update --init --recursive
```

Ownership rules for changes: see [ADR 0002](../docs/adr/0002-adaengine-fork-and-submodule.md).
