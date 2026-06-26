# SloppySafari Customize Addendum Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the first SloppySafari customize iteration with Comet-style drag reorder, a bottom-sheet widget picker, and a first-class shortcut widget that supports bookmarks and URL drag-and-drop.

**Architecture:** Build on the existing customize shell and span-grid model already present in `contentScript.js`. Introduce a bottom-sheet picker and drag/edit interaction layer without replacing the deterministic span-based layout engine; reorder updates logical grid order, shortcut widgets share the same item model as other widgets, and bookmark / URL-drop entry points feed into the same shortcut editor flow.

**Tech Stack:** Safari extension resources (`contentScript.js`, `panel.css`, `i18n.js`), Safari extension background bridge (`background.js`) if bookmark access wiring is needed, Swift Testing resource-level tests in `Apps/SloppySafari/Tests/SloppySafariCoreTests/`, plus existing JS-side Safari extension tests if expanded later.

## Global Constraints

- Project type: SwiftPM agent runtime (Swift 6.2) + React/Vite dashboard + Apple client.
- Keep API behavior backward-compatible unless task explicitly allows breaking change.
- Do not introduce language heuristics for agent behavior; rely on explicit state and structured data.
- Preserve existing JS formatting style in Safari extension resources.
- Update/add tests when changing behavior.
- Run the smallest relevant verification first.
- Scope of this plan is only the approved addendum in `docs/superpowers/specs/2026-06-25-sloppysafari-customize-addendum-design.md`.

---

## File Structure

- Modify: `Apps/SloppySafari/Extension/Resources/contentScript.js`
  - Owns the widget picker bottom sheet, drag/reorder interaction state, shortcut-widget item model, bookmark/URL drop flows, and editor routing.
- Modify: `Apps/SloppySafari/Extension/Resources/panel.css`
  - Owns bottom-sheet layout, dashed placeholder card, drag preview, and contextual item menu styling.
- Modify: `Apps/SloppySafari/Extension/Resources/i18n.js`
  - Owns addendum-specific copy for the sheet, shortcut widget, bookmarks, drag/drop feedback, and item menus.
- Modify: `Apps/SloppySafari/Extension/Resources/background.js`
  - Only if needed to expose bookmark listing through the existing extension message bridge.
- Modify: `Apps/SloppySafari/Tests/SloppySafariCoreTests/CustomizeFlowResourceTests.swift`
  - Extend with resource-level assertions for the bottom sheet, shortcut widget, contextual menus, and drag/drop hooks.
- Modify: `Apps/SloppySafari/Extension/Tests/contentSelection.test.mjs`
  - If needed, add lightweight runtime-message tests for bookmark and picker bridge behavior.

## Task 1: Replace Inline Insertion With Bottom-Sheet Widget Picker

**Files:**
- Modify: `Apps/SloppySafari/Extension/Resources/contentScript.js`
- Modify: `Apps/SloppySafari/Extension/Resources/panel.css`
- Modify: `Apps/SloppySafari/Extension/Resources/i18n.js`
- Test: `Apps/SloppySafari/Tests/SloppySafariCoreTests/CustomizeFlowResourceTests.swift`

**Interfaces:**
- Consumes: existing `renderCustomizeWidgetsScreen(frame)`, `openWidgetEditor(frame, sourceItemId = null)`, `state.artifacts`.
- Produces:
  - `state.widgetPickerSheet = { open: boolean }`
  - `renderWidgetPickerSheet(frame)`
  - `openWidgetPickerSheet(frame)`
  - `closeWidgetPickerSheet(frame)`

- [ ] **Step 1: Write the failing resource test for the bottom-sheet picker**

```swift
@Test("widgets screen renders a bottom sheet picker with ready widgets and create placeholder")
func widgetsScreenRendersBottomSheetPicker() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let contentScriptURL = packageRoot.appendingPathComponent("Extension/Resources/contentScript.js")
    let panelCSSURL = packageRoot.appendingPathComponent("Extension/Resources/panel.css")
    let i18nURL = packageRoot.appendingPathComponent("Extension/Resources/i18n.js")

    let contentScript = try String(contentsOf: contentScriptURL, encoding: .utf8)
    let panelCSS = try String(contentsOf: panelCSSURL, encoding: .utf8)
    let i18n = try String(contentsOf: i18nURL, encoding: .utf8)

    #expect(contentScript.contains("renderWidgetPickerSheet(frame)"))
    #expect(contentScript.contains("data-sloppy-widget-picker-sheet"))
    #expect(contentScript.contains("data-sloppy-create-widget-card"))
    #expect(panelCSS.contains(".sloppy-widget-picker-sheet"))
    #expect(panelCSS.contains(".sloppy-widget-create-card"))
    #expect(i18n.contains("createWidgetCard"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter widgetsScreenRendersBottomSheetPicker`

Expected: FAIL because the bottom-sheet picker does not exist yet.

- [ ] **Step 3: Add the bottom-sheet state and rendering shell**

```javascript
state.widgetPickerSheet = { open: false };

function openWidgetPickerSheet(frame) {
  state.widgetPickerSheet = { open: true };
  renderCustomizeDialog(frame);
}

function closeWidgetPickerSheet(frame) {
  state.widgetPickerSheet = { open: false };
  renderCustomizeDialog(frame);
}

function renderWidgetPickerSheet(frame) {
  if (!state.widgetPickerSheet?.open) {
    return "";
  }
  return `
    <section class="sloppy-widget-picker-sheet" data-sloppy-widget-picker-sheet>
      <header>
        <strong>${escapeHTML(t("widgetsSection"))}</strong>
        <button class="sloppy-settings-save" type="button" data-sloppy-widget-picker-done>${escapeHTML(t("finishEditing"))}</button>
      </header>
      <div class="sloppy-widget-picker-grid" data-sloppy-widget-picker-grid></div>
    </section>
  `;
}
```

- [ ] **Step 4: Replace inline generator block with sheet entry point**

```javascript
<button class="sloppy-settings-save" type="button" data-sloppy-open-widget-picker>${escapeHTML(t("createWidget"))}</button>
${renderWidgetPickerSheet(frame)}
```

```javascript
root.innerHTML = `
  <section class="sloppy-customize-screen" data-sloppy-customize-screen="widgets">
    ...
    <button class="sloppy-settings-save" type="button" data-sloppy-open-widget-picker>${escapeHTML(t("createWidget"))}</button>
    ${renderWidgetPickerSheet(frame)}
  </section>
`;
```

- [ ] **Step 5: Render ready widgets plus dashed placeholder card**

```javascript
function renderWidgetPickerSheet(frame) {
  if (!state.widgetPickerSheet?.open) {
    return "";
  }
  const widgets = (state.artifacts || []).filter((artifact) => String(artifact?.kind || "").trim() === "widget");
  return `
    <section class="sloppy-widget-picker-sheet" data-sloppy-widget-picker-sheet>
      <div class="sloppy-widget-picker-grid">
        <button class="sloppy-widget-create-card" type="button" data-sloppy-create-widget-card>
          <span>+</span>
          <strong>${escapeHTML(t("createWidgetCard"))}</strong>
        </button>
        ${widgets.map((artifact) => `
          <button class="sloppy-widget-picker-card" type="button" data-sloppy-pick-ready-widget="${escapeHTML(artifact.id || "")}">
            <strong>${escapeHTML(artifact.title || artifact.id || "Widget")}</strong>
          </button>
        `).join("")}
      </div>
    </section>
  `;
}
```

```css
.sloppy-widget-picker-sheet {
  position: sticky;
  bottom: 0;
}

.sloppy-widget-create-card {
  border: 1px dashed rgba(255, 255, 255, 0.24);
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `swift test --filter widgetsScreenRendersBottomSheetPicker`

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Apps/SloppySafari/Extension/Resources/contentScript.js Apps/SloppySafari/Extension/Resources/panel.css Apps/SloppySafari/Extension/Resources/i18n.js Apps/SloppySafari/Tests/SloppySafariCoreTests/CustomizeFlowResourceTests.swift
git commit -m "feat: add widget picker bottom sheet"
```

## Task 2: Replace Shortcut Form Rows With First-Class Shortcut Widgets

**Files:**
- Modify: `Apps/SloppySafari/Extension/Resources/contentScript.js`
- Modify: `Apps/SloppySafari/Extension/Resources/panel.css`
- Modify: `Apps/SloppySafari/Extension/Resources/i18n.js`
- Test: `Apps/SloppySafari/Tests/SloppySafariCoreTests/CustomizeFlowResourceTests.swift`

**Interfaces:**
- Consumes: `normalizedStartPageItems(settings)`, `renderWidgetsGrid(frame, items)`, `openWidgetPickerSheet(frame)`.
- Produces:
  - `openShortcutEditor(frame, sourceItemId = null, seed = null)`
  - `commitShortcutDraft(frame)`
  - shortcut items with `kind: "shortcut"` that behave like widgets

- [ ] **Step 1: Write the failing resource test for shortcut widgets**

```swift
@Test("shortcut is treated as a widget card and the old shortcut form list is removed")
func shortcutIsTreatedAsWidgetCard() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let contentScriptURL = packageRoot.appendingPathComponent("Extension/Resources/contentScript.js")
    let i18nURL = packageRoot.appendingPathComponent("Extension/Resources/i18n.js")

    let contentScript = try String(contentsOf: contentScriptURL, encoding: .utf8)
    let i18n = try String(contentsOf: i18nURL, encoding: .utf8)

    #expect(contentScript.contains("openShortcutEditor(frame, sourceItemId = null, seed = null)"))
    #expect(contentScript.contains("data-sloppy-pick-shortcut-widget"))
    #expect(!contentScript.contains("data-sloppy-start-page-shortcuts"))
    #expect(i18n.contains("shortcutWidget"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter shortcutIsTreatedAsWidgetCard`

Expected: FAIL because the sheet does not include the shortcut widget and the widgets screen still renders shortcut rows.

- [ ] **Step 3: Add `Shortcut` card to the picker sheet**

```javascript
<button class="sloppy-widget-picker-card" type="button" data-sloppy-pick-shortcut-widget>
  <strong>${escapeHTML(t("shortcutWidget"))}</strong>
  <span>${escapeHTML(t("shortcutWidgetHint"))}</span>
</button>
```

- [ ] **Step 4: Remove the old inline shortcut form list from the widgets screen**

```javascript
// Remove:
<div class="sloppy-start-shortcut-editor" data-sloppy-start-page-shortcuts></div>
<button class="sloppy-settings-save" type="button" data-sloppy-start-page-add-shortcut>...</button>

// Keep grid-only editing surface.
```

- [ ] **Step 5: Implement shortcut editor shell**

```javascript
function openShortcutEditor(frame, sourceItemId = null, seed = null) {
  const sourceItem = normalizedStartPageItems(state.settings).find((item) => item.id === sourceItemId) || null;
  state.customizeNavigation = {
    ...state.customizeNavigation,
    screen: "shortcut-editor",
    widgetDraftSourceId: sourceItemId,
    widgetDraft: sourceItem || {
      id: `shortcut-${Date.now()}`,
      kind: "shortcut",
      title: seed?.title || "",
      url: seed?.url || "",
      colSpan: 1,
      rowSpan: 1
    }
  };
  renderCustomizeDialog(frame);
}

function commitShortcutDraft(frame) {
  const draft = state.customizeNavigation?.widgetDraft;
  if (!draft?.url) {
    navigateCustomize(frame, "widgets");
    return;
  }
  updateStartPageItems((items) => {
    const nextItem = {
      id: draft.id,
      kind: "shortcut",
      title: draft.title || draft.url,
      url: draft.url,
      colSpan: draft.colSpan || 1,
      rowSpan: draft.rowSpan || 1
    };
    if (state.customizeNavigation?.widgetDraftSourceId) {
      return items.map((item) => item.id === state.customizeNavigation.widgetDraftSourceId ? nextItem : item);
    }
    return [...items, { ...nextItem, order: items.length }];
  });
  navigateCustomize(frame, "widgets");
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `swift test --filter shortcutIsTreatedAsWidgetCard`

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Apps/SloppySafari/Extension/Resources/contentScript.js Apps/SloppySafari/Extension/Resources/panel.css Apps/SloppySafari/Extension/Resources/i18n.js Apps/SloppySafari/Tests/SloppySafariCoreTests/CustomizeFlowResourceTests.swift
git commit -m "feat: make shortcut a first-class widget"
```

## Task 3: Add Comet-Style Edit Mode Menus And Drag-Reorder Hooks

**Files:**
- Modify: `Apps/SloppySafari/Extension/Resources/contentScript.js`
- Modify: `Apps/SloppySafari/Extension/Resources/panel.css`
- Modify: `Apps/SloppySafari/Tests/SloppySafariCoreTests/CustomizeFlowResourceTests.swift`

**Interfaces:**
- Consumes: `renderWidgetsGrid(frame, items)`, `updateStartPageItems(mutator)`, `state.customizeNavigation.editing`.
- Produces:
  - `state.gridDrag = { activeId: string | null, overId: string | null, dropPosition: "before" | "after" | null }`
  - drag hooks `data-sloppy-grid-draggable`, `data-sloppy-grid-drop-target`
  - contextual menu trigger `data-sloppy-grid-menu`

- [ ] **Step 1: Write the failing resource test for drag/menu affordances**

```swift
@Test("widgets edit mode exposes drag affordances and contextual menus")
func widgetsEditModeExposesDragAffordances() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let contentScriptURL = packageRoot.appendingPathComponent("Extension/Resources/contentScript.js")
    let panelCSSURL = packageRoot.appendingPathComponent("Extension/Resources/panel.css")

    let contentScript = try String(contentsOf: contentScriptURL, encoding: .utf8)
    let panelCSS = try String(contentsOf: panelCSSURL, encoding: .utf8)

    #expect(contentScript.contains("state.gridDrag"))
    #expect(contentScript.contains("data-sloppy-grid-draggable"))
    #expect(contentScript.contains("data-sloppy-grid-drop-target"))
    #expect(contentScript.contains("data-sloppy-grid-menu"))
    #expect(panelCSS.contains(".sloppy-grid-drop-preview"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter widgetsEditModeExposesDragAffordances`

Expected: FAIL because current edit mode only has button-based move controls.

- [ ] **Step 3: Introduce drag state and item menu trigger**

```javascript
state.gridDrag = {
  activeId: null,
  overId: null,
  dropPosition: null
};

<button class="sloppy-grid-menu-trigger" type="button" data-sloppy-grid-menu="${escapeHTML(item.id)}">...</button>
```

- [ ] **Step 4: Render draggable wrappers and drop-preview hooks**

```javascript
<article
  class="sloppy-grid-item"
  data-sloppy-grid-item="${escapeHTML(item.id)}"
  data-sloppy-grid-draggable="${escapeHTML(item.id)}"
  data-sloppy-grid-drop-target="${escapeHTML(item.id)}"
  draggable="${isEditing ? "true" : "false"}"
>
```

```css
.sloppy-grid-drop-preview {
  outline: 2px solid rgba(183, 255, 0, 0.72);
}
```

- [ ] **Step 5: Add drag event wiring**

```javascript
root.querySelectorAll("[data-sloppy-grid-draggable]").forEach((node) => {
  node.addEventListener("dragstart", () => {
    state.gridDrag.activeId = node.dataset.sloppyGridDraggable;
  });
  node.addEventListener("dragend", () => {
    state.gridDrag = { activeId: null, overId: null, dropPosition: null };
    renderCustomizeDialog(frame);
  });
});

root.querySelectorAll("[data-sloppy-grid-drop-target]").forEach((node) => {
  node.addEventListener("dragover", (event) => {
    event.preventDefault();
    state.gridDrag.overId = node.dataset.sloppyGridDropTarget;
    state.gridDrag.dropPosition = "after";
  });
  node.addEventListener("drop", (event) => {
    event.preventDefault();
    moveStartPageItemRelative(state.gridDrag.activeId, node.dataset.sloppyGridDropTarget, state.gridDrag.dropPosition);
    renderCustomizeDialog(frame);
  });
});
```

- [ ] **Step 6: Run test to verify it passes**

Run: `swift test --filter widgetsEditModeExposesDragAffordances`

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Apps/SloppySafari/Extension/Resources/contentScript.js Apps/SloppySafari/Extension/Resources/panel.css Apps/SloppySafari/Tests/SloppySafariCoreTests/CustomizeFlowResourceTests.swift
git commit -m "feat: add drag reorder hooks for widgets grid"
```

## Task 4: Add URL Drag-And-Drop Shortcut Creation With Validation

**Files:**
- Modify: `Apps/SloppySafari/Extension/Resources/contentScript.js`
- Modify: `Apps/SloppySafari/Extension/Resources/i18n.js`
- Test: `Apps/SloppySafari/Tests/SloppySafariCoreTests/CustomizeFlowResourceTests.swift`

**Interfaces:**
- Consumes: `openShortcutEditor(frame, sourceItemId = null, seed = null)`, `state.gridDrag`.
- Produces:
  - `readDroppedURL(event)`
  - `isSupportedShortcutURL(value)`
  - URL-drop path that opens shortcut editor

- [ ] **Step 1: Write the failing resource test for URL drop**

```swift
@Test("dragging a valid URL to the grid opens shortcut widget creation")
func draggingValidURLOpensShortcutCreation() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let contentScriptURL = packageRoot.appendingPathComponent("Extension/Resources/contentScript.js")

    let contentScript = try String(contentsOf: contentScriptURL, encoding: .utf8)

    #expect(contentScript.contains("readDroppedURL(event)"))
    #expect(contentScript.contains("isSupportedShortcutURL(value)"))
    #expect(contentScript.contains("openShortcutEditor(frame, null,"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter draggingValidURLOpensShortcutCreation`

Expected: FAIL because URL-drop creation is not implemented yet.

- [ ] **Step 3: Implement URL parsing and validation helpers**

```javascript
function isSupportedShortcutURL(value) {
  try {
    const url = new URL(String(value || "").trim());
    return url.protocol === "http:" || url.protocol === "https:";
  } catch {
    return false;
  }
}

function readDroppedURL(event) {
  const text = event.dataTransfer?.getData("text/uri-list")
    || event.dataTransfer?.getData("text/plain")
    || "";
  return isSupportedShortcutURL(text) ? text.trim() : "";
}
```

- [ ] **Step 4: Wire drop-to-shortcut behavior**

```javascript
node.addEventListener("drop", (event) => {
  event.preventDefault();
  const droppedURL = readDroppedURL(event);
  if (droppedURL) {
    openShortcutEditor(frame, null, { title: droppedURL, url: droppedURL });
    return;
  }
  moveStartPageItemRelative(state.gridDrag.activeId, node.dataset.sloppyGridDropTarget, state.gridDrag.dropPosition);
  renderCustomizeDialog(frame);
});
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter draggingValidURLOpensShortcutCreation`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Apps/SloppySafari/Extension/Resources/contentScript.js Apps/SloppySafari/Extension/Resources/i18n.js Apps/SloppySafari/Tests/SloppySafariCoreTests/CustomizeFlowResourceTests.swift
git commit -m "feat: add URL drop to shortcut widget flow"
```

## Task 5: Add Bookmark-Backed Shortcut Selection When Access Exists

**Files:**
- Modify: `Apps/SloppySafari/Extension/Resources/background.js`
- Modify: `Apps/SloppySafari/Extension/Resources/contentScript.js`
- Modify: `Apps/SloppySafari/Extension/Resources/i18n.js`
- Test: `Apps/SloppySafari/Tests/SloppySafariCoreTests/CustomizeFlowResourceTests.swift`
- Test: `Apps/SloppySafari/Extension/Tests/contentSelection.test.mjs`

**Interfaces:**
- Consumes: `openShortcutEditor(frame, sourceItemId = null, seed = null)`.
- Produces:
  - background message `sloppy.bookmarks.list`
  - `loadBookmarksIfAvailable(frame)`
  - `state.availableBookmarks = []`

- [ ] **Step 1: Write the failing resource test for bookmark integration**

```swift
@Test("shortcut editor includes bookmark selection only when bookmark access is available")
func shortcutEditorSupportsBookmarksWhenAvailable() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let contentScriptURL = packageRoot.appendingPathComponent("Extension/Resources/contentScript.js")
    let backgroundURL = packageRoot.appendingPathComponent("Extension/Resources/background.js")

    let contentScript = try String(contentsOf: contentScriptURL, encoding: .utf8)
    let background = try String(contentsOf: backgroundURL, encoding: .utf8)

    #expect(contentScript.contains("loadBookmarksIfAvailable(frame)"))
    #expect(contentScript.contains("availableBookmarks"))
    #expect(background.contains("sloppy.bookmarks.list"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter shortcutEditorSupportsBookmarksWhenAvailable`

Expected: FAIL because bookmark bridge is not implemented yet.

- [ ] **Step 3: Expose bookmark list from the background bridge**

```javascript
if (message?.type === "sloppy.bookmarks.list") {
  try {
    const bookmarks = await browser.bookmarks.search({});
    return bookmarks
      .filter((item) => item?.url)
      .map((item) => ({ id: item.id, title: item.title || item.url, url: item.url }));
  } catch {
    return { error: "bookmarks_unavailable" };
  }
}
```

- [ ] **Step 4: Show bookmark section only when available**

```javascript
async function loadBookmarksIfAvailable(frame) {
  const response = await chrome.runtime.sendMessage({ type: "sloppy.bookmarks.list" }).catch(() => ({ error: "bookmarks_unavailable" }));
  state.availableBookmarks = Array.isArray(response) ? response : [];
  renderCustomizeDialog(frame);
}

// In shortcut editor render:
${state.availableBookmarks?.length ? `
  <section class="sloppy-shortcut-bookmarks">
    ${state.availableBookmarks.map((bookmark) => `
      <button type="button" data-sloppy-pick-bookmark="${escapeHTML(bookmark.id)}">${escapeHTML(bookmark.title)}</button>
    `).join("")}
  </section>
` : ""}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter shortcutEditorSupportsBookmarksWhenAvailable`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Apps/SloppySafari/Extension/Resources/background.js Apps/SloppySafari/Extension/Resources/contentScript.js Apps/SloppySafari/Extension/Resources/i18n.js Apps/SloppySafari/Tests/SloppySafariCoreTests/CustomizeFlowResourceTests.swift Apps/SloppySafari/Extension/Tests/contentSelection.test.mjs
git commit -m "feat: add bookmarks-backed shortcut picker"
```

## Self-Review

### Spec Coverage

- bottom-sheet picker: Task 1
- dashed create-widget card: Task 1
- shortcut widget as first-class item: Task 2
- remove old shortcut form list: Task 2
- Comet-style drag reorder hooks and contextual menus: Task 3
- URL drag/drop with validation: Task 4
- bookmarks only when available: Task 5

No gaps found against `docs/superpowers/specs/2026-06-25-sloppysafari-customize-addendum-design.md`.

### Placeholder Scan

- No `TBD` / `TODO`
- Each task includes exact files, tests, commands, and code blocks
- No cross-task “same as before” placeholders

### Type Consistency

- `openWidgetPickerSheet`, `closeWidgetPickerSheet`, and `renderWidgetPickerSheet` are introduced before later tasks depend on them
- `openShortcutEditor` / `commitShortcutDraft` are introduced before drag/drop and bookmark tasks use them
- drag state keys remain `activeId`, `overId`, and `dropPosition`

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-25-sloppysafari-customize-addendum-implementation.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
