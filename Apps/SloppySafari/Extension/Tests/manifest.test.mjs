import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { test } from "node:test";

function loadManifest() {
  return JSON.parse(readFileSync(new URL("../Resources/manifest.json", import.meta.url), "utf8"));
}

function loadPanelCSS() {
  return readFileSync(new URL("../Resources/panel.css", import.meta.url), "utf8");
}

function loadContentScript() {
  return readFileSync(new URL("../Resources/contentScript.js", import.meta.url), "utf8");
}

function loadChatHTML() {
  return readFileSync(new URL("../Resources/chat.html", import.meta.url), "utf8");
}

function loadXcodeProject() {
  return readFileSync(new URL("../../SloppySafari.xcodeproj/project.pbxproj", import.meta.url), "utf8");
}

test("host permissions use valid WebExtension match patterns", () => {
  const manifest = loadManifest();
  assert.equal(manifest.host_permissions.includes("http://192.168.0.0/16"), false);
  assert.equal(manifest.host_permissions.includes("<all_urls>"), true);
});

test("extension declares tab access for browser context", () => {
  const manifest = loadManifest();
  assert.equal(manifest.permissions.includes("tabs"), true);
});

test("extension declares context menu access for page summary shortcut", () => {
  const manifest = loadManifest();
  const backgroundSource = readFileSync(new URL("../Resources/background.js", import.meta.url), "utf8");
  const contentSource = loadContentScript();

  assert.equal(manifest.permissions.includes("contextMenus"), true);
  assert.match(backgroundSource, /id:\s*summarizePageContextMenuId/);
  assert.match(backgroundSource, /title:\s*t\("summarizePageContextMenu"\)/);
  assert.match(backgroundSource, /contexts:\s*\["page"\]/);
  assert.match(contentSource, /sloppy\.page\.summarize/);
  assert.match(contentSource, /await summarizePage\(panel\)/);
});

test("extension does not request persistent microphone permission in manifest", () => {
  const manifest = loadManifest();
  assert.equal((manifest.permissions || []).includes("microphone"), false);
});

test("logo is web accessible for injected sidebar images", () => {
  const manifest = loadManifest();
  const resources = manifest.web_accessible_resources || [];
  assert.equal(
    resources.some((entry) => entry.resources?.includes("so_logo.svg") && entry.matches?.includes("<all_urls>")),
    true
  );
});

test("SF-style icon assets are web accessible for mask-based controls", () => {
  const manifest = loadManifest();
  const resources = manifest.web_accessible_resources || [];

  assert.equal(
    resources.some((entry) => entry.resources?.includes("*.svg") && entry.matches?.includes("<all_urls>")),
    true
  );
});

test("fullscreen chat page is packaged as an extension resource", () => {
  const manifest = loadManifest();
  const resources = manifest.web_accessible_resources || [];
  assert.equal(
    resources.some((entry) => entry.resources?.includes("chat.html") && entry.resources?.includes("chatPage.js")),
    true
  );
});

test("fullscreen chat page loads localization before content script", () => {
  const html = loadChatHTML();
  const i18nIndex = html.indexOf('src="i18n.js"');
  const contentScriptIndex = html.indexOf('src="contentScript.js"');

  assert.notEqual(i18nIndex, -1);
  assert.notEqual(contentScriptIndex, -1);
  assert.ok(i18nIndex < contentScriptIndex);
});

test("fullscreen chat files are copied into every Safari web extension bundle", () => {
  const project = loadXcodeProject();
  const chatHTMLCopies = project.match(/\/\* chat\.html in Resources \*\/,/g) || [];
  const chatPageCopies = project.match(/\/\* chatPage\.js in Resources \*\/,/g) || [];

  assert.equal(chatHTMLCopies.length, 3);
  assert.equal(chatPageCopies.length, 3);
});

test("SF-style icon assets are copied into every Safari web extension bundle", () => {
  const project = loadXcodeProject();
  const iconFolderCopies = project.match(/\/\* icons in Resources \*\/,/g) || [];
  const iconFiles = readdirSync(new URL("../Resources/icons", import.meta.url)).filter((file) => file.endsWith(".svg"));

  if (iconFolderCopies.length > 0) {
    assert.equal(iconFolderCopies.length, 3);
    return;
  }

  for (const iconFile of iconFiles) {
    const escapedIconFile = iconFile.replaceAll(".", "\\.");
    const iconCopies = project.match(new RegExp(`/\\* ${escapedIconFile} in Resources \\*/,`, "g")) || [];
    assert.equal(iconCopies.length, 3, `${iconFile} should be copied into every Safari web extension bundle`);
  }
});

test("localization runtime is packaged with every Safari web extension bundle", () => {
  const manifest = loadManifest();
  const project = loadXcodeProject();
  const i18nCopies = project.match(/\/\* i18n\.js in Resources \*\/,/g) || [];

  assert.deepEqual(manifest.content_scripts?.[0]?.js, ["i18n.js", "contentScript.js"]);
  assert.equal(i18nCopies.length, 3);
});

test("toolbar action uses the green Sloppy logo", () => {
  const manifest = loadManifest();
  assert.equal(manifest.action?.default_icon?.["128"], "so_logo.svg");
});

test("floating button is not gated by mobile viewport size", () => {
  const source = loadContentScript();
  const renderFloatingButton = source.match(/function renderFloatingButton\(\) \{[\s\S]*?\n\}/)?.[0] || "";

  assert.match(source, /<span>Show floating button<\/span>/);
  assert.doesNotMatch(renderFloatingButton, /isMobileViewport/);
});

test("mobile form controls use 16px text to avoid iOS Safari focus zoom", () => {
  const css = loadPanelCSS();
  assert.match(css, /@media\s*\(max-width:\s*520px\)[\s\S]*#sloppy-safari-extension-panel textarea[\s\S]*font-size:\s*16px/);
  assert.match(css, /@media\s*\(max-width:\s*520px\)[\s\S]*\.sloppy-selection-popover input[\s\S]*font-size:\s*16px/);
});

test("mobile selection menu can render as a bottom sheet", () => {
  const css = loadPanelCSS();

  assert.match(css, /#sloppy-selection-menu\.is-mobile-sheet\s*\{[\s\S]*align-items:\s*end/);
  assert.match(css, /#sloppy-selection-menu\.is-mobile-sheet \.sloppy-selection-bubble\s*\{[\s\S]*display:\s*none/);
  assert.match(css, /#sloppy-selection-menu\.is-mobile-sheet \.sloppy-selection-popover\s*\{[\s\S]*position:\s*relative/);
});

test("selection bubble scales smoothly on hover", () => {
  const css = loadPanelCSS();
  assert.match(css, /\.sloppy-selection-bubble\s*\{[\s\S]*transition:\s*transform 160ms/);
  assert.match(css, /\.sloppy-selection-bubble:hover[\s\S]*transform:\s*scale\(1\.12\)/);
});

test("empty assistant logo is grayscale and shimmers", () => {
  const css = loadPanelCSS();
  assert.match(css, /\.sloppy-empty-mark\s*\{[\s\S]*filter:\s*grayscale\(1\)/);
  assert.match(css, /\.sloppy-empty-mark\s*\{[\s\S]*animation:\s*sloppy-empty-mark-shimmer/);
  assert.match(css, /@keyframes sloppy-empty-mark-shimmer/);
});

test("streaming assistant messages show a compact thinking label", () => {
  const css = loadPanelCSS();
  assert.match(css, /\.sloppy-thinking\s*\{[\s\S]*display:\s*inline-flex;/);
  assert.match(css, /\.sloppy-thinking span\s*\{[\s\S]*font-weight:\s*650;/);
});

test("search ask button uses the StarButton capsule animation", () => {
  const css = loadPanelCSS();
  assert.match(css, /#sloppy-search-ask-button\s*\{[\s\S]*isolation:\s*isolate;/);
  assert.match(css, /#sloppy-search-ask-button\s*\{[\s\S]*overflow:\s*hidden;/);
  assert.match(css, /#sloppy-search-ask-button\s*\{[\s\S]*transition:\s*[\s\S]*transform 180ms/);
  assert.match(css, /#sloppy-search-ask-button \.sloppy-star-button-light\s*\{[\s\S]*offset-path:\s*var\(--sloppy-star-path\)/);
  assert.match(css, /#sloppy-search-ask-button \.sloppy-star-button-light\s*\{[\s\S]*animation:\s*sloppy-star-btn/);
  assert.match(css, /#sloppy-search-ask-button \.sloppy-star-button-background\s*\{[\s\S]*border:\s*2px solid/);
  assert.match(css, /#sloppy-search-ask-button \.sloppy-star-button-stars\s*\{[\s\S]*height:\s*100%/);
  assert.match(css, /#sloppy-search-ask-button:hover,\n#sloppy-search-ask-button:focus-visible\s*\{[\s\S]*transform:\s*scale\(1\.06\);/);
  assert.match(css, /@keyframes sloppy-star-btn\s*\{[\s\S]*offset-distance:\s*100%/);
});

test("command palette recent sessions scroll independently below the floating input", () => {
  const css = loadPanelCSS();

  assert.match(css, /#sloppy-command-palette,\n#sloppy-command-palette \*\s*\{[\s\S]*box-sizing:\s*border-box;/);
  assert.match(css, /\.sloppy-command-palette-shell\s*\{[\s\S]*display:\s*grid;[\s\S]*grid-template-rows:\s*auto minmax\(0, 1fr\);[\s\S]*min-height:\s*0;/);
  assert.match(css, /\.sloppy-command-palette-sessions\s*\{[\s\S]*min-height:\s*0;[\s\S]*max-height:\s*100%;/);
  assert.match(css, /\.sloppy-command-palette-sessions\s*\{[\s\S]*overflow-y:\s*auto;/);
  assert.match(css, /\.sloppy-command-palette-box > span\s*\{[\s\S]*display:\s*inline-grid;/);
  assert.doesNotMatch(css, /#sloppy-command-palette span\s*\{/);
});

test("sidebar shell uses one neutral border for clean rounded corners", () => {
  const css = loadPanelCSS();

  assert.match(css, /\.sloppy-shell\s*\{[\s\S]*border:\s*1px solid rgba\(255, 255, 255, 0\.12\);/);
  assert.doesNotMatch(css, /border-right-color:\s*rgba\(237, 190, 70/);
  assert.doesNotMatch(css, /border-bottom-color:\s*rgba\(237, 190, 70/);
});

test("voice orb uses accent-colored free-motion layers and answering pulses", () => {
  const css = loadPanelCSS();

  assert.match(css, /\.sloppy-voice-orb\s*\{[\s\S]*--sloppy-orb-accent:\s*#b7ff00;/);
  assert.match(css, /\.sloppy-voice-orb\s*\{[\s\S]*overflow:\s*hidden;/);
  assert.match(css, /\.sloppy-voice-orb::before\s*\{[\s\S]*animation:\s*sloppy-voice-free-motion/);
  assert.match(css, /\.sloppy-voice-orb::after\s*\{[\s\S]*animation:\s*sloppy-voice-free-motion-2/);
  assert.match(css, /\.sloppy-voice-orb\[data-state="answering"\]\s*\{[\s\S]*animation:\s*sloppy-voice-answering/);
  assert.match(css, /\.sloppy-voice-orb\[data-state="answering"\]::before\s*\{[\s\S]*sloppy-voice-answering-wave/);
  assert.match(css, /@keyframes sloppy-voice-answering/);
  assert.match(css, /@keyframes sloppy-voice-answering-wave/);
});

test("composer icon buttons are compact and only the primary action keeps a filled background", () => {
  const css = loadPanelCSS();
  const source = loadContentScript();

  assert.match(css, /\.sloppy-composer \.sloppy-icon-button\s*\{[\s\S]*width:\s*30px;[\s\S]*height:\s*30px;/);
  assert.match(css, /\.sloppy-composer \.sloppy-icon-button\s*\{[\s\S]*background:\s*transparent;/);
  assert.match(css, /\.sloppy-primary-action\s*\{[\s\S]*background:\s*#e6e6e6;/);
  assert.match(source, /data-sloppy-primary-action/);
  assert.doesNotMatch(source, /class="sloppy-send"/);
  assert.doesNotMatch(source, /data-sloppy-voice aria-label="Voice mode"/);
  assert.match(css, /\.sloppy-context-icon\s*\{[\s\S]*appearance:\s*none;[\s\S]*padding:\s*0;[\s\S]*place-items:\s*center;/);
});

test("controls render symbol mask icons instead of inline svg markup", () => {
  const css = loadPanelCSS();
  const source = loadContentScript();

  assert.match(source, /data-sf-symbol/);
  assert.match(source, /const path = `\$\{symbol\}\.svg`;/);
  assert.match(source, /chrome\.runtime\.getURL\(path\)/);
  assert.doesNotMatch(source, /return `<svg/);
  assert.match(css, /\.sloppy-symbol\s*\{[\s\S]*-webkit-mask:\s*var\(--sloppy-symbol-url\)/);
  assert.match(css, /\.sloppy-icon-button \.sloppy-symbol/);
});

test("assistant markdown and code blocks stay inside the chat viewport", () => {
  const css = loadPanelCSS();

  assert.match(css, /\.sloppy-thread\s*\{[\s\S]*min-width:\s*0;[\s\S]*overflow-x:\s*hidden;/);
  assert.match(css, /\.sloppy-message\s*\{[\s\S]*min-width:\s*0;[\s\S]*max-width:\s*100%;/);
  assert.match(css, /\.sloppy-message-body\s*\{[\s\S]*min-width:\s*0;[\s\S]*box-sizing:\s*border-box;/);
  assert.match(css, /\.sloppy-markdown\s*\{[\s\S]*max-width:\s*100%;[\s\S]*overflow-wrap:\s*anywhere;/);
  assert.match(css, /\.sloppy-markdown pre,\n\.sloppy-tool pre\s*\{[\s\S]*max-width:\s*100%;[\s\S]*overflow-x:\s*hidden;/);
  assert.match(css, /\.sloppy-markdown pre code\s*\{[\s\S]*white-space:\s*pre-wrap;[\s\S]*overflow-wrap:\s*anywhere;/);
  assert.match(css, /\.sloppy-tool pre\s*\{[\s\S]*white-space:\s*pre-wrap;[\s\S]*overflow-wrap:\s*anywhere;/);
});

test("voice mode exposes a compact language picker", () => {
  const source = loadContentScript();
  const css = loadPanelCSS();

  assert.match(source, /data-sloppy-voice-settings/);
  assert.match(source, /data-sloppy-voice-language/);
  assert.match(css, /\.sloppy-voice-settings/);
  assert.match(css, /\.sloppy-voice-language/);
});

test("agent control keeps dropdown affordance while model control stays icon-only", () => {
  const css = loadPanelCSS();
  const source = loadContentScript();

  assert.match(source, /data-sloppy-model/);
  assert.match(css, /\.sloppy-brand::after\s*\{[\s\S]*border-top:\s*5px solid/);
  assert.doesNotMatch(css, /\.sloppy-model-picker::after/);
  assert.match(css, /\.sloppy-brand:hover select/);
});

test("fullscreen chat uses a flat dark canvas instead of glass or gradients", () => {
  const css = loadPanelCSS();
  const fullscreenBlock = css.match(/\.sloppy-fullscreen-chat-page,\n\.sloppy-fullscreen-chat-page body\s*\{[\s\S]*?\n\}/)?.[0] || "";
  const fullscreenShellBlock = css.match(/\.sloppy-fullscreen-chat-page #sloppy-safari-extension-panel \.sloppy-shell\s*\{[\s\S]*?\n\}/)?.[0] || "";
  const fullscreenPanelBlock = css.match(/\.sloppy-fullscreen-chat-page #sloppy-safari-extension-panel\s*\{[\s\S]*?\n\}/)?.[0] || "";

  assert.match(fullscreenBlock, /background:\s*#171717;/);
  assert.doesNotMatch(fullscreenBlock, /gradient|backdrop-filter/);
  assert.match(fullscreenPanelBlock, /top:\s*var\(--sloppy-viewport-top, 0px\);/);
  assert.match(fullscreenPanelBlock, /height:\s*var\(--sloppy-viewport-height, 100vh\);/);
  assert.match(css, /\.sloppy-fullscreen-chat-page #sloppy-safari-extension-panel \[data-sloppy-close\],\n\.sloppy-fullscreen-chat-page #sloppy-safari-extension-panel \[data-sloppy-open-fullscreen\]\s*\{[\s\S]*display:\s*none;/);
  assert.match(fullscreenShellBlock, /background:\s*#171717;/);
  assert.match(fullscreenShellBlock, /box-shadow:\s*none;/);
  assert.match(fullscreenShellBlock, /backdrop-filter:\s*none;/);
});

test("fullscreen chat loads the launched session history", () => {
  const source = loadContentScript();
  const initializeFullscreenChat = source.match(/async function initializeFullscreenChat\(\) \{[\s\S]*?\n\}/)?.[0] || "";

  assert.match(initializeFullscreenChat, /if \(launch\.sessionId\) \{[\s\S]*loadSessionSelection\(launch\.sessionId\)/);
  assert.match(source, /async function loadSessionSelection\(sessionId\)/);
});
