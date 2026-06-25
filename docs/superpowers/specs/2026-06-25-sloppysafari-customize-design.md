# SloppySafari Customize Flow Design

Date: 2026-06-25
Project: SloppySafari
Scope: Start page customization redesign for Safari extension `chat.html`

## Goal

Replace the current flat customize dialog with a navigation-style customization flow that:

- separates `General` and `Widgets` concerns,
- supports a flexible grid with reorder / resize / delete,
- introduces a widget editor with live preview and iterative prompt refinement,
- keeps widget creation explicit, draft-based, and reversible.

## Problem

The current start page customization flow is too limited:

- shortcuts and widgets are managed in one flat form,
- widgets only support coarse fixed sizes,
- there is no real grid editing model,
- there is no reorder flow,
- there is no dedicated widget editing experience,
- widget deletion and iterative regeneration are awkward,
- the current UI does not scale to a larger collection of widgets and shortcuts.

## Chosen Approach

We will implement an iOS-inspired edit mode with a discrete but flexible span-based grid.

Instead of free pixel positioning, each start page item will occupy grid spans such as:

- `1x1`
- `2x1`
- `2x2`
- `3x2`

This preserves a "freeform" feeling while keeping layout deterministic, responsive, and stable.

The customize flow will use an internal navigation model:

1. `Customize Home`
2. `General`
3. `Widgets`
4. `Widget Editor`

The `Widget Editor` behaves like a pushed screen inside customize, similar to `NavigationStack` / `NavigationView`.

## Information Architecture

### Customize Home

Entry point launched from the existing `Customize` button.

Contains two top-level sections:

- `General`
- `Widgets`

This screen is a lightweight hub, not the place for direct editing.

### General

Contains only start page appearance settings:

- theme
- background image

No widget management controls live here.

### Widgets

Displays the editable start page grid.

Capabilities:

- add shortcut
- add widget
- edit widget
- delete widget
- delete shortcut
- reorder all grid items
- resize grid items by span
- preview final layout in-place

Contains an `Edit` mode toggle. In normal mode the grid is passive. In edit mode items expose editing affordances.

### Widget Editor

Opened from:

- the `+` action in `Widgets`,
- tapping an existing widget's edit action.

Contains:

- a live widget preview,
- a mini chat for iterative prompts,
- draft-only editing,
- `Done` and `Cancel` actions.

## Widget Editor Behavior

### Creation

When the user taps `+` in `Widgets`, we push `Widget Editor`.

The editor starts with an empty draft.

The user writes prompts in the mini chat. The agent performs actions and returns widget updates. Each successful response updates the current draft preview dynamically.

No widget is added to the start page until the user taps `Done`.

### Editing Existing Widget

When opening an existing widget, the editor works on a draft copy of the widget.

- `Done` replaces the old widget with the updated draft.
- `Cancel` discards the draft and keeps the original widget unchanged.

### Confirmation Model

- `Done` commits the current draft and returns to `Widgets`.
- `Cancel` closes without applying draft changes.

This keeps widget creation explicit and predictable.

## Grid Model

### Item Types

The grid will support two kinds of start page items:

- `shortcut`
- `widget`

Both participate in the same ordering and placement system.

### Layout Metadata

Each item will carry layout metadata:

- `id`
- `kind`
- `order`
- `colSpan`
- `rowSpan`

Item-specific payload remains unchanged in spirit:

- shortcuts use `title` and `url`
- widgets use `artifactId`, `title`, and associated widget HTML / artifact data

### Placement Strategy

Layout remains deterministic:

1. sort items by `order`
2. place them left-to-right, top-to-bottom
3. fit each item according to `colSpan` and `rowSpan`

We do not store freeform absolute coordinates.

This reduces layout bugs and keeps behavior stable across viewport widths.

## Editing Operations

In `Widgets` edit mode we support:

- `reorder`
- `resize`
- `delete`
- `edit widget`

### Reorder

Drag-and-drop updates logical order. The layout engine reflows the grid from item order plus spans.

### Resize

Resize changes `colSpan` and `rowSpan`.

We will expose supported sizes through discrete grid presets rather than pixel dragging.

### Delete

Delete removes the item from `startPageItems`.

For widgets this removes the widget from the start page layout. It does not necessarily delete the underlying artifact globally unless we explicitly add a separate artifact deletion action later.

### Edit Widget

Pushes `Widget Editor` with a draft copy.

## Migration Strategy

Current widget size values map into the new span model:

- `small` -> `1x1`
- `medium` -> `2x1`
- `large` -> `2x2`

Existing shortcuts receive a default span of `1x1`.

If old records do not have explicit `order`, preserve array order.

## UI Direction

The visual direction follows a dark OLED control-surface language:

- dark panel surfaces,
- thin borders,
- compact cards,
- navigation-style hierarchy,
- restrained glass / material feel,
- low-emission contrast with bright focus states,
- modular grid with deliberate spacing.

The `Widgets` screen should feel more like a control board than a form.

The `Widget Editor` should feel like an embedded creation workspace rather than a modal prompt box.

## Error Handling

### Widget Draft Errors

If widget generation or regeneration fails:

- preserve the last valid draft preview,
- show the error inline in the editor,
- keep the chat open for further refinement.

### Invalid Layout Changes

If a resize choice cannot be applied in the current viewport:

- the system should reflow gracefully,
- if necessary, clamp to the nearest supported layout.

### Cancel Safety

Unsaved draft edits are discarded on `Cancel`.

## Testing Strategy

### Resource-Level Tests

Add focused tests that assert:

- customize flow markup includes the new navigation structure,
- widget editor exists as a distinct screen,
- grid items carry span metadata,
- edit controls for delete / resize / reorder are present,
- `Done` / `Cancel` semantics are wired correctly.

### Behavior Tests

Where practical, cover:

- size migration from old widget sizes,
- order preservation,
- deleting items,
- draft vs committed widget behavior.

## Non-Goals

This design does not include:

- free pixel-based canvas positioning,
- automatic artifact deletion from the broader artifact store,
- multi-draft version history in the widget editor,
- simultaneous editing of multiple widgets in one editor session.

## Open Decisions Resolved

The following decisions were made during brainstorming:

- use an iOS-like `Customize/Edit` mode,
- use an internal pushed-screen flow inside customize,
- `Done` commits widget drafts, `Cancel` discards,
- use a flexible span grid rather than fixed small / medium / large only,
- keep widget generation draft-based and live-updating.

## Implementation Notes

Likely implementation areas:

- `Apps/SloppySafari/Extension/Resources/contentScript.js`
- `Apps/SloppySafari/Extension/Resources/panel.css`
- related i18n strings in `Apps/SloppySafari/Extension/Resources/i18n.js`
- resource-level regression tests in `Apps/SloppySafari/Tests/SloppySafariCoreTests/`

The work should be implemented incrementally:

1. navigation-style customize shell
2. widget editor draft flow
3. span-grid metadata and rendering
4. edit mode controls
5. migration and tests
