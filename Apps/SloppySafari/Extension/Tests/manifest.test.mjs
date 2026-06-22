import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
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

test("fullscreen chat page is packaged as an extension resource", () => {
  const manifest = loadManifest();
  const resources = manifest.web_accessible_resources || [];
  assert.equal(
    resources.some((entry) => entry.resources?.includes("chat.html") && entry.resources?.includes("chatPage.js")),
    true
  );
});

test("fullscreen chat files are copied into every Safari web extension bundle", () => {
  const project = loadXcodeProject();
  const chatHTMLCopies = project.match(/\/\* chat\.html in Resources \*\/,/g) || [];
  const chatPageCopies = project.match(/\/\* chatPage\.js in Resources \*\/,/g) || [];

  assert.equal(chatHTMLCopies.length, 3);
  assert.equal(chatPageCopies.length, 3);
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

test("streaming assistant messages show a small thinking animation", () => {
  const css = loadPanelCSS();
  assert.match(css, /\.sloppy-thinking\s*\{[\s\S]*display:\s*inline-flex;/);
  assert.match(css, /\.sloppy-thinking span\s*\{[\s\S]*animation:\s*sloppy-thinking-dot/);
  assert.match(css, /@keyframes sloppy-thinking-dot/);
});

test("search ask button keeps Siri-like waves contained inside the capsule", () => {
  const css = loadPanelCSS();
  assert.match(css, /#sloppy-search-ask-button\s*\{[\s\S]*Canvas[\s\S]*CanvasText/);
  assert.match(css, /#sloppy-search-ask-button\s*\{[\s\S]*isolation:\s*isolate;/);
  assert.match(css, /#sloppy-search-ask-button\s*\{[\s\S]*overflow:\s*hidden;/);
  assert.match(css, /#sloppy-search-ask-button\s*\{[\s\S]*transition:\s*[\s\S]*transform 180ms/);
  assert.match(css, /#sloppy-search-ask-button::before\s*\{[\s\S]*radial-gradient\(ellipse at 18% 32%/);
  assert.match(css, /#sloppy-search-ask-button::before\s*\{[\s\S]*animation:\s*sloppy-search-contained-wave-a/);
  assert.match(css, /#sloppy-search-ask-button::after\s*\{[\s\S]*radial-gradient\(ellipse at 42% 58%/);
  assert.match(css, /#sloppy-search-ask-button::after\s*\{[\s\S]*animation:\s*sloppy-search-contained-wave-b/);
  assert.match(css, /#sloppy-search-ask-button:hover,\n#sloppy-search-ask-button:focus-visible\s*\{[\s\S]*transform:\s*scale\(1\.06\);/);
  assert.match(css, /@media\s*\(prefers-color-scheme:\s*dark\)[\s\S]*#sloppy-search-ask-button/);
  assert.match(css, /@keyframes sloppy-search-contained-wave-a/);
  assert.match(css, /@keyframes sloppy-search-contained-wave-b/);
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

test("square icon buttons reset native button padding for centered icons", () => {
  const css = loadPanelCSS();
  assert.match(css, /\.sloppy-icon-button,\n\.sloppy-send\s*\{[\s\S]*appearance:\s*none;[\s\S]*padding:\s*0;[\s\S]*place-items:\s*center;/);
  assert.match(css, /\.sloppy-context-icon\s*\{[\s\S]*appearance:\s*none;[\s\S]*padding:\s*0;[\s\S]*place-items:\s*center;/);
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
