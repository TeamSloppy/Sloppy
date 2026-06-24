# SloppySafari Start Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Comet-like SloppySafari new-tab start page with shared fullscreen chat sidebar, customizable shortcuts, theme, and background image.

**Architecture:** Add `start.html`/`startPage.js` as a WebExtension page selected by `chrome_url_overrides.newtab`, but reuse the existing `contentScript.js` shell and chat pipeline. Store all customization in sanitized `chrome.storage.local` settings handled by `panel.js` and `background.js`.

**Tech Stack:** Safari WebExtension Manifest V3, plain JavaScript modules/scripts, Node `node:test`, SwiftPM/Xcode project packaging.

## Global Constraints

- Follow `/Users/vlad-prusakov/Developer/Sloppy/AGENTS.md`.
- Use TDD: write each failing test before production changes and verify it fails.
- Preserve existing uncommitted changes in SloppySafari files.
- Do not add React/Vite or new frontend frameworks.
- Keep WebExtension files bundled for macOS, iOS, and visionOS extension targets.
- Manifest override is static; runtime disable changes `start.html` behavior, not the manifest.
- Shortcuts accept only `http:` and `https:` URLs.
- Theme values are exactly `"dark"` or `"light"`.
- Background image is stored as a data URL and must be image-only with a conservative size limit.

---

## File Structure

- Modify `Apps/SloppySafari/Extension/Resources/manifest.json`: add `chrome_url_overrides.newtab` and expose/copy start page resources.
- Create `Apps/SloppySafari/Extension/Resources/start.html`: new tab entry page.
- Create `Apps/SloppySafari/Extension/Resources/startPage.js`: marks start-page mode before `contentScript.js` initializes.
- Modify `Apps/SloppySafari/Extension/Resources/panel.js`: sanitize start-page settings and export helpers for tests.
- Modify `Apps/SloppySafari/Extension/Resources/background.js`: extend defaults and save/load settings path.
- Modify `Apps/SloppySafari/Extension/Resources/contentScript.js`: add shared sidebar, start-page mode rendering, customization controls, and start-to-chat transition.
- Modify `Apps/SloppySafari/Extension/Resources/panel.css`: add start page, disabled page, light/dark theme, sidebar, shortcut, and background image styles.
- Modify `Apps/SloppySafari/Extension/Resources/i18n.js`: add visible labels for start/customize UI.
- Modify `Apps/SloppySafari/project.yml` and generated `Apps/SloppySafari/SloppySafari.xcodeproj/project.pbxproj`: include `start.html` and `startPage.js` in every WebExtension bundle.
- Modify tests under `Apps/SloppySafari/Extension/Tests`.

---

### Task 1: Manifest And Packaging

**Files:**
- Create: `Apps/SloppySafari/Extension/Resources/start.html`
- Create: `Apps/SloppySafari/Extension/Resources/startPage.js`
- Modify: `Apps/SloppySafari/Extension/Resources/manifest.json`
- Modify: `Apps/SloppySafari/project.yml`
- Modify: `Apps/SloppySafari/SloppySafari.xcodeproj/project.pbxproj`
- Test: `Apps/SloppySafari/Extension/Tests/manifest.test.mjs`

**Interfaces:**
- Produces: `start.html` loads `panel.css`, `startPage.js`, `i18n.js`, and `contentScript.js` in that order.
- Produces: `startPage.js` sets `document.documentElement.classList.add("sloppy-start-page")` and `globalThis.SloppyStartPageMode = true`.
- Produces: `manifest.chrome_url_overrides.newtab === "start.html"`.

- [ ] **Step 1: Write failing manifest and packaging tests**

Add to `Apps/SloppySafari/Extension/Tests/manifest.test.mjs`:

```js
test("extension overrides new tabs with the Sloppy start page", () => {
  const manifest = loadManifest();

  assert.equal(manifest.chrome_url_overrides?.newtab, "start.html");
});

test("start page is packaged as an extension resource", () => {
  const manifest = loadManifest();
  const resources = manifest.web_accessible_resources || [];

  assert.equal(
    resources.some((entry) => entry.resources?.includes("start.html") && entry.resources?.includes("startPage.js")),
    true
  );
});

test("start page loads mode marker before localization and content script", () => {
  const html = readFileSync(new URL("../Resources/start.html", import.meta.url), "utf8");
  const startPageIndex = html.indexOf('src="startPage.js"');
  const i18nIndex = html.indexOf('src="i18n.js"');
  const contentScriptIndex = html.indexOf('src="contentScript.js"');

  assert.notEqual(startPageIndex, -1);
  assert.notEqual(i18nIndex, -1);
  assert.notEqual(contentScriptIndex, -1);
  assert.ok(startPageIndex < i18nIndex);
  assert.ok(i18nIndex < contentScriptIndex);
});

test("start page files are copied into every Safari web extension bundle", () => {
  const project = loadXcodeProject();
  const startHTMLCopies = project.match(/\/\* start\.html in Resources \*\/,/g) || [];
  const startPageCopies = project.match(/\/\* startPage\.js in Resources \*\/,/g) || [];

  assert.equal(startHTMLCopies.length, 3);
  assert.equal(startPageCopies.length, 3);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd Apps/SloppySafari/Extension
npm test -- Tests/manifest.test.mjs
```

Expected: FAIL because `start.html` is missing and `chrome_url_overrides` is undefined.

- [ ] **Step 3: Add minimal resources and manifest entries**

Create `Apps/SloppySafari/Extension/Resources/start.html`:

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Sloppy Start</title>
  <link rel="stylesheet" href="panel.css">
</head>
<body>
  <script src="startPage.js"></script>
  <script src="i18n.js"></script>
  <script src="contentScript.js"></script>
</body>
</html>
```

Create `Apps/SloppySafari/Extension/Resources/startPage.js`:

```js
document.documentElement.classList.add("sloppy-start-page");
globalThis.SloppyStartPageMode = true;
```

Modify `Apps/SloppySafari/Extension/Resources/manifest.json`:

```json
"chrome_url_overrides": {
  "newtab": "start.html"
},
"web_accessible_resources": [
  {
    "resources": ["so_logo.svg", "chat.html", "chatPage.js", "start.html", "startPage.js", "*.svg", "icons/*.svg"],
    "matches": ["<all_urls>"]
  }
]
```

Add `start.html` and `startPage.js` to `Apps/SloppySafari/project.yml` next to `chat.html` and `chatPage.js`, then regenerate or manually align `Apps/SloppySafari/SloppySafari.xcodeproj/project.pbxproj` so each appears in all three WebExtension resource copy phases.

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
cd Apps/SloppySafari/Extension
npm test -- Tests/manifest.test.mjs
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Apps/SloppySafari/Extension/Resources/manifest.json Apps/SloppySafari/Extension/Resources/start.html Apps/SloppySafari/Extension/Resources/startPage.js Apps/SloppySafari/project.yml Apps/SloppySafari/SloppySafari.xcodeproj/project.pbxproj Apps/SloppySafari/Extension/Tests/manifest.test.mjs
git commit -m "feat: add SloppySafari new tab start page resource"
```

---

### Task 2: Start Page Settings Sanitization

**Files:**
- Modify: `Apps/SloppySafari/Extension/Resources/panel.js`
- Modify: `Apps/SloppySafari/Extension/Resources/background.js`
- Test: `Apps/SloppySafari/Extension/Tests/panelPayload.test.mjs`

**Interfaces:**
- Produces: `sanitizeStartPageTheme(value: unknown): "dark" | "light"`.
- Produces: `sanitizeStartPageShortcuts(records: unknown[]): Array<{ title: string, url: string }>`
- Produces: `sanitizeStartPageBackgroundImage(value: unknown): string`.
- Produces: `sanitizeSettings(settings).startPageEnabled`.
- Produces: `sanitizeSettings(settings).startPageTheme`.
- Produces: `sanitizeSettings(settings).startPageBackgroundImage`.
- Produces: `sanitizeSettings(settings).startPageShortcuts`.

- [ ] **Step 1: Write failing sanitization tests**

Add imports in `Apps/SloppySafari/Extension/Tests/panelPayload.test.mjs` if needed:

```js
import {
  sanitizeSettings,
  sanitizeStartPageBackgroundImage,
  sanitizeStartPageShortcuts,
  sanitizeStartPageTheme
} from "../Resources/panel.js";
```

Add tests:

```js
test("sanitizeSettings defaults start page customization", () => {
  const settings = sanitizeSettings({});

  assert.equal(settings.startPageEnabled, true);
  assert.equal(settings.startPageTheme, "dark");
  assert.equal(settings.startPageBackgroundImage, "");
  assert.deepEqual(settings.startPageShortcuts, []);
});

test("sanitizeStartPageTheme accepts only light and dark", () => {
  assert.equal(sanitizeStartPageTheme("light"), "light");
  assert.equal(sanitizeStartPageTheme("dark"), "dark");
  assert.equal(sanitizeStartPageTheme("system"), "dark");
});

test("sanitizeStartPageShortcuts keeps only http and https urls", () => {
  assert.deepEqual(sanitizeStartPageShortcuts([
    { title: "GitHub", url: "https://github.com" },
    { title: "", url: "http://localhost:25101" },
    { title: "Bad", url: "javascript:alert(1)" },
    { title: "File", url: "file:///tmp/a" }
  ]), [
    { title: "GitHub", url: "https://github.com/" },
    { title: "localhost:25101", url: "http://localhost:25101/" }
  ]);
});

test("sanitizeStartPageBackgroundImage keeps small image data urls only", () => {
  assert.equal(sanitizeStartPageBackgroundImage("data:image/png;base64,abcd"), "data:image/png;base64,abcd");
  assert.equal(sanitizeStartPageBackgroundImage("data:text/html;base64,abcd"), "");
  assert.equal(sanitizeStartPageBackgroundImage("https://example.com/image.png"), "");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd Apps/SloppySafari/Extension
npm test -- Tests/panelPayload.test.mjs
```

Expected: FAIL because the exported helper functions and settings fields do not exist.

- [ ] **Step 3: Implement sanitizers in `panel.js`**

Add near existing settings helpers:

```js
const maxStartPageShortcuts = 8;
const maxStartPageBackgroundImageLength = 750000;

export function sanitizeStartPageTheme(value) {
  return String(value || "dark").trim() === "light" ? "light" : "dark";
}

export function sanitizeStartPageBackgroundImage(value) {
  const image = String(value || "").trim();
  if (!image) {
    return "";
  }
  if (image.length > maxStartPageBackgroundImageLength) {
    return "";
  }
  return /^data:image\/(png|jpe?g|gif|webp);base64,[a-z0-9+/=\s]+$/i.test(image) ? image : "";
}

export function sanitizeStartPageShortcuts(records = []) {
  return (Array.isArray(records) ? records : [])
    .map((record) => {
      const rawURL = String(record?.url || "").trim();
      let url = null;
      try {
        url = new URL(rawURL);
      } catch {
        return null;
      }
      if (url.protocol !== "http:" && url.protocol !== "https:") {
        return null;
      }
      const hostTitle = url.host || url.href;
      return {
        title: String(record?.title || hostTitle).trim() || hostTitle,
        url: url.href
      };
    })
    .filter(Boolean)
    .slice(0, maxStartPageShortcuts);
}
```

Extend `sanitizeSettings` return object:

```js
startPageEnabled: settings.startPageEnabled !== false,
startPageTheme: sanitizeStartPageTheme(settings.startPageTheme),
startPageBackgroundImage: sanitizeStartPageBackgroundImage(settings.startPageBackgroundImage),
startPageShortcuts: sanitizeStartPageShortcuts(settings.startPageShortcuts),
```

- [ ] **Step 4: Extend `background.js` defaults**

Update `defaultSettings`:

```js
const defaultSettings = {
  coreURLString: "http://127.0.0.1:25101",
  authToken: "",
  defaultAgentID: "sloppy",
  selectedModel: "",
  floatingButtonEnabled: true,
  selectionBubbleEnabled: true,
  startPageEnabled: true,
  startPageTheme: "dark",
  startPageBackgroundImage: "",
  startPageShortcuts: [],
  voiceLanguage: "auto"
};
```

- [ ] **Step 5: Run test to verify it passes**

Run:

```bash
cd Apps/SloppySafari/Extension
npm test -- Tests/panelPayload.test.mjs
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Apps/SloppySafari/Extension/Resources/panel.js Apps/SloppySafari/Extension/Resources/background.js Apps/SloppySafari/Extension/Tests/panelPayload.test.mjs
git commit -m "feat: sanitize SloppySafari start page settings"
```

---

### Task 3: Start Page UI And Customization

**Files:**
- Modify: `Apps/SloppySafari/Extension/Resources/contentScript.js`
- Modify: `Apps/SloppySafari/Extension/Resources/panel.css`
- Modify: `Apps/SloppySafari/Extension/Resources/i18n.js`
- Test: `Apps/SloppySafari/Extension/Tests/contentSelection.test.mjs`
- Test: `Apps/SloppySafari/Extension/Tests/manifest.test.mjs`

**Interfaces:**
- Consumes: `globalThis.SloppyStartPageMode === true`.
- Consumes: sanitized settings fields from Task 2.
- Produces: `isStartPageMode(): boolean`.
- Produces: `setStartPageMode(active: boolean): void`.
- Produces: `renderStartPageSurface(frame: HTMLElement): void`.
- Produces: settings controls with data attributes:
  - `data-sloppy-start-page-enabled`
  - `data-sloppy-start-page-theme`
  - `data-sloppy-start-page-background`
  - `data-sloppy-start-page-clear-background`
  - `data-sloppy-start-page-shortcuts`
  - `data-sloppy-start-page-add-shortcut`

- [ ] **Step 1: Write failing UI structure tests**

Add to `Apps/SloppySafari/Extension/Tests/contentSelection.test.mjs`:

```js
test("start page mode renders centered composer and shortcuts", () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      }
    }
  };
  vm.runInNewContext(`
    globalThis.SloppyStartPageMode = true;
    state.settings = {
      startPageEnabled: true,
      startPageTheme: "light",
      startPageShortcuts: [{ title: "GitHub", url: "https://github.com/" }]
    };
  `, sandbox);

  const panel = sandbox.ensurePanel();
  sandbox.render(panel);

  assert.match(panel.innerHTML, /data-sloppy-start-surface/);
  assert.match(panel.innerHTML, /data-sloppy-start-shortcut="https:\/\/github\.com\/"/);
  assert.match(panel.innerHTML, /sloppy-theme-light/);
});

test("settings dialog includes start page customization controls", () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      }
    }
  };

  const panel = sandbox.ensurePanel();

  assert.match(panel.innerHTML, /data-sloppy-start-page-enabled/);
  assert.match(panel.innerHTML, /data-sloppy-start-page-theme/);
  assert.match(panel.innerHTML, /data-sloppy-start-page-background/);
  assert.match(panel.innerHTML, /data-sloppy-start-page-add-shortcut/);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd Apps/SloppySafari/Extension
npm test -- Tests/contentSelection.test.mjs
```

Expected: FAIL because start-page rendering and controls do not exist.

- [ ] **Step 3: Add mode helpers and settings controls**

In `contentScript.js`, add:

```js
function isStartPageMode() {
  return Boolean(globalThis.SloppyStartPageMode) && !document.documentElement.classList.contains("sloppy-fullscreen-chat-page");
}

function setStartPageMode(active) {
  globalThis.SloppyStartPageMode = Boolean(active);
  document.documentElement.classList.toggle("sloppy-start-page", Boolean(active));
  document.documentElement.classList.toggle("sloppy-fullscreen-chat-page", !active);
}
```

Add Start Page controls inside the existing settings dialog form after selection bubble settings:

```html
<div class="sloppy-settings-section">
  <strong>${escapeHTML(t("startPage"))}</strong>
  <label class="sloppy-settings-toggle">
    <input data-sloppy-start-page-enabled type="checkbox">
    <span>${escapeHTML(t("enableStartPage"))}</span>
  </label>
  <label>${escapeHTML(t("theme"))}
    <select data-sloppy-start-page-theme>
      <option value="dark">${escapeHTML(t("darkTheme"))}</option>
      <option value="light">${escapeHTML(t("lightTheme"))}</option>
    </select>
  </label>
  <label>${escapeHTML(t("backgroundImage"))}<input data-sloppy-start-page-background type="file" accept="image/png,image/jpeg,image/gif,image/webp"></label>
  <button class="sloppy-settings-save" type="button" data-sloppy-start-page-clear-background>${escapeHTML(t("clearBackground"))}</button>
  <div class="sloppy-start-shortcut-editor" data-sloppy-start-page-shortcuts></div>
  <button class="sloppy-settings-save" type="button" data-sloppy-start-page-add-shortcut>${escapeHTML(t("addShortcut"))}</button>
  <p class="sloppy-settings-note" data-sloppy-start-page-error></p>
</div>
```

- [ ] **Step 4: Render start surface and shortcuts**

Add:

```js
function renderStartPageSurface(frame) {
  const thread = frame.querySelector("[data-sloppy-thread]");
  const settings = state.settings || {};
  const shortcuts = settings.startPageShortcuts || [];
  frame.classList.toggle("sloppy-theme-light", settings.startPageTheme === "light");
  frame.style.setProperty("--sloppy-start-background-image", settings.startPageBackgroundImage ? `url("${settings.startPageBackgroundImage}")` : "none");
  thread.innerHTML = `
    <section class="sloppy-start-surface" data-sloppy-start-surface>
      <img class="sloppy-empty-mark" src="${logoURL()}" alt="" aria-hidden="true">
      <h1>${escapeHTML(t("assistant"))}</h1>
      <div class="sloppy-start-shortcuts">
        ${shortcuts.map((shortcut) => `
          <a href="${escapeHTML(shortcut.url)}" data-sloppy-start-shortcut="${escapeHTML(shortcut.url)}">
            <span>${escapeHTML(shortcut.title)}</span>
          </a>
        `).join("")}
      </div>
    </section>
  `;
}
```

Update `render(frame)` before `renderThread(frame)`:

```js
if (isStartPageMode() && state.settings?.startPageEnabled !== false && !state.messages.length) {
  renderAgents(frame);
  renderModels(frame);
  renderVoiceControls(frame);
  renderStartPageSurface(frame);
  renderContext(frame);
  renderAttachments(frame);
  renderComposerAction(frame);
  return;
}
```

- [ ] **Step 5: Save customization controls**

In `openSettings(frame)`, populate:

```js
frame.querySelector("[data-sloppy-start-page-enabled]").checked = state.settings?.startPageEnabled !== false;
frame.querySelector("[data-sloppy-start-page-theme]").value = state.settings?.startPageTheme || "dark";
renderStartPageShortcutEditor(frame);
```

In `saveSettings(frame)`, include:

```js
startPageEnabled: frame.querySelector("[data-sloppy-start-page-enabled]").checked,
startPageTheme: frame.querySelector("[data-sloppy-start-page-theme]").value,
startPageBackgroundImage: state.settings?.startPageBackgroundImage || "",
startPageShortcuts: readStartPageShortcutEditor(frame),
```

Add shortcut editor helpers:

```js
function renderStartPageShortcutEditor(frame) {
  const root = frame.querySelector("[data-sloppy-start-page-shortcuts]");
  const shortcuts = state.settings?.startPageShortcuts || [];
  root.innerHTML = shortcuts.map((shortcut, index) => `
    <div class="sloppy-start-shortcut-row" data-sloppy-start-shortcut-row>
      <input data-sloppy-start-shortcut-title value="${escapeHTML(shortcut.title)}" placeholder="${escapeHTML(t("shortcutTitle"))}">
      <input data-sloppy-start-shortcut-url value="${escapeHTML(shortcut.url)}" placeholder="https://example.com">
      <button class="sloppy-icon-button" type="button" data-sloppy-remove-start-shortcut="${index}" aria-label="${escapeHTML(t("removeShortcut"))}">${icon("close")}</button>
    </div>
  `).join("");
}

function readStartPageShortcutEditor(frame) {
  return Array.from(frame.querySelectorAll("[data-sloppy-start-shortcut-row]")).map((row) => ({
    title: row.querySelector("[data-sloppy-start-shortcut-title]")?.value || "",
    url: row.querySelector("[data-sloppy-start-shortcut-url]")?.value || ""
  }));
}
```

Wire add/remove/background controls in `wirePanel(frame)`:

```js
frame.querySelector("[data-sloppy-start-page-add-shortcut]")?.addEventListener("click", () => {
  state.settings = {
    ...(state.settings || {}),
    startPageShortcuts: [
      ...(state.settings?.startPageShortcuts || []),
      { title: "", url: "" }
    ]
  };
  renderStartPageShortcutEditor(frame);
});
frame.querySelector("[data-sloppy-start-page-shortcuts]")?.addEventListener("click", (event) => {
  const button = event.target?.closest?.("[data-sloppy-remove-start-shortcut]");
  if (!button) {
    return;
  }
  const removeIndex = Number(button.dataset.sloppyRemoveStartShortcut);
  state.settings = {
    ...(state.settings || {}),
    startPageShortcuts: (state.settings?.startPageShortcuts || []).filter((_shortcut, index) => index !== removeIndex)
  };
  renderStartPageShortcutEditor(frame);
});
frame.querySelector("[data-sloppy-start-page-clear-background]")?.addEventListener("click", () => {
  state.settings = {
    ...(state.settings || {}),
    startPageBackgroundImage: ""
  };
  frame.querySelector("[data-sloppy-start-page-error]").textContent = "";
});
frame.querySelector("[data-sloppy-start-page-background]")?.addEventListener("change", (event) => {
  void readStartPageBackgroundImage(event.target.files?.[0], frame);
});
```

Add the file reader helper:

```js
function readStartPageBackgroundImage(file, frame) {
  const error = frame.querySelector("[data-sloppy-start-page-error]");
  if (!file) {
    return Promise.resolve();
  }
  if (!/^image\/(png|jpe?g|gif|webp)$/i.test(file.type || "")) {
    error.textContent = t("unsupportedBackgroundImage");
    return Promise.resolve();
  }
  if (file.size > 560000) {
    error.textContent = t("backgroundImageTooLarge");
    return Promise.resolve();
  }
  return new Promise((resolve) => {
    const reader = new FileReader();
    reader.addEventListener("load", () => {
      state.settings = {
        ...(state.settings || {}),
        startPageBackgroundImage: String(reader.result || "")
      };
      error.textContent = "";
      resolve();
    });
    reader.addEventListener("error", () => {
      error.textContent = t("backgroundImageReadFailed");
      resolve();
    });
    reader.readAsDataURL(file);
  });
}
```

- [ ] **Step 6: Add CSS and i18n**

Add CSS:

```css
.sloppy-start-page #sloppy-safari-extension-panel .sloppy-thread {
  display: grid;
  place-items: center;
}

.sloppy-start-page #sloppy-safari-extension-panel {
  background-image: var(--sloppy-start-background-image);
  background-size: cover;
  background-position: center;
}

.sloppy-start-surface {
  display: grid;
  width: min(620px, 100%);
  gap: 18px;
  justify-items: center;
}

.sloppy-start-shortcuts {
  display: grid;
  width: 100%;
  grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
  gap: 8px;
}

.sloppy-start-shortcuts a {
  min-width: 0;
  padding: 10px 12px;
  color: inherit;
  text-decoration: none;
  background: rgba(255, 255, 255, 0.08);
  border: 1px solid rgba(255, 255, 255, 0.12);
  border-radius: 8px;
}

#sloppy-safari-extension-panel.sloppy-theme-light {
  color: #171717;
  color-scheme: light;
}
```

Add these labels in each locale object in `i18n.js`, translating the values for Russian and Chinese while keeping the same keys:

```js
startPage: "Start Page",
enableStartPage: "Use Sloppy Start Page",
theme: "Theme",
darkTheme: "Dark",
lightTheme: "Light",
backgroundImage: "Background image",
clearBackground: "Clear background",
addShortcut: "Add shortcut",
removeShortcut: "Remove shortcut",
shortcutTitle: "Title",
unsupportedBackgroundImage: "Choose a PNG, JPEG, GIF, or WebP image.",
backgroundImageTooLarge: "Choose an image under 560 KB.",
backgroundImageReadFailed: "Unable to read that image."
```

- [ ] **Step 7: Run test to verify it passes**

Run:

```bash
cd Apps/SloppySafari/Extension
npm test -- Tests/contentSelection.test.mjs
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Apps/SloppySafari/Extension/Resources/contentScript.js Apps/SloppySafari/Extension/Resources/panel.css Apps/SloppySafari/Extension/Resources/i18n.js Apps/SloppySafari/Extension/Tests/contentSelection.test.mjs
git commit -m "feat: render customizable SloppySafari start page"
```

---

### Task 4: Shared Sidebar And Start-To-Chat Transition

**Files:**
- Modify: `Apps/SloppySafari/Extension/Resources/contentScript.js`
- Modify: `Apps/SloppySafari/Extension/Resources/panel.css`
- Test: `Apps/SloppySafari/Extension/Tests/contentSelection.test.mjs`

**Interfaces:**
- Consumes: `setStartPageMode(active)`.
- Produces: sidebar element with `data-sloppy-app-sidebar`.
- Produces: sidebar buttons:
  - `data-sloppy-sidebar-new`
  - `data-sloppy-sidebar-sessions`
  - `data-sloppy-sidebar-projects`
  - `data-sloppy-sidebar-settings`
  - `data-sloppy-sidebar-customize`
- Produces: `transitionStartPageToChat(frame: HTMLElement): void`.

- [ ] **Step 1: Write failing sidebar and transition tests**

Add:

```js
test("fullscreen chat shell includes the shared app sidebar", () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      }
    }
  };
  vm.runInNewContext("document.documentElement.classList.add('sloppy-fullscreen-chat-page');", sandbox);

  const panel = sandbox.ensurePanel();

  assert.match(panel.innerHTML, /data-sloppy-app-sidebar/);
  assert.match(panel.innerHTML, /data-sloppy-sidebar-new/);
  assert.match(panel.innerHTML, /data-sloppy-sidebar-sessions/);
  assert.match(panel.innerHTML, /data-sloppy-sidebar-customize/);
});

test("transitionStartPageToChat exits start mode before sending", () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      }
    }
  };
  vm.runInNewContext("globalThis.SloppyStartPageMode = true;", sandbox);
  const panel = sandbox.ensurePanel();

  sandbox.transitionStartPageToChat(panel);

  assert.equal(sandbox.SloppyStartPageMode, false);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd Apps/SloppySafari/Extension
npm test -- Tests/contentSelection.test.mjs
```

Expected: FAIL because sidebar and transition helper do not exist.

- [ ] **Step 3: Add sidebar markup to `ensurePanel()`**

Wrap the existing `.sloppy-shell` element with a layout. Insert this `<nav>` immediately before the current `<div class="sloppy-shell">`, insert an opening `<div class="sloppy-app-layout">` before the `<nav>`, and insert the matching closing `</div>` immediately after the current `</div>` that closes `.sloppy-shell`. Do not change the existing `.sloppy-shell` children while doing this step.

```html
<div class="sloppy-app-layout">
  <nav class="sloppy-app-sidebar" data-sloppy-app-sidebar aria-label="${escapeHTML(t("navigation"))}">
    <button class="sloppy-sidebar-item" type="button" data-sloppy-sidebar-new>${icon("plus")}<span>${escapeHTML(t("newSession"))}</span></button>
    <button class="sloppy-sidebar-item" type="button" data-sloppy-sidebar-sessions>${icon("sessions")}<span>${escapeHTML(t("sessions"))}</span></button>
    <button class="sloppy-sidebar-item" type="button" data-sloppy-sidebar-projects>${icon("project")}<span>${escapeHTML(t("projects"))}</span></button>
    <button class="sloppy-sidebar-item" type="button" data-sloppy-sidebar-settings>${icon("settings")}<span>${escapeHTML(t("settings"))}</span></button>
    <button class="sloppy-sidebar-item" type="button" data-sloppy-sidebar-customize>${icon("customize")}<span>${escapeHTML(t("customize"))}</span></button>
  </nav>
</div>
```

Add these cases to the existing `icon(name)` helper:

```js
if (name === "project") {
  return '<span class="sloppy-symbol" aria-hidden="true">◇</span>';
}
if (name === "customize") {
  return '<span class="sloppy-symbol" aria-hidden="true">◌</span>';
}
```

- [ ] **Step 4: Wire sidebar actions**

In `wirePanel(frame)`:

```js
frame.querySelector("[data-sloppy-sidebar-new]")?.addEventListener("click", () => {
  state.messages = [];
  delete ensureSettings().sessionId;
  setStartPageMode(Boolean(globalThis.SloppyStartPageMode));
  render(frame);
});
frame.querySelector("[data-sloppy-sidebar-sessions]")?.addEventListener("click", () => openSessions(frame));
frame.querySelector("[data-sloppy-sidebar-settings]")?.addEventListener("click", () => openSettings(frame));
frame.querySelector("[data-sloppy-sidebar-customize]")?.addEventListener("click", () => openSettings(frame));
frame.querySelector("[data-sloppy-sidebar-projects]")?.addEventListener("click", () => {
  appendMessage({ role: "assistant", label: t("assistant"), text: t("projectsUnavailable") });
  transitionStartPageToChat(frame);
  render(frame);
});
```

- [ ] **Step 5: Add transition helper and call it on send/select**

Add:

```js
function transitionStartPageToChat(frame) {
  if (!isStartPageMode()) {
    return;
  }
  setStartPageMode(false);
  frame.classList.remove("sloppy-theme-light");
}
```

At the start of `sendPrompt(frame)`, before reading/sending payload:

```js
transitionStartPageToChat(frame);
```

In `selectSession(frame, sessionId)`, before `render(frame)` on successful session selection:

```js
transitionStartPageToChat(frame);
```

- [ ] **Step 6: Add sidebar CSS**

Add:

```css
.sloppy-fullscreen-chat-page #sloppy-safari-extension-panel .sloppy-app-layout,
.sloppy-start-page #sloppy-safari-extension-panel .sloppy-app-layout {
  display: grid;
  grid-template-columns: 168px minmax(0, 1fr);
  width: 100%;
  height: 100%;
}

.sloppy-app-sidebar {
  display: none;
}

.sloppy-fullscreen-chat-page #sloppy-safari-extension-panel .sloppy-app-sidebar,
.sloppy-start-page #sloppy-safari-extension-panel .sloppy-app-sidebar {
  display: grid;
  align-content: start;
  gap: 4px;
  padding: 16px 8px;
  background: rgba(255, 255, 255, 0.04);
  border-right: 1px solid rgba(255, 255, 255, 0.1);
}

.sloppy-sidebar-item {
  display: grid;
  grid-template-columns: 20px minmax(0, 1fr);
  align-items: center;
  gap: 8px;
  width: 100%;
  min-height: 34px;
  padding: 7px 8px;
  color: inherit;
  text-align: left;
  background: transparent;
  border: 0;
  border-radius: 8px;
}

.sloppy-sidebar-item:hover,
.sloppy-sidebar-item:focus-visible {
  background: rgba(255, 255, 255, 0.08);
}

@media (max-width: 720px) {
  .sloppy-fullscreen-chat-page #sloppy-safari-extension-panel .sloppy-app-layout,
  .sloppy-start-page #sloppy-safari-extension-panel .sloppy-app-layout {
    grid-template-columns: 56px minmax(0, 1fr);
  }

  .sloppy-sidebar-item span {
    display: none;
  }
}
```

- [ ] **Step 7: Run test to verify it passes**

Run:

```bash
cd Apps/SloppySafari/Extension
npm test -- Tests/contentSelection.test.mjs
```

Expected: PASS.

- [ ] **Step 8: Run full extension test suite**

Run:

```bash
cd Apps/SloppySafari/Extension
npm test
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add Apps/SloppySafari/Extension/Resources/contentScript.js Apps/SloppySafari/Extension/Resources/panel.css Apps/SloppySafari/Extension/Tests/contentSelection.test.mjs
git commit -m "feat: share SloppySafari sidebar across start and chat pages"
```

---

## Final Verification

- [ ] Run extension tests:

```bash
cd Apps/SloppySafari/Extension
npm test
```

Expected: PASS.

- [ ] Run Swift package tests if project files changed:

```bash
cd Apps/SloppySafari
swift test
```

Expected: PASS.

- [ ] Build macOS app if Xcode project changed:

```bash
cd Apps/SloppySafari
xcodebuild -project SloppySafari.xcodeproj -scheme SloppySafari-macOS build -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: build succeeds with no new errors.

## Self-Review Notes

- Spec coverage: manifest override, disabled-state limitation, shared sidebar, start-to-chat transition, shortcuts, theme, background image, settings, tests, and packaging are covered by Tasks 1-4.
- Placeholder scan: no deferred implementation placeholders remain; each task names exact files, functions, and verification commands.
- Type consistency: settings keys match the design spec and are introduced in Task 2 before UI consumption in Tasks 3-4.
