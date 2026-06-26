# SloppySafari Customize Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat SloppySafari start-page customize form with a navigation-style customization flow that supports `General` and `Widgets` sections, a live-preview widget editor, and a flexible span-based grid with reorder / resize / delete.

**Architecture:** Keep the feature inside the existing Safari extension resource bundle by extending `contentScript.js` state, rendering, and event wiring rather than introducing a new framework. Store all start-page layout metadata inside `startPageItems`, render a deterministic span-grid from `order + colSpan + rowSpan`, and model the widget editor as a draft-based pushed screen inside the existing customize dialog.

**Tech Stack:** Safari extension resources (`contentScript.js`, `panel.css`, `i18n.js`), Swift Testing resource-level regression tests in `Apps/SloppySafari/Tests/SloppySafariCoreTests/`.

## Global Constraints

- Project type: SwiftPM agent runtime (Swift 6.2) + React/Vite dashboard + Apple client.
- Keep API behavior backward-compatible unless task explicitly allows breaking change.
- Do not introduce language heuristics for agent behavior; rely on explicit state and structured data.
- Preserve existing JS formatting style in Safari extension resources.
- Update/add tests when changing behavior.
- Run the smallest relevant verification first.
- Scope of this plan is only the approved `Customize` redesign from `docs/superpowers/specs/2026-06-25-sloppysafari-customize-design.md`.

---

## File Structure

- Modify: `Apps/SloppySafari/Extension/Resources/contentScript.js`
  - Owns customize navigation state, start-page item migration helpers, grid rendering, widget editor rendering, and event wiring.
- Modify: `Apps/SloppySafari/Extension/Resources/panel.css`
  - Owns customize shell layout, widgets grid, edit affordances, widget editor layout, and responsive behavior.
- Modify: `Apps/SloppySafari/Extension/Resources/i18n.js`
  - Owns new copy for `General`, `Widgets`, edit mode, resize / delete / done / cancel, and widget editor labels.
- Modify: `Apps/SloppySafari/Tests/SloppySafariCoreTests/SidebarRestoreButtonResourceTests.swift`
  - Extend existing resource-level assertions for customize navigation, shell placement, and sidebar interactions.
- Create: `Apps/SloppySafari/Tests/SloppySafariCoreTests/CustomizeFlowResourceTests.swift`
  - New focused resource-level tests for grid metadata, widget editor draft flow, and edit controls.

## Task 1: Build The Navigation-Style Customize Shell

**Files:**
- Modify: `Apps/SloppySafari/Extension/Resources/contentScript.js`
- Modify: `Apps/SloppySafari/Extension/Resources/panel.css`
- Modify: `Apps/SloppySafari/Extension/Resources/i18n.js`
- Create: `Apps/SloppySafari/Tests/SloppySafariCoreTests/CustomizeFlowResourceTests.swift`

**Interfaces:**
- Consumes: existing `openCustomize(frame)`, `saveCustomize(frame)`, `renderStartPageShortcutEditor(frame)`, `renderWidgetPicker(frame)`, `state.settings`.
- Produces:
  - `state.customizeNavigation = { screen: "home" | "general" | "widgets" | "widget-editor", editing: boolean, widgetDraft: null | object, widgetDraftSourceId: string | null }`
  - `renderCustomizeDialog(frame)`
  - `navigateCustomize(frame, screen)`

- [ ] **Step 1: Write the failing resource test for the navigation shell**

```swift
import Foundation
import Testing

@Test("customize flow renders navigation shell with general and widgets sections")
func customizeFlowRendersNavigationShell() throws {
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

    #expect(contentScript.contains("state.customizeNavigation"))
    #expect(contentScript.contains("renderCustomizeDialog(frame)"))
    #expect(contentScript.contains("data-sloppy-customize-screen"))
    #expect(panelCSS.contains(".sloppy-customize-nav"))
    #expect(i18n.contains("widgetsSection"))
    #expect(i18n.contains("generalSection"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter customizeFlowRendersNavigationShell`

Expected: FAIL with missing `customizeNavigation`, `renderCustomizeDialog(frame)`, and new copy keys.

- [ ] **Step 3: Write the minimal navigation shell implementation**

```javascript
const state = {
  // existing fields...
  customizeNavigation: {
    screen: "home",
    editing: false,
    widgetDraft: null,
    widgetDraftSourceId: null
  }
};

function navigateCustomize(frame, screen) {
  state.customizeNavigation = {
    ...state.customizeNavigation,
    screen
  };
  renderCustomizeDialog(frame);
}

function renderCustomizeDialog(frame) {
  const root = frame.querySelector("[data-sloppy-customize-body]");
  if (!root) {
    return;
  }
  if (state.customizeNavigation.screen === "home") {
    root.innerHTML = `
      <div class="sloppy-customize-nav" data-sloppy-customize-screen="home">
        <button type="button" data-sloppy-open-general>${escapeHTML(t("generalSection"))}</button>
        <button type="button" data-sloppy-open-widgets>${escapeHTML(t("widgetsSection"))}</button>
      </div>
    `;
    return;
  }
  // Task 2 and Task 4 extend these branches.
}

function openCustomize(frame) {
  state.customizeNavigation = {
    screen: "home",
    editing: false,
    widgetDraft: null,
    widgetDraftSourceId: null
  };
  renderCustomizeDialog(frame);
  frame.querySelector("[data-sloppy-customize-dialog]").showModal();
}
```

```css
.sloppy-customize-nav {
  display: grid;
  gap: 12px;
}
```

```javascript
en: {
  // existing keys...
  generalSection: "General",
  widgetsSection: "Widgets"
}
```

- [ ] **Step 4: Wire the customize dialog root and back navigation**

```javascript
<dialog class="sloppy-settings-dialog sloppy-customize-dialog" data-sloppy-customize-dialog>
  <form method="dialog" class="sloppy-settings-card">
    <header>
      <strong>${escapeHTML(t("startPage"))}</strong>
      <button class="sloppy-icon-button" value="cancel" aria-label="${escapeHTML(t("closeSettings"))}">${icon("close")}</button>
    </header>
    <div class="sloppy-customize-body" data-sloppy-customize-body></div>
  </form>
</dialog>
```

```javascript
frame.querySelector("[data-sloppy-customize-body]")?.addEventListener("click", (event) => {
  if (event.target?.closest?.("[data-sloppy-open-general]")) {
    navigateCustomize(frame, "general");
    return;
  }
  if (event.target?.closest?.("[data-sloppy-open-widgets]")) {
    navigateCustomize(frame, "widgets");
  }
});
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter customizeFlowRendersNavigationShell`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Apps/SloppySafari/Extension/Resources/contentScript.js Apps/SloppySafari/Extension/Resources/panel.css Apps/SloppySafari/Extension/Resources/i18n.js Apps/SloppySafari/Tests/SloppySafariCoreTests/CustomizeFlowResourceTests.swift
git commit -m "feat: add customize navigation shell"
```

## Task 2: Migrate Start Page Items To Span-Grid Metadata

**Files:**
- Modify: `Apps/SloppySafari/Extension/Resources/contentScript.js`
- Modify: `Apps/SloppySafari/Extension/Resources/panel.css`
- Test: `Apps/SloppySafari/Tests/SloppySafariCoreTests/CustomizeFlowResourceTests.swift`

**Interfaces:**
- Consumes: `state.settings.startPageItems`, `startPageShortcutItems(settings)`, `startPageWidgetItems(settings)`, existing `saveCustomize(frame)`.
- Produces:
  - `normalizeStartPageItem(record, fallbackOrder)`
  - `normalizedStartPageItems(settings)`
  - `applyLegacyWidgetSize(size) -> { colSpan, rowSpan }`
  - `renderWidgetsGrid(frame, items)`

- [ ] **Step 1: Write the failing resource test for span-grid metadata**

```swift
@Test("start page items migrate to span-based layout metadata")
func startPageItemsMigrateToSpanGridMetadata() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let contentScriptURL = packageRoot.appendingPathComponent("Extension/Resources/contentScript.js")
    let panelCSSURL = packageRoot.appendingPathComponent("Extension/Resources/panel.css")

    let contentScript = try String(contentsOf: contentScriptURL, encoding: .utf8)
    let panelCSS = try String(contentsOf: panelCSSURL, encoding: .utf8)

    #expect(contentScript.contains("normalizeStartPageItem(record, fallbackOrder)"))
    #expect(contentScript.contains("applyLegacyWidgetSize(size)"))
    #expect(contentScript.contains("colSpan"))
    #expect(contentScript.contains("rowSpan"))
    #expect(panelCSS.contains(".sloppy-widgets-grid"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter startPageItemsMigrateToSpanGridMetadata`

Expected: FAIL because the migration helpers and widgets grid do not exist yet.

- [ ] **Step 3: Write the migration helpers**

```javascript
function applyLegacyWidgetSize(size) {
  if (size === "medium") {
    return { colSpan: 2, rowSpan: 1 };
  }
  if (size === "large") {
    return { colSpan: 2, rowSpan: 2 };
  }
  return { colSpan: 1, rowSpan: 1 };
}

function normalizeStartPageItem(record, fallbackOrder) {
  const kind = String(record?.kind || "shortcut").trim() === "widget" ? "widget" : "shortcut";
  const legacySpan = kind === "widget" ? applyLegacyWidgetSize(String(record?.size || "").trim()) : { colSpan: 1, rowSpan: 1 };
  return {
    ...record,
    id: String(record?.id || record?.artifactId || record?.url || `${kind}-${fallbackOrder}`),
    kind,
    order: Number.isFinite(Number(record?.order)) ? Number(record.order) : fallbackOrder,
    colSpan: Math.max(1, Number(record?.colSpan) || legacySpan.colSpan),
    rowSpan: Math.max(1, Number(record?.rowSpan) || legacySpan.rowSpan)
  };
}

function normalizedStartPageItems(settings = state.settings || {}) {
  const records = Array.isArray(settings.startPageItems) && settings.startPageItems.length
    ? settings.startPageItems
    : (settings.startPageShortcuts || []).map((shortcut) => ({ kind: "shortcut", ...shortcut }));
  return records.map((record, index) => normalizeStartPageItem(record, index));
}
```

- [ ] **Step 4: Render the grid from normalized items**

```javascript
function renderWidgetsGrid(frame, items) {
  const root = frame.querySelector("[data-sloppy-widgets-grid]");
  if (!root) {
    return;
  }
  const sorted = [...items].sort((lhs, rhs) => lhs.order - rhs.order);
  root.innerHTML = sorted.map((item) => `
    <article
      class="sloppy-grid-item sloppy-grid-item-${escapeHTML(item.kind)}"
      data-sloppy-grid-item="${escapeHTML(item.id)}"
      style="--sloppy-col-span:${item.colSpan};--sloppy-row-span:${item.rowSpan};"
    >
      <strong>${escapeHTML(item.title || item.url || item.artifactId || item.id)}</strong>
    </article>
  `).join("");
}
```

```css
.sloppy-widgets-grid {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 12px;
}

.sloppy-grid-item {
  grid-column: span var(--sloppy-col-span);
  grid-row: span var(--sloppy-row-span);
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter startPageItemsMigrateToSpanGridMetadata`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Apps/SloppySafari/Extension/Resources/contentScript.js Apps/SloppySafari/Extension/Resources/panel.css Apps/SloppySafari/Tests/SloppySafariCoreTests/CustomizeFlowResourceTests.swift
git commit -m "feat: add start page span grid model"
```

## Task 3: Implement Widgets Edit Mode With Reorder, Resize, And Delete

**Files:**
- Modify: `Apps/SloppySafari/Extension/Resources/contentScript.js`
- Modify: `Apps/SloppySafari/Extension/Resources/panel.css`
- Modify: `Apps/SloppySafari/Extension/Resources/i18n.js`
- Test: `Apps/SloppySafari/Tests/SloppySafariCoreTests/CustomizeFlowResourceTests.swift`

**Interfaces:**
- Consumes: `state.customizeNavigation.editing`, `normalizedStartPageItems(settings)`, `renderWidgetsGrid(frame, items)`.
- Produces:
  - `toggleCustomizeEditMode(frame)`
  - `resizeStartPageItem(itemId, colSpan, rowSpan)`
  - `removeStartPageItem(itemId)`
  - `moveStartPageItem(itemId, direction)`

- [ ] **Step 1: Write the failing resource test for edit controls**

```swift
@Test("widgets screen exposes edit mode with reorder resize and delete controls")
func widgetsScreenExposesEditControls() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let contentScriptURL = packageRoot.appendingPathComponent("Extension/Resources/contentScript.js")
    let i18nURL = packageRoot.appendingPathComponent("Extension/Resources/i18n.js")

    let contentScript = try String(contentsOf: contentScriptURL, encoding: .utf8)
    let i18n = try String(contentsOf: i18nURL, encoding: .utf8)

    #expect(contentScript.contains("data-sloppy-toggle-edit"))
    #expect(contentScript.contains("data-sloppy-resize-item"))
    #expect(contentScript.contains("data-sloppy-delete-item"))
    #expect(contentScript.contains("data-sloppy-move-item"))
    #expect(i18n.contains("editWidgets"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter widgetsScreenExposesEditControls`

Expected: FAIL with missing edit-mode controls and copy.

- [ ] **Step 3: Render the widgets screen and edit affordances**

```javascript
function renderCustomizeWidgetsScreen(frame) {
  const root = frame.querySelector("[data-sloppy-customize-body]");
  const items = normalizedStartPageItems(state.settings);
  root.innerHTML = `
    <section class="sloppy-customize-widgets" data-sloppy-customize-screen="widgets">
      <header class="sloppy-customize-toolbar">
        <button type="button" data-sloppy-back-customize>${escapeHTML(t("back"))}</button>
        <button type="button" data-sloppy-toggle-edit>${escapeHTML(state.customizeNavigation.editing ? t("done") : t("editWidgets"))}</button>
        <button type="button" data-sloppy-open-widget-editor>${escapeHTML(t("addWidget"))}</button>
      </header>
      <div class="sloppy-widgets-grid" data-sloppy-widgets-grid></div>
    </section>
  `;
  renderWidgetsGrid(frame, items);
}
```

```javascript
function renderWidgetsGrid(frame, items) {
  const root = frame.querySelector("[data-sloppy-widgets-grid]");
  if (!root) {
    return;
  }
  const editing = Boolean(state.customizeNavigation.editing);
  root.innerHTML = [...items].sort((lhs, rhs) => lhs.order - rhs.order).map((item) => `
    <article class="sloppy-grid-item" data-sloppy-grid-item="${escapeHTML(item.id)}" style="--sloppy-col-span:${item.colSpan};--sloppy-row-span:${item.rowSpan};">
      ${editing ? `
        <div class="sloppy-grid-item-controls">
          <button type="button" data-sloppy-move-item="${escapeHTML(item.id)}" data-direction="backward">←</button>
          <button type="button" data-sloppy-move-item="${escapeHTML(item.id)}" data-direction="forward">→</button>
          <button type="button" data-sloppy-resize-item="${escapeHTML(item.id)}" data-span="2x2">Resize</button>
          <button type="button" data-sloppy-delete-item="${escapeHTML(item.id)}">Delete</button>
        </div>
      ` : ""}
      <strong>${escapeHTML(item.title || item.url || item.artifactId || item.id)}</strong>
    </article>
  `).join("");
}
```

- [ ] **Step 4: Implement item mutation helpers**

```javascript
function updateStartPageItems(mutator) {
  const currentItems = normalizedStartPageItems(state.settings);
  state.settings = {
    ...(state.settings || {}),
    startPageItems: mutator(currentItems)
  };
}

function removeStartPageItem(itemId) {
  updateStartPageItems((items) => items.filter((item) => item.id !== itemId).map((item, index) => ({ ...item, order: index })));
}

function resizeStartPageItem(itemId, colSpan, rowSpan) {
  updateStartPageItems((items) => items.map((item) => item.id === itemId ? { ...item, colSpan, rowSpan } : item));
}

function moveStartPageItem(itemId, direction) {
  updateStartPageItems((items) => {
    const sorted = [...items].sort((lhs, rhs) => lhs.order - rhs.order);
    const index = sorted.findIndex((item) => item.id === itemId);
    const target = direction === "backward" ? index - 1 : index + 1;
    if (index < 0 || target < 0 || target >= sorted.length) {
      return sorted;
    }
    const swap = sorted[index];
    sorted[index] = sorted[target];
    sorted[target] = swap;
    return sorted.map((item, nextIndex) => ({ ...item, order: nextIndex }));
  });
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter widgetsScreenExposesEditControls`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Apps/SloppySafari/Extension/Resources/contentScript.js Apps/SloppySafari/Extension/Resources/panel.css Apps/SloppySafari/Extension/Resources/i18n.js Apps/SloppySafari/Tests/SloppySafariCoreTests/CustomizeFlowResourceTests.swift
git commit -m "feat: add widgets edit mode controls"
```

## Task 4: Implement Draft-Based Widget Editor With Live Preview

**Files:**
- Modify: `Apps/SloppySafari/Extension/Resources/contentScript.js`
- Modify: `Apps/SloppySafari/Extension/Resources/panel.css`
- Modify: `Apps/SloppySafari/Extension/Resources/i18n.js`
- Test: `Apps/SloppySafari/Tests/SloppySafariCoreTests/CustomizeFlowResourceTests.swift`

**Interfaces:**
- Consumes: `state.customizeNavigation.widgetDraft`, `addWidgetToStartPage(frame, artifactId, options)`, widget artifact responses from `sloppy.artifacts.widget` and `sloppy.artifacts.widget.generate`.
- Produces:
  - `openWidgetEditor(frame, sourceItemId = null)`
  - `renderWidgetEditor(frame)`
  - `updateWidgetDraftFromPrompt(frame, prompt)`
  - `commitWidgetDraft(frame)`

- [ ] **Step 1: Write the failing resource test for widget editor draft flow**

```swift
@Test("widget editor uses a draft preview with done and cancel actions")
func widgetEditorUsesDraftPreviewFlow() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let contentScriptURL = packageRoot.appendingPathComponent("Extension/Resources/contentScript.js")
    let i18nURL = packageRoot.appendingPathComponent("Extension/Resources/i18n.js")

    let contentScript = try String(contentsOf: contentScriptURL, encoding: .utf8)
    let i18n = try String(contentsOf: i18nURL, encoding: .utf8)

    #expect(contentScript.contains("openWidgetEditor(frame, sourceItemId = null)"))
    #expect(contentScript.contains("commitWidgetDraft(frame)"))
    #expect(contentScript.contains("data-sloppy-widget-preview"))
    #expect(contentScript.contains("data-sloppy-widget-editor-prompt"))
    #expect(i18n.contains("widgetEditorDone"))
    #expect(i18n.contains("widgetEditorCancel"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter widgetEditorUsesDraftPreviewFlow`

Expected: FAIL because widget editor draft flow is not present.

- [ ] **Step 3: Render the widget editor screen**

```javascript
function openWidgetEditor(frame, sourceItemId = null) {
  const sourceItem = normalizedStartPageItems(state.settings).find((item) => item.id === sourceItemId) || null;
  state.customizeNavigation = {
    ...state.customizeNavigation,
    screen: "widget-editor",
    widgetDraftSourceId: sourceItemId,
    widgetDraft: sourceItem ? { ...sourceItem } : { id: "", kind: "widget", title: "", artifactId: "", colSpan: 2, rowSpan: 1, html: "" }
  };
  renderCustomizeDialog(frame);
}

function renderWidgetEditor(frame) {
  const draft = state.customizeNavigation.widgetDraft;
  const root = frame.querySelector("[data-sloppy-customize-body]");
  root.innerHTML = `
    <section class="sloppy-widget-editor" data-sloppy-customize-screen="widget-editor">
      <header class="sloppy-customize-toolbar">
        <button type="button" data-sloppy-widget-editor-cancel>${escapeHTML(t("widgetEditorCancel"))}</button>
        <button type="button" data-sloppy-widget-editor-done>${escapeHTML(t("widgetEditorDone"))}</button>
      </header>
      <article class="sloppy-widget-editor-preview" data-sloppy-widget-preview>
        ${draft?.html ? `<iframe sandbox="allow-scripts" srcdoc="${escapeHTML(draft.html)}"></iframe>` : `<div class="sloppy-widget-editor-empty">${escapeHTML(t("describeWidget"))}</div>`}
      </article>
      <textarea data-sloppy-widget-editor-prompt rows="4" placeholder="${escapeHTML(t("describeWidget"))}"></textarea>
      <button type="button" data-sloppy-widget-editor-send>${escapeHTML(t("generateWidget"))}</button>
    </section>
  `;
}
```

- [ ] **Step 4: Implement live preview update and draft commit**

```javascript
async function updateWidgetDraftFromPrompt(frame, prompt) {
  const response = await chrome.runtime.sendMessage({
    type: "sloppy.artifacts.widget.generate",
    prompt,
    size: "medium"
  }).catch((error) => ({ error: error.message }));
  if (response?.error || !response?.artifact) {
    frame.querySelector("[data-sloppy-start-page-error]")?.textContent = response?.error || "Widget generation failed.";
    return;
  }
  state.artifacts = [response.artifact, ...(state.artifacts || []).filter((artifact) => artifact?.id !== response.artifact.id)];
  state.customizeNavigation = {
    ...state.customizeNavigation,
    widgetDraft: {
      ...(state.customizeNavigation.widgetDraft || {}),
      id: state.customizeNavigation.widgetDraft?.id || `widget-${Date.now()}`,
      kind: "widget",
      artifactId: response.artifact.id,
      title: response.artifact.title || response.artifact.id,
      html: String(response.html || response.artifact.html || "").trim()
    }
  };
  renderWidgetEditor(frame);
}

function commitWidgetDraft(frame) {
  const draft = state.customizeNavigation.widgetDraft;
  if (!draft?.artifactId) {
    navigateCustomize(frame, "widgets");
    return;
  }
  updateStartPageItems((items) => {
    const next = state.customizeNavigation.widgetDraftSourceId
      ? items.map((item) => item.id === state.customizeNavigation.widgetDraftSourceId ? draft : item)
      : [...items, { ...draft, order: items.length }];
    return next.map((item, index) => ({ ...item, order: index }));
  });
  state.customizeNavigation = {
    ...state.customizeNavigation,
    screen: "widgets",
    widgetDraft: null,
    widgetDraftSourceId: null
  };
  renderCustomizeDialog(frame);
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter widgetEditorUsesDraftPreviewFlow`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Apps/SloppySafari/Extension/Resources/contentScript.js Apps/SloppySafari/Extension/Resources/panel.css Apps/SloppySafari/Extension/Resources/i18n.js Apps/SloppySafari/Tests/SloppySafariCoreTests/CustomizeFlowResourceTests.swift
git commit -m "feat: add widget editor draft flow"
```

## Task 5: Persist Layout Changes And Cover Migration / Delete Paths

**Files:**
- Modify: `Apps/SloppySafari/Extension/Resources/contentScript.js`
- Modify: `Apps/SloppySafari/Tests/SloppySafariCoreTests/CustomizeFlowResourceTests.swift`
- Modify: `Apps/SloppySafari/Tests/SloppySafariCoreTests/SidebarRestoreButtonResourceTests.swift`

**Interfaces:**
- Consumes: `saveCustomize(frame)`, `updateStartPageItems(mutator)`, `commitWidgetDraft(frame)`.
- Produces:
  - `persistCustomizeState(frame)`
  - finalized `startPageItems` with `id/order/colSpan/rowSpan`
  - migration-safe delete / reorder / resize persistence

- [ ] **Step 1: Write the failing resource tests for persistence and deletion**

```swift
@Test("customize saves migrated span items instead of legacy shortcut-only state")
func customizeSavesMigratedSpanItems() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let contentScriptURL = packageRoot.appendingPathComponent("Extension/Resources/contentScript.js")
    let contentScript = try String(contentsOf: contentScriptURL, encoding: .utf8)

    #expect(contentScript.contains("persistCustomizeState(frame)"))
    #expect(contentScript.contains("startPageItems: normalizedStartPageItems(state.settings)"))
    #expect(contentScript.contains("removeStartPageItem(itemId)"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter customizeSavesMigratedSpanItems`

Expected: FAIL because persistence still saves the old flat state shape.

- [ ] **Step 3: Persist the new structure**

```javascript
async function persistCustomizeState(frame) {
  const settings = {
    ...(state.settings || {}),
    startPageEnabled: frame.querySelector("[data-sloppy-start-page-enabled]")?.checked ?? state.settings?.startPageEnabled !== false,
    startPageTheme: frame.querySelector("[data-sloppy-start-page-theme]")?.value || state.settings?.startPageTheme || "dark",
    startPageBackgroundImage: state.settings?.startPageBackgroundImage || "",
    startPageShortcuts: normalizedStartPageItems(state.settings)
      .filter((item) => item.kind === "shortcut")
      .map((item) => ({ title: item.title, url: item.url })),
    startPageItems: normalizedStartPageItems(state.settings)
  };
  state.settings = await chrome.runtime.sendMessage({ type: "sloppy.settings.save", settings });
}

async function saveCustomize(frame) {
  await persistCustomizeState(frame);
  frame.querySelector("[data-sloppy-customize-dialog]").close();
  render(frame);
}
```

- [ ] **Step 4: Run the focused Safari customize test set**

Run: `swift test --filter 'SidebarRestoreButtonResourceTests|CustomizeFlowResourceTests'`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Apps/SloppySafari/Extension/Resources/contentScript.js Apps/SloppySafari/Tests/SloppySafariCoreTests/CustomizeFlowResourceTests.swift Apps/SloppySafari/Tests/SloppySafariCoreTests/SidebarRestoreButtonResourceTests.swift
git commit -m "feat: persist customize span grid state"
```

## Self-Review

### Spec Coverage

- `General` and `Widgets` split: Task 1
- internal navigation-style customize flow: Task 1
- span-grid metadata and migration: Task 2
- reorder / resize / delete: Task 3
- widget editor with draft preview and `Done` / `Cancel`: Task 4
- persistence of new model: Task 5

No gaps found against `docs/superpowers/specs/2026-06-25-sloppysafari-customize-design.md`.

### Placeholder Scan

- No `TBD` / `TODO`
- Each task has explicit files, interfaces, commands, and code blocks
- Commands use narrow `swift test --filter ...` verification

### Type Consistency

- `state.customizeNavigation` is introduced in Task 1 and used consistently in Tasks 2-5
- `normalizeStartPageItem`, `normalizedStartPageItems`, and `renderWidgetsGrid` are defined before mutation and widget-editor tasks use them
- Grid metadata keys stay `id`, `order`, `colSpan`, `rowSpan` throughout the plan

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-25-sloppysafari-customize-implementation.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
