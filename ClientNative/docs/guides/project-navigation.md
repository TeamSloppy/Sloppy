# Sidebar and project navigation

On macOS, the project sections are arranged vertically at the right edge of the
workspace. Hovering a section enlarges its button with a short spring animation;
Reduce Motion disables that animation and hover scaling. The tooltip shows the
section name and its keyboard shortcut:

- Command–1: Kanban
- Command–2: Workspaces
- Command–3: Automation
- Command–4: Chats

The shortcuts are registered once in the Workspace menu and use the selected
project in the active window. They are disabled outside a project view. The
Workspaces back button remains available when an individual workspace is open.
Mobile layouts retain the compact horizontal picker.

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
