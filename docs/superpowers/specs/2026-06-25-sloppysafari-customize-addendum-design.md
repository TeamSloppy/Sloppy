# SloppySafari Customize Addendum Design

Date: 2026-06-25
Project: SloppySafari
Scope: Second iteration of the start page customization flow for Safari extension `chat.html`

## Goal

Extend the approved customize redesign with:

- Comet-style drag-and-drop reordering inside the grid,
- a bottom-sheet widget picker,
- `shortcut-widget` as a first-class grid item,
- bookmark-backed shortcut insertion when access is available,
- URL drag-and-drop that creates validated shortcut widgets.

This addendum builds on:

- `docs/superpowers/specs/2026-06-25-sloppysafari-customize-design.md`

## Why This Addendum Exists

The first customize redesign established:

- a navigation-style customize shell,
- `General` and `Widgets` separation,
- span-based grid metadata,
- draft-based widget editor.

This follow-up design defines the richer interaction model requested after the first iteration:

- direct drag reordering "like Comet",
- removal of the flat shortcut form,
- bottom-sheet insertion model for new widgets,
- treating shortcuts as widgets rather than as a separate editor list.

## Chosen Interaction Model

### Reorder Model

We will replace button-based reorder with drag-and-drop in `Widgets` edit mode.

The target interaction is:

- items enter edit mode,
- the user drags an item across the grid,
- the grid shows insertion / placement preview,
- releasing commits the new order and placement.

This should feel close to Comet-style card editing rather than a form-based dashboard editor.

### Add Model

New items are inserted from a bottom sheet rather than from inline controls inside the `Widgets` screen.

The bottom sheet contains:

- ready-made widgets,
- a dashed placeholder card with `+` for creating a custom widget,
- a `Shortcut` widget card.

### Shortcut Model

Shortcuts become a first-class widget type.

They are no longer managed as a long flat list of title/URL rows below the grid.

Instead:

- a shortcut appears as a grid item,
- it can be moved, resized, removed, and edited like any other item,
- shortcut creation flows through the same add/edit system.

## Information Architecture Changes

### Widgets Screen

The `Widgets` screen still owns:

- the editable grid,
- edit mode,
- save/done actions.

It no longer owns:

- a long inline shortcut field list,
- inline widget generation controls.

Instead, it gains:

- drag-and-drop grid editing,
- a button that opens the bottom sheet,
- contextual item menus.

### Bottom Sheet

The bottom sheet is the single insertion surface for new items.

Sections:

1. ready-made widgets
2. `Shortcut` widget
3. dashed placeholder card `Create widget`

The bottom sheet should feel like a widget tray rather than a generic modal.

### Editors

After insertion:

- ready-made widgets can be added directly or optionally edited,
- `Shortcut` opens shortcut editor,
- `Create widget` opens widget editor.

## Widget Picker Bottom Sheet

### Content

The bottom sheet shows a grid/list of available insertable cards:

- `Shortcut`
- existing saved widgets / templates / generated widget artifacts that are insertable
- a dashed placeholder card with `+` and clear label for custom widget creation

### Placeholder Card

The dashed placeholder card is a clear CTA:

- rounded dashed border,
- `+` icon,
- title like `Create widget`,
- secondary hint copy.

Pressing it pushes the existing `Widget Editor` screen.

### Ready Widget Cards

Each ready-made widget card shows:

- name,
- visual preview or skeleton preview,
- optional type hint.

Pressing it inserts that widget into the grid and may open its editor if the widget type requires configuration.

## Shortcut Widget

### Shortcut As Widget

`Shortcut` is a widget kind, not a special side-form.

It supports:

- title,
- URL,
- favicon,
- layout span metadata,
- reorder / resize / delete,
- edit after insertion.

### Shortcut Creation Flow

When the user selects the `Shortcut` widget card from the bottom sheet:

1. create draft shortcut widget
2. push shortcut editor
3. edit title and URL
4. save back to grid

### Shortcut Editing

Shortcut editor is lighter than widget editor:

- title field,
- URL field,
- optional favicon preview,
- bookmark chooser if available,
- `Done` / `Cancel`.

## Bookmarks Integration

### Visibility Rule

Bookmarks should be shown only if access is actually available.

If bookmark access is unavailable:

- hide the bookmarks section entirely,
- do not show a dead placeholder,
- do not show an access CTA in this iteration.

### Bookmark Picker

If access is available, shortcut editor can show:

- bookmark list or bookmark picker,
- selecting a bookmark pre-fills title and URL.

This is assistive, not the primary creation path.

## URL Drag-and-Drop

### Behavior

Dragging a URL onto the editable grid should create a shortcut widget.

### Validation

Before creating the shortcut:

- validate that the drop payload resolves to a URL,
- reject non-link payloads.

Accepted:

- standard `http://`
- standard `https://`

Rejected:

- plain text without valid URL parsing,
- unsupported schemes unless explicitly allowed later.

### Placement Preview

When dragging over the grid:

- show a drop-preview between items / within grid placement,
- do not require dropping only on empty cells,
- preview where the shortcut widget will land.

On drop:

1. create shortcut draft
2. insert at previewed location
3. open shortcut editor

This gives both precise placement and immediate editability.

## Contextual Menus

### Item Menu

In edit mode, each item can expose a compact `...` trigger.

Menu entries:

- `Settings`
- `Remove`

For widgets, `Settings` opens widget editor.

For shortcuts, `Settings` opens shortcut editor.

`Remove` deletes the item from the grid.

### Relationship To Drag

The contextual menu must not conflict with drag behavior.

That means:

- drag is attached to the card body / explicit drag affordance,
- menu trigger remains tap-first and stable.

## Grid Interaction Rules

### Edit Mode

Drag-and-drop is enabled only in edit mode.

Outside edit mode:

- items behave normally,
- menus / drag affordances are hidden or muted,
- no accidental reorder should occur.

### Placement Engine

The existing span-grid model still applies.

We continue to use:

- `id`
- `order`
- `colSpan`
- `rowSpan`

Absolute pixel coordinates remain out of scope.

Drag updates logical order / placement intent, and the layout engine reflows deterministically.

### Resize

Resize remains span-based.

It may live:

- in item settings,
- in item toolbar controls,
- or both.

This addendum does not require pixel-resize handles.

## Data Model Additions

The current model should expand to support a shortcut widget explicitly.

Suggested logical kinds:

- `shortcut`
- `widget`

Shortcut items should behave like widgets in placement logic but still store:

- `title`
- `url`

Additional optional metadata:

- `faviconURL`
- `source` such as `manual`, `bookmark`, `drop`

## Error Handling

### Invalid Drag Payload

If dropped text is not a valid URL:

- reject creation,
- show lightweight inline feedback,
- do not insert a broken shortcut item.

### Bookmark Access Unavailable

No blocking UI is shown. The bookmarks section is simply omitted.

### Bottom Sheet Empty State

If there are no saved widgets to show:

- keep `Shortcut` card,
- keep dashed `Create widget` card,
- show empty-state copy for the ready-made widgets section if needed.

## UI Direction

This iteration should feel more like a polished widget curation surface than a form.

Core visual cues:

- dark OLED surfaces,
- soft rounded cards,
- thin borders,
- subtle floating bottom sheet,
- dashed placeholder CTA,
- stable compact context menus,
- strong drag preview clarity.

The interaction tone should feel tactile, lightweight, and deliberate.

## Testing Strategy

Add resource-level coverage for:

- bottom-sheet markup and CTA card,
- shortcut widget editor presence,
- removal of the old shortcut form list,
- bookmark section visibility gating,
- URL drop validation hooks,
- drag / reorder affordance presence,
- contextual menu entries `Settings` and `Remove`.

Behavior tests should cover:

- inserting shortcut widget,
- dropping valid URL,
- rejecting invalid URL,
- bookmark-driven prefill when bookmark data exists,
- deleting grid items,
- preserving deterministic order after reorder.

## Non-Goals

This addendum does not include:

- cross-device sync semantics,
- automatic bookmark permission prompting UX,
- freeform pixel positioning,
- arbitrary nested widget folders or groups.

## Resolved Decisions

The following product decisions were explicitly chosen:

- use the previously recommended `Edit mode + drag + menu + bottom sheet` approach,
- bottom sheet shows ready widgets plus dashed `Create widget` card,
- remove the old flat shortcut list,
- shortcut is a widget type,
- show bookmarks only when access is already available,
- URL drag-and-drop creates shortcut widgets,
- drag uses insertion preview instead of forcing only empty-cell drops.

## Implementation Areas

Likely files impacted:

- `Apps/SloppySafari/Extension/Resources/contentScript.js`
- `Apps/SloppySafari/Extension/Resources/panel.css`
- `Apps/SloppySafari/Extension/Resources/i18n.js`
- `Apps/SloppySafari/Tests/SloppySafariCoreTests/CustomizeFlowResourceTests.swift`
- related Safari extension JS tests if we add finer interaction coverage later
