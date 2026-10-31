# Sidebar and project navigation

On macOS, the project sections appear in the project navigation block at the
right of the workspace. The tooltip shows each section's keyboard shortcut:

- Command–1: Kanban
- Command–2: Workspaces
- Command–3: Automation
- Command–4: Chats
- Command–5: Workflows

The shortcuts are registered once in the Workspace menu and use the selected
project in the active window. They are disabled outside a project view. The
Workspaces back button remains available when an individual workspace is open.
On iPhone and iPad, project sections use native tabs.

Workflows shows the definitions created by agents for the selected project.
Choose a workflow and a run to see its task, status, graph and recorded steps.
Select a graph node to inspect its configuration and transitions; select a
recorded step to inspect its input, output and error. Branches and joins remain
visible even when a generated workflow has no saved node positions. The Steps
view also shows pending human input and repeated executions of a node.

The view refreshes every five seconds while visible and the app is active.
Refresh errors retain the last successful snapshot and offer a retry. Selecting
Definition only hides execution data. Run selection survives refresh and is
kept separately for each project and server during the current app session.
The project section itself is persisted across launches. If a run used an older
definition version, the graph is labelled as current and does not overlay that
run's statuses; Steps still shows its recorded execution. This view is read-only.

The sidebar list fades over its top 22 points after scrolling. Its bottom control
area always has an opaque app background, including when the chat's shared
composer gradient is present, so scrolling content cannot show through it.

Project cards display total tasks and tasks **in progress**. The latter counts
only the canonical `in_progress` status, excluding `ready` and `needs_review`.
Missing task data is shown as a dash rather than zero. Counts use the available
project snapshot and update when that data changes.

## Checks

`ProjectInProgressCountTests` covers status counting, transitions and missing data.
`SidebarChromeRenderingTests` checks scrolling and footer pixels in a native
window, dispatches Command–1 through Command–4, verifies disabled shortcuts, and
captures the right-hand navigation before and after native hover dispatch.

To retain screenshots, set `SLOPPY_SIDEBAR_SCREENSHOTS` to an existing directory
when running these tests. These six focused checks and the macOS Xcode build
passed on 2026-09-15.

The complete client suite ran 488 tests with the same 107 pre-existing issues as
before this change; there were no additional failures.
