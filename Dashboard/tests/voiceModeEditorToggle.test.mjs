import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const dashboardRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const voiceModeEditor = readFileSync(join(dashboardRoot, "src", "features", "config", "components", "VoiceModeEditor.tsx"), "utf8");
const settingsCss = readFileSync(join(dashboardRoot, "src", "styles", "settings.css"), "utf8");
const coreApi = readFileSync(join(dashboardRoot, "src", "shared", "api", "coreApi.ts"), "utf8");

test("voice mode boolean fields use the shared dashboard switch control", () => {
  assert.match(voiceModeEditor, /className="agent-tools-switch"/);
  assert.match(voiceModeEditor, /className="agent-tools-switch-track"/);
  assert.match(
    voiceModeEditor,
    /<span className="agent-tools-switch">[\s\S]*?<input id=\{id\} type="checkbox" checked=\{checked\}[\s\S]*?<span className="agent-tools-switch-track" \/>/
  );
});

test("voice mode toggle copy styles do not target switch internals", () => {
  assert.match(settingsCss, /\.config-voice-toggle-copy\s*\{/);
  assert.doesNotMatch(settingsCss, /\.config-voice-toggle span\s*\{/);
  assert.match(settingsCss, /\.config-voice-toggle \.agent-tools-switch\s*\{/);
});

test("voice mode editor loads voice capabilities for model and voice pickers", () => {
  assert.match(coreApi, /fetchVoiceCapabilities/);
  assert.match(coreApi, /path:\s*"\/v1\/voice\/capabilities"/);
  assert.match(voiceModeEditor, /fetchVoiceCapabilities\(\)/);
  assert.match(voiceModeEditor, /Available TTS models/);
  assert.match(voiceModeEditor, /Available voices/);
});
