# Voice Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build hybrid voice mode for Dashboard and Safari Extension, using OpenAI audio when configured and local browser speech APIs otherwise.

**Architecture:** Store voice preferences in `CoreConfig.voiceMode`, expose sanitized effective voice configuration from Core, and keep browser clients away from OpenAI secrets. SafariExtension owns the first usable voice surface and sends final transcript text through the existing browser context message flow; OpenAI transcription and TTS are proxied by Core.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftPM, React 19, TypeScript, Vite, Safari Web Extension JavaScript, Node test runner.

## Global Constraints

- Run from repo root unless a task says otherwise.
- Use Swift Testing macros: `@Test`, `#expect`.
- Dashboard code uses 2-space indentation, semicolons, and double quotes.
- Dashboard dropdown/select UI must use the custom `.actor-team-search` dropdown pattern, not native `<select>`.
- Do not classify agent state or control flow by matching assistant text phrases.
- Browser code must not receive raw OpenAI API keys.
- First implementation uses bounded transcription and TTS, not Realtime WebRTC.
- Reuse existing browser context message flow for sending voice transcripts to agents.
- Keep changes small and commit after each task.

---

## File Structure

- `Sources/sloppy/CoreConfig.swift`: add `CoreConfig.VoiceMode` nested config, coding, defaults, and round-trip support.
- `Sources/Protocols/VoiceModeModels.swift`: add sanitized API request/response DTOs for voice config, transcription, and speech.
- `Sources/sloppy/CoreService+VoiceMode.swift`: implement effective config and OpenAI availability/error handling.
- `Sources/sloppy/Gateway/Routers/SystemAPIRouter.swift`: register `/v1/voice/config`, `/v1/voice/transcriptions`, and `/v1/voice/speech`.
- `Tests/sloppyTests/CoreConfigTests.swift`: cover config defaults and round-trips.
- `Tests/ProtocolsTests/VoiceModeModelsTests.swift`: cover DTO round-trips and defaults.
- `Tests/sloppyTests/CoreRouterTests.swift`: cover voice config route and configuration errors.
- `Dashboard/src/features/config/configModel.ts`: add `voiceMode` defaults and normalization.
- `Dashboard/src/features/config/components/VoiceModeEditor.tsx`: add the settings editor.
- `Dashboard/src/features/config/ConfigView.tsx`: render the Voice Mode settings section.
- `Dashboard/src/styles/settings.css`: style the voice settings controls using existing settings patterns.
- `Apps/SafariExtension/Extension/Resources/panel.js`: add pure helpers for voice config normalization, local speech support checks, and voice prompt submission.
- `Apps/SafariExtension/Extension/Resources/contentScript.js`: add microphone UI and local voice state machine.
- `Apps/SafariExtension/Extension/Resources/background.js`: add Core proxy message handlers for voice config and OpenAI audio calls.
- `Apps/SafariExtension/Extension/Resources/panel.css`: style the voice mode surface.
- `Apps/SafariExtension/Extension/Tests/panelPayload.test.mjs`: add voice helper and transcript submission tests.
- `Apps/SafariExtension/Extension/Tests/manifest.test.mjs`: verify microphone permission posture.

---

### Task 1: Runtime Config And Protocol Models

**Files:**
- Modify: `Sources/sloppy/CoreConfig.swift`
- Create: `Sources/Protocols/VoiceModeModels.swift`
- Modify: `Package.swift`
- Modify: `Tests/sloppyTests/CoreConfigTests.swift`
- Create: `Tests/ProtocolsTests/VoiceModeModelsTests.swift`

**Interfaces:**
- Produces: `CoreConfig.VoiceMode`, `CoreConfig.VoiceMode.Provider`, `CoreConfig.VoiceMode.Input`, `CoreConfig.VoiceMode.OpenAI`, `CoreConfig.VoiceMode.Local`.
- Produces: `VoiceModeConfigResponse`, `VoiceModeTranscriptionRequest`, `VoiceModeTranscriptionResponse`, `VoiceModeSpeechRequest`, `VoiceModeSpeechResponse`.
- Later tasks consume `CoreConfig.voiceMode` and these DTOs.

- [ ] **Step 1: Write failing CoreConfig tests**

Append to `Tests/sloppyTests/CoreConfigTests.swift`:

```swift
@Test
func missingVoiceModeFallsBackToDefaults() throws {
    let json =
        """
        {
          "listen": { "host": "0.0.0.0", "port": 25101 },
          "auth": { "token": "dev-token" },
          "models": [],
          "memory": { "backend": "sqlite-local-vectors" },
          "nodes": ["local"],
          "gateways": [],
          "plugins": [],
          "sqlitePath": "core.sqlite"
        }
        """

    let decoded = try JSONDecoder().decode(CoreConfig.self, from: Data(json.utf8))

    #expect(decoded.voiceMode.enabled == false)
    #expect(decoded.voiceMode.provider == .auto)
    #expect(decoded.voiceMode.input.mode == .pushToTalk)
    #expect(decoded.voiceMode.input.language == "auto")
    #expect(decoded.voiceMode.input.previewBeforeSend == true)
    #expect(decoded.voiceMode.openAI.enabled == false)
    #expect(decoded.voiceMode.openAI.transcriptionModel == "gpt-4o-mini-transcribe")
    #expect(decoded.voiceMode.openAI.ttsModel == "gpt-4o-mini-tts")
    #expect(decoded.voiceMode.openAI.voice == "coral")
    #expect(decoded.voiceMode.local.enabled == true)
    #expect(decoded.voiceMode.local.rate == 1)
    #expect(decoded.voiceMode.local.pitch == 1)
}

@Test
func voiceModeConfigRoundTrips() throws {
    var config = CoreConfig.default
    config.voiceMode = .init(
        enabled: true,
        provider: .openAI,
        input: .init(mode: .autoSubmit, language: "ru-RU", previewBeforeSend: false),
        openAI: .init(
            enabled: true,
            transcriptionModel: "gpt-4o-transcribe",
            ttsModel: "gpt-4o-mini-tts",
            voice: "marin",
            instructions: "Speak calmly."
        ),
        local: .init(enabled: true, voiceName: "Milena", rate: 1.1, pitch: 0.9)
    )

    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(CoreConfig.self, from: data)

    #expect(decoded.voiceMode.enabled == true)
    #expect(decoded.voiceMode.provider == .openAI)
    #expect(decoded.voiceMode.input.mode == .autoSubmit)
    #expect(decoded.voiceMode.input.language == "ru-RU")
    #expect(decoded.voiceMode.input.previewBeforeSend == false)
    #expect(decoded.voiceMode.openAI.enabled == true)
    #expect(decoded.voiceMode.openAI.transcriptionModel == "gpt-4o-transcribe")
    #expect(decoded.voiceMode.openAI.voice == "marin")
    #expect(decoded.voiceMode.local.voiceName == "Milena")
    #expect(decoded.voiceMode.local.rate == 1.1)
    #expect(decoded.voiceMode.local.pitch == 0.9)
}
```

- [ ] **Step 2: Write failing Protocols tests**

Create `Tests/ProtocolsTests/VoiceModeModelsTests.swift`:

```swift
import Foundation
import Testing
@testable import Protocols

@Test
func voiceModeConfigResponseRoundTripsWithoutSecrets() throws {
    let response = VoiceModeConfigResponse(
        enabled: true,
        configuredProvider: "auto",
        effectiveProvider: "openai",
        openAIConfigured: true,
        localAvailable: true,
        input: .init(mode: "push_to_talk", language: "auto", previewBeforeSend: true),
        openAI: .init(
            enabled: true,
            transcriptionModel: "gpt-4o-mini-transcribe",
            ttsModel: "gpt-4o-mini-tts",
            voice: "coral",
            instructions: "Speak warmly."
        ),
        local: .init(enabled: true, voiceName: "", rate: 1, pitch: 1)
    )

    let data = try JSONEncoder().encode(response)
    let json = String(decoding: data, as: UTF8.self)
    #expect(!json.localizedCaseInsensitiveContains("apiKey"))
    #expect(!json.localizedCaseInsensitiveContains("authorization"))

    let decoded = try JSONDecoder().decode(VoiceModeConfigResponse.self, from: data)
    #expect(decoded.effectiveProvider == "openai")
    #expect(decoded.openAI.voice == "coral")
}

@Test
func voiceModeAudioRequestsRoundTrip() throws {
    let transcription = VoiceModeTranscriptionRequest(
        audioBase64: "d2F2",
        mimeType: "audio/webm",
        language: "ru-RU",
        prompt: "Sloppy project vocabulary"
    )
    let speech = VoiceModeSpeechRequest(text: "Привет", voice: "marin", instructions: "Short reply")

    let transcriptionDecoded = try JSONDecoder().decode(
        VoiceModeTranscriptionRequest.self,
        from: JSONEncoder().encode(transcription)
    )
    let speechDecoded = try JSONDecoder().decode(
        VoiceModeSpeechRequest.self,
        from: JSONEncoder().encode(speech)
    )

    #expect(transcriptionDecoded.mimeType == "audio/webm")
    #expect(transcriptionDecoded.language == "ru-RU")
    #expect(speechDecoded.text == "Привет")
    #expect(speechDecoded.voice == "marin")
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run:

```bash
swift test --filter voiceMode
```

Expected: FAIL because `CoreConfig.voiceMode` and `VoiceMode*` models do not exist.

- [ ] **Step 4: Add Protocol DTOs**

Create `Sources/Protocols/VoiceModeModels.swift`:

```swift
import Foundation

public struct VoiceModeConfigResponse: Codable, Sendable, Equatable {
    public struct Input: Codable, Sendable, Equatable {
        public var mode: String
        public var language: String
        public var previewBeforeSend: Bool

        public init(mode: String, language: String, previewBeforeSend: Bool) {
            self.mode = mode
            self.language = language
            self.previewBeforeSend = previewBeforeSend
        }
    }

    public struct OpenAI: Codable, Sendable, Equatable {
        public var enabled: Bool
        public var transcriptionModel: String
        public var ttsModel: String
        public var voice: String
        public var instructions: String

        public init(enabled: Bool, transcriptionModel: String, ttsModel: String, voice: String, instructions: String) {
            self.enabled = enabled
            self.transcriptionModel = transcriptionModel
            self.ttsModel = ttsModel
            self.voice = voice
            self.instructions = instructions
        }
    }

    public struct Local: Codable, Sendable, Equatable {
        public var enabled: Bool
        public var voiceName: String
        public var rate: Double
        public var pitch: Double

        public init(enabled: Bool, voiceName: String, rate: Double, pitch: Double) {
            self.enabled = enabled
            self.voiceName = voiceName
            self.rate = rate
            self.pitch = pitch
        }
    }

    public var enabled: Bool
    public var configuredProvider: String
    public var effectiveProvider: String
    public var openAIConfigured: Bool
    public var localAvailable: Bool
    public var input: Input
    public var openAI: OpenAI
    public var local: Local

    public init(
        enabled: Bool,
        configuredProvider: String,
        effectiveProvider: String,
        openAIConfigured: Bool,
        localAvailable: Bool,
        input: Input,
        openAI: OpenAI,
        local: Local
    ) {
        self.enabled = enabled
        self.configuredProvider = configuredProvider
        self.effectiveProvider = effectiveProvider
        self.openAIConfigured = openAIConfigured
        self.localAvailable = localAvailable
        self.input = input
        self.openAI = openAI
        self.local = local
    }
}

public struct VoiceModeTranscriptionRequest: Codable, Sendable, Equatable {
    public var audioBase64: String
    public var mimeType: String
    public var language: String?
    public var prompt: String?

    public init(audioBase64: String, mimeType: String, language: String? = nil, prompt: String? = nil) {
        self.audioBase64 = audioBase64
        self.mimeType = mimeType
        self.language = language
        self.prompt = prompt
    }
}

public struct VoiceModeTranscriptionResponse: Codable, Sendable, Equatable {
    public var text: String
    public var provider: String
    public var model: String

    public init(text: String, provider: String, model: String) {
        self.text = text
        self.provider = provider
        self.model = model
    }
}

public struct VoiceModeSpeechRequest: Codable, Sendable, Equatable {
    public var text: String
    public var voice: String?
    public var instructions: String?

    public init(text: String, voice: String? = nil, instructions: String? = nil) {
        self.text = text
        self.voice = voice
        self.instructions = instructions
    }
}

public struct VoiceModeSpeechResponse: Codable, Sendable, Equatable {
    public var audioBase64: String
    public var mimeType: String
    public var provider: String
    public var model: String
    public var voice: String

    public init(audioBase64: String, mimeType: String, provider: String, model: String, voice: String) {
        self.audioBase64 = audioBase64
        self.mimeType = mimeType
        self.provider = provider
        self.model = model
        self.voice = voice
    }
}
```

- [ ] **Step 5: Add CoreConfig voice mode**

In `Sources/sloppy/CoreConfig.swift`, add this nested type near other nested config structs:

```swift
    public struct VoiceMode: Codable, Sendable, Equatable {
        public enum Provider: String, Codable, Sendable {
            case auto
            case openAI = "openai"
            case local
        }

        public enum InputMode: String, Codable, Sendable {
            case pushToTalk = "push_to_talk"
            case autoSubmit = "auto_submit"
        }

        public struct Input: Codable, Sendable, Equatable {
            public var mode: InputMode
            public var language: String
            public var previewBeforeSend: Bool

            public init(mode: InputMode = .pushToTalk, language: String = "auto", previewBeforeSend: Bool = true) {
                self.mode = mode
                self.language = language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "auto" : language
                self.previewBeforeSend = previewBeforeSend
            }
        }

        public struct OpenAI: Codable, Sendable, Equatable {
            public var enabled: Bool
            public var transcriptionModel: String
            public var ttsModel: String
            public var voice: String
            public var instructions: String

            public init(
                enabled: Bool = false,
                transcriptionModel: String = "gpt-4o-mini-transcribe",
                ttsModel: String = "gpt-4o-mini-tts",
                voice: String = "coral",
                instructions: String = ""
            ) {
                self.enabled = enabled
                self.transcriptionModel = transcriptionModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "gpt-4o-mini-transcribe" : transcriptionModel
                self.ttsModel = ttsModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "gpt-4o-mini-tts" : ttsModel
                self.voice = voice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "coral" : voice
                self.instructions = instructions
            }
        }

        public struct Local: Codable, Sendable, Equatable {
            public var enabled: Bool
            public var voiceName: String
            public var rate: Double
            public var pitch: Double

            public init(enabled: Bool = true, voiceName: String = "", rate: Double = 1, pitch: Double = 1) {
                self.enabled = enabled
                self.voiceName = voiceName
                self.rate = min(max(rate, 0.5), 2)
                self.pitch = min(max(pitch, 0), 2)
            }
        }

        public var enabled: Bool
        public var provider: Provider
        public var input: Input
        public var openAI: OpenAI
        public var local: Local

        public init(
            enabled: Bool = false,
            provider: Provider = .auto,
            input: Input = Input(),
            openAI: OpenAI = OpenAI(),
            local: Local = Local()
        ) {
            self.enabled = enabled
            self.provider = provider
            self.input = input
            self.openAI = openAI
            self.local = local
        }
    }
```

Then add `public var voiceMode: VoiceMode`, add `voiceMode: VoiceMode = VoiceMode()` to the initializer, assign `self.voiceMode = voiceMode`, pass `voiceMode: .init()` in `.default`, add `case voiceMode` to `CodingKeys`, decode with:

```swift
        voiceMode = try container.decodeIfPresent(VoiceMode.self, forKey: .voiceMode) ?? .init()
```

and encode with:

```swift
        try container.encode(voiceMode, forKey: .voiceMode)
```

- [ ] **Step 6: Run focused tests**

Run:

```bash
swift test --filter voiceMode
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/sloppy/CoreConfig.swift Sources/Protocols/VoiceModeModels.swift Tests/sloppyTests/CoreConfigTests.swift Tests/ProtocolsTests/VoiceModeModelsTests.swift Package.swift
git commit -m "Add voice mode runtime config"
```

---

### Task 2: Dashboard Voice Mode Settings

**Files:**
- Modify: `Dashboard/src/features/config/configModel.ts`
- Create: `Dashboard/src/features/config/components/VoiceModeEditor.tsx`
- Modify: `Dashboard/src/features/config/ConfigView.tsx`
- Modify: `Dashboard/src/styles/settings.css`

**Interfaces:**
- Consumes: `voiceMode` JSON shape from Task 1.
- Produces: normalized `draftConfig.voiceMode`.
- Produces: `VoiceModeEditor({ voiceMode, onUpdate })`.

- [ ] **Step 1: Add config normalization tests by using typecheck as the failing gate**

Before implementation, run:

```bash
cd Dashboard && npm run typecheck
```

Expected: PASS before changes. After adding the import/render without the component in Step 2, the same command should fail until the component exists.

- [ ] **Step 2: Wire the new settings section**

In `Dashboard/src/features/config/configModel.ts`, add to `SETTINGS_ITEMS` after `browser`:

```ts
  {
    id: "voice-mode",
    title: "Voice Mode",
    icon: "mic",
    searchTerms: ["voice", "speech", "transcription", "tts", "openai", "microphone", "audio"]
  },
```

Add `voiceMode` defaults to `EMPTY_CONFIG`:

```ts
  voiceMode: {
    enabled: false,
    provider: "auto",
    input: {
      mode: "push_to_talk",
      language: "auto",
      previewBeforeSend: true
    },
    openAI: {
      enabled: false,
      transcriptionModel: "gpt-4o-mini-transcribe",
      ttsModel: "gpt-4o-mini-tts",
      voice: "coral",
      instructions: ""
    },
    local: {
      enabled: true,
      voiceName: "",
      rate: 1,
      pitch: 1
    }
  },
```

Add helper functions near other normalizers:

```ts
function normalizeVoiceProvider(value) {
  const provider = String(value || "auto").trim().toLowerCase();
  return provider === "openai" || provider === "local" ? provider : "auto";
}

function normalizeVoiceInputMode(value) {
  const mode = String(value || "push_to_talk").trim().toLowerCase();
  return mode === "auto_submit" ? "auto_submit" : "push_to_talk";
}

function normalizeNumberRange(value, fallback, min, max) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return fallback;
  }
  return Math.min(Math.max(parsed, min), max);
}

export function normalizeVoiceMode(value) {
  return {
    enabled: Boolean(value?.enabled),
    provider: normalizeVoiceProvider(value?.provider),
    input: {
      mode: normalizeVoiceInputMode(value?.input?.mode),
      language: String(value?.input?.language || "auto").trim() || "auto",
      previewBeforeSend: value?.input?.previewBeforeSend !== false
    },
    openAI: {
      enabled: Boolean(value?.openAI?.enabled),
      transcriptionModel: String(value?.openAI?.transcriptionModel || "gpt-4o-mini-transcribe").trim() || "gpt-4o-mini-transcribe",
      ttsModel: String(value?.openAI?.ttsModel || "gpt-4o-mini-tts").trim() || "gpt-4o-mini-tts",
      voice: String(value?.openAI?.voice || "coral").trim() || "coral",
      instructions: String(value?.openAI?.instructions || "")
    },
    local: {
      enabled: value?.local?.enabled !== false,
      voiceName: String(value?.local?.voiceName || ""),
      rate: normalizeNumberRange(value?.local?.rate, 1, 0.5, 2),
      pitch: normalizeNumberRange(value?.local?.pitch, 1, 0, 2)
    }
  };
}
```

Inside `normalizeConfig(config)`, add:

```ts
  normalized.voiceMode = normalizeVoiceMode(config?.voiceMode);
```

- [ ] **Step 3: Create VoiceModeEditor**

Create `Dashboard/src/features/config/components/VoiceModeEditor.tsx`:

```tsx
import React from "react";

const OPENAI_VOICES = ["alloy", "ash", "ballad", "coral", "echo", "fable", "marin", "nova", "onyx", "sage", "shimmer", "verse"];

export function VoiceModeEditor({ voiceMode, onUpdate }) {
  const provider = voiceMode?.provider || "auto";
  const input = voiceMode?.input || {};
  const openAI = voiceMode?.openAI || {};
  const local = voiceMode?.local || {};

  function update(patch) {
    onUpdate?.({ ...voiceMode, ...patch });
  }

  function updateInput(patch) {
    update({ input: { ...input, ...patch } });
  }

  function updateOpenAI(patch) {
    update({ openAI: { ...openAI, ...patch } });
  }

  function updateLocal(patch) {
    update({ local: { ...local, ...patch } });
  }

  return (
    <div className="entry-editor-layout config-voice-layout">
      <section className="entry-editor-card config-voice-card">
        <div className="entry-editor-head">
          <div>
            <span className="entry-editor-kicker">Voice Mode</span>
            <h3>Voice conversation</h3>
          </div>
          <label className="config-field-toggle">
            <input
              type="checkbox"
              checked={Boolean(voiceMode?.enabled)}
              onChange={(event) => update({ enabled: event.target.checked })}
            />
            <span>Enabled</span>
          </label>
        </div>

        <section className="entry-editor-block">
          <h4>Provider</h4>
          <div className="provider-auth-mode-segmented config-segmented" role="tablist" aria-label="Voice provider">
            {[
              ["auto", "Auto"],
              ["openai", "OpenAI"],
              ["local", "Local"]
            ].map(([value, label]) => (
              <button
                key={value}
                type="button"
                className={provider === value ? "active" : ""}
                onClick={() => update({ provider: value })}
              >
                {label}
              </button>
            ))}
          </div>
          <span className="entry-form-hint">
            Auto uses OpenAI when voice credentials are configured, otherwise local browser speech.
          </span>
        </section>

        <section className="entry-editor-block config-voice-grid">
          <label>
            Input mode
            <div className="provider-auth-mode-segmented config-segmented" role="tablist" aria-label="Voice input mode">
              <button
                type="button"
                className={(input.mode || "push_to_talk") === "push_to_talk" ? "active" : ""}
                onClick={() => updateInput({ mode: "push_to_talk" })}
              >
                Push to talk
              </button>
              <button
                type="button"
                className={input.mode === "auto_submit" ? "active" : ""}
                onClick={() => updateInput({ mode: "auto_submit" })}
              >
                Auto submit
              </button>
            </div>
          </label>
          <label>
            Language
            <input value={input.language || "auto"} onChange={(event) => updateInput({ language: event.target.value })} />
          </label>
          <label className="config-field-toggle">
            <input
              type="checkbox"
              checked={input.previewBeforeSend !== false}
              onChange={(event) => updateInput({ previewBeforeSend: event.target.checked })}
            />
            <span>Preview before send</span>
          </label>
        </section>
      </section>

      <section className="entry-editor-card config-voice-card">
        <div className="entry-editor-head">
          <div>
            <span className="entry-editor-kicker">OpenAI</span>
            <h3>Server audio</h3>
          </div>
          <label className="config-field-toggle">
            <input
              type="checkbox"
              checked={Boolean(openAI.enabled)}
              onChange={(event) => updateOpenAI({ enabled: event.target.checked })}
            />
            <span>Use when available</span>
          </label>
        </div>
        <div className="entry-form-grid">
          <label>Transcription model<input value={openAI.transcriptionModel || ""} onChange={(event) => updateOpenAI({ transcriptionModel: event.target.value })} /></label>
          <label>TTS model<input value={openAI.ttsModel || ""} onChange={(event) => updateOpenAI({ ttsModel: event.target.value })} /></label>
          <label>
            Voice
            <div className="actor-team-search-wrap config-voice-picker">
              <input
                value={openAI.voice || "coral"}
                onChange={(event) => updateOpenAI({ voice: event.target.value })}
                list="voice-mode-openai-voices"
              />
              <datalist id="voice-mode-openai-voices">
                {OPENAI_VOICES.map((voice) => <option key={voice} value={voice} />)}
              </datalist>
            </div>
          </label>
          <label className="entry-form-wide">Instructions<textarea value={openAI.instructions || ""} onChange={(event) => updateOpenAI({ instructions: event.target.value })} /></label>
        </div>
      </section>

      <section className="entry-editor-card config-voice-card">
        <div className="entry-editor-head">
          <div>
            <span className="entry-editor-kicker">Local</span>
            <h3>Browser fallback</h3>
          </div>
          <label className="config-field-toggle">
            <input
              type="checkbox"
              checked={local.enabled !== false}
              onChange={(event) => updateLocal({ enabled: event.target.checked })}
            />
            <span>Enabled</span>
          </label>
        </div>
        <div className="entry-form-grid">
          <label>Voice name<input value={local.voiceName || ""} onChange={(event) => updateLocal({ voiceName: event.target.value })} /></label>
          <label>Rate<input type="number" min="0.5" max="2" step="0.1" value={local.rate ?? 1} onChange={(event) => updateLocal({ rate: Number(event.target.value) })} /></label>
          <label>Pitch<input type="number" min="0" max="2" step="0.1" value={local.pitch ?? 1} onChange={(event) => updateLocal({ pitch: Number(event.target.value) })} /></label>
        </div>
      </section>
    </div>
  );
}
```

- [ ] **Step 4: Render editor in ConfigView**

In `Dashboard/src/features/config/ConfigView.tsx`, import:

```ts
import { VoiceModeEditor } from "./components/VoiceModeEditor";
```

In `renderSettingsContent()`, before raw config:

```tsx
    if (selectedSettings === "voice-mode") {
      return (
        <VoiceModeEditor
          voiceMode={draftConfig.voiceMode}
          onUpdate={(nextVoiceMode) => mutateDraft((next) => {
            next.voiceMode = nextVoiceMode;
          })}
        />
      );
    }
```

- [ ] **Step 5: Add focused styles**

Append to `Dashboard/src/styles/settings.css`:

```css
.config-voice-layout {
  grid-template-columns: minmax(0, 1fr);
  gap: 16px;
}

.config-voice-card {
  min-width: 0;
}

.config-voice-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: 14px;
}

.config-voice-picker input {
  width: 100%;
}
```

- [ ] **Step 6: Verify Dashboard**

Run:

```bash
cd Dashboard && npm run typecheck && npm run build
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Dashboard/src/features/config/configModel.ts Dashboard/src/features/config/components/VoiceModeEditor.tsx Dashboard/src/features/config/ConfigView.tsx Dashboard/src/styles/settings.css
git commit -m "Add voice mode dashboard settings"
```

---

### Task 3: Core Voice Config Route

**Files:**
- Create: `Sources/sloppy/CoreService+VoiceMode.swift`
- Modify: `Sources/sloppy/Gateway/Routers/SystemAPIRouter.swift`
- Modify: `Tests/sloppyTests/CoreRouterTests.swift`

**Interfaces:**
- Consumes: `CoreConfig.voiceMode`.
- Produces: `CoreService.voiceModeConfig() async -> VoiceModeConfigResponse`.
- Produces: `GET /v1/voice/config`.

- [ ] **Step 1: Write failing route tests**

Append to `Tests/sloppyTests/CoreRouterTests.swift`:

```swift
@Test
func voiceConfigEndpointReturnsSanitizedLocalFallback() async throws {
    var config = CoreConfig.test
    config.voiceMode = .init(enabled: true, provider: .auto)
    config.models = []
    let router = CoreRouter(service: CoreService(config: config))

    let response = await router.handle(method: "GET", path: "/v1/voice/config", body: nil)

    #expect(response.status == 200)
    let payload = try JSONDecoder().decode(VoiceModeConfigResponse.self, from: response.body)
    #expect(payload.enabled == true)
    #expect(payload.configuredProvider == "auto")
    #expect(payload.effectiveProvider == "local")
    #expect(payload.openAIConfigured == false)
    #expect(payload.openAI.transcriptionModel == "gpt-4o-mini-transcribe")
    #expect(String(decoding: response.body, as: UTF8.self).contains("apiKey") == false)
}

@Test
func voiceConfigEndpointUsesOpenAIWhenConfigured() async throws {
    var config = CoreConfig.test
    config.voiceMode = .init(
        enabled: true,
        provider: .auto,
        openAI: .init(enabled: true, voice: "marin")
    )
    config.models = [
        .init(title: "openai-api", apiKey: "sk-test", apiUrl: "https://api.openai.com/v1", model: "gpt-5.4-mini")
    ]
    let router = CoreRouter(service: CoreService(config: config))

    let response = await router.handle(method: "GET", path: "/v1/voice/config", body: nil)

    #expect(response.status == 200)
    let payload = try JSONDecoder().decode(VoiceModeConfigResponse.self, from: response.body)
    #expect(payload.effectiveProvider == "openai")
    #expect(payload.openAIConfigured == true)
    #expect(payload.openAI.voice == "marin")
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter voiceConfigEndpoint
```

Expected: FAIL with route/model/service missing errors.

- [ ] **Step 3: Implement service**

Create `Sources/sloppy/CoreService+VoiceMode.swift`:

```swift
import Foundation
import Protocols

extension CoreService {
    public func voiceModeConfig() async -> VoiceModeConfigResponse {
        let config = await getConfig()
        let openAIConfigured = Self.voiceModeOpenAIConfigured(config)
        let effectiveProvider: String
        switch config.voiceMode.provider {
        case .openAI:
            effectiveProvider = openAIConfigured ? "openai" : "unavailable"
        case .local:
            effectiveProvider = "local"
        case .auto:
            effectiveProvider = openAIConfigured ? "openai" : "local"
        }

        return VoiceModeConfigResponse(
            enabled: config.voiceMode.enabled,
            configuredProvider: config.voiceMode.provider.rawValue,
            effectiveProvider: effectiveProvider,
            openAIConfigured: openAIConfigured,
            localAvailable: config.voiceMode.local.enabled,
            input: .init(
                mode: config.voiceMode.input.mode.rawValue,
                language: config.voiceMode.input.language,
                previewBeforeSend: config.voiceMode.input.previewBeforeSend
            ),
            openAI: .init(
                enabled: config.voiceMode.openAI.enabled,
                transcriptionModel: config.voiceMode.openAI.transcriptionModel,
                ttsModel: config.voiceMode.openAI.ttsModel,
                voice: config.voiceMode.openAI.voice,
                instructions: config.voiceMode.openAI.instructions
            ),
            local: .init(
                enabled: config.voiceMode.local.enabled,
                voiceName: config.voiceMode.local.voiceName,
                rate: config.voiceMode.local.rate,
                pitch: config.voiceMode.local.pitch
            )
        )
    }

    static func voiceModeOpenAIConfigured(_ config: CoreConfig) -> Bool {
        guard config.voiceMode.openAI.enabled else {
            return false
        }
        return config.models.contains { model in
            !model.disabled &&
            model.apiUrl.localizedCaseInsensitiveContains("openai.com") &&
            !model.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } || ProcessInfo.processInfo.environment["OPENAI_API_KEY"].map { !$0.isEmpty } == true
    }
}
```

- [ ] **Step 4: Register route**

In `Sources/sloppy/Gateway/Routers/SystemAPIRouter.swift`, after `/v1/config` GET:

```swift
        router.get("/v1/voice/config", metadata: RouteMetadata(summary: "Get voice mode config", description: "Returns sanitized effective voice mode configuration", tags: ["System"])) { _ in
            let response = await service.voiceModeConfig()
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
        }
```

- [ ] **Step 5: Verify**

Run:

```bash
swift test --filter voiceConfigEndpoint
swift test --filter CoreConfigTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/sloppy/CoreService+VoiceMode.swift Sources/sloppy/Gateway/Routers/SystemAPIRouter.swift Tests/sloppyTests/CoreRouterTests.swift
git commit -m "Expose sanitized voice mode config"
```

---

### Task 4: Safari Extension Local Voice Flow

**Files:**
- Modify: `Apps/SafariExtension/Extension/Resources/panel.js`
- Modify: `Apps/SafariExtension/Extension/Resources/contentScript.js`
- Modify: `Apps/SafariExtension/Extension/Resources/panel.css`
- Modify: `Apps/SafariExtension/Extension/Tests/panelPayload.test.mjs`
- Modify: `Apps/SafariExtension/Extension/Tests/manifest.test.mjs`

**Interfaces:**
- Consumes: `sloppy.voice.config.get` background message from Task 5; before Task 5 exists, local helpers should still work with defaults.
- Produces: `normalizeVoiceConfig`, `localSpeechAvailable`, `buildVoicePrompt`.
- Produces: content-script state values `idle`, `listening`, `transcribing`, `sending`, `speaking`, `error`.

- [ ] **Step 1: Write failing panel helper tests**

In `Apps/SafariExtension/Extension/Tests/panelPayload.test.mjs`, add imports:

```js
  buildVoicePrompt,
  localSpeechAvailable,
  normalizeVoiceConfig,
```

Append tests:

```js
test("normalizeVoiceConfig falls back to local mode", () => {
  const config = normalizeVoiceConfig({});
  assert.equal(config.enabled, false);
  assert.equal(config.effectiveProvider, "local");
  assert.equal(config.input.mode, "push_to_talk");
  assert.equal(config.local.enabled, true);
});

test("buildVoicePrompt trims transcript and preserves page prompt behavior", () => {
  assert.equal(buildVoicePrompt("  hello agent  "), "hello agent");
  assert.equal(buildVoicePrompt("   "), "");
});

test("localSpeechAvailable checks browser speech APIs without touching assistant text", () => {
  assert.deepEqual(localSpeechAvailable({ SpeechRecognition: function SpeechRecognition() {}, speechSynthesis: {} }), {
    recognition: true,
    synthesis: true
  });
  assert.deepEqual(localSpeechAvailable({ webkitSpeechRecognition: function SpeechRecognition() {} }), {
    recognition: true,
    synthesis: false
  });
});
```

In `Apps/SafariExtension/Extension/Tests/manifest.test.mjs`, append:

```js
test("extension does not request persistent microphone permission in manifest", () => {
  const manifest = loadManifest();
  assert.equal((manifest.permissions || []).includes("microphone"), false);
});
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
cd Apps/SafariExtension/Extension && npm test
```

Expected: FAIL because new exports do not exist.

- [ ] **Step 3: Add pure voice helpers**

In `Apps/SafariExtension/Extension/Resources/panel.js`, export:

```js
export function normalizeVoiceConfig(config = {}) {
  const provider = String(config.configuredProvider || config.provider || "auto").toLowerCase();
  const effectiveProvider = String(config.effectiveProvider || (provider === "openai" ? "unavailable" : "local")).toLowerCase();
  return {
    enabled: Boolean(config.enabled),
    configuredProvider: provider === "openai" || provider === "local" ? provider : "auto",
    effectiveProvider: effectiveProvider === "openai" ? "openai" : "local",
    openAIConfigured: Boolean(config.openAIConfigured),
    localAvailable: config.localAvailable !== false,
    input: {
      mode: config.input?.mode === "auto_submit" ? "auto_submit" : "push_to_talk",
      language: String(config.input?.language || "auto"),
      previewBeforeSend: config.input?.previewBeforeSend !== false
    },
    openAI: {
      enabled: Boolean(config.openAI?.enabled),
      transcriptionModel: String(config.openAI?.transcriptionModel || "gpt-4o-mini-transcribe"),
      ttsModel: String(config.openAI?.ttsModel || "gpt-4o-mini-tts"),
      voice: String(config.openAI?.voice || "coral"),
      instructions: String(config.openAI?.instructions || "")
    },
    local: {
      enabled: config.local?.enabled !== false,
      voiceName: String(config.local?.voiceName || ""),
      rate: Number.isFinite(Number(config.local?.rate)) ? Number(config.local.rate) : 1,
      pitch: Number.isFinite(Number(config.local?.pitch)) ? Number(config.local.pitch) : 1
    }
  };
}

export function localSpeechAvailable(windowLike = globalThis) {
  return {
    recognition: typeof windowLike.SpeechRecognition === "function" || typeof windowLike.webkitSpeechRecognition === "function",
    synthesis: Boolean(windowLike.speechSynthesis)
  };
}

export function buildVoicePrompt(transcript) {
  return String(transcript || "").trim();
}
```

- [ ] **Step 4: Add content-script UI state machine**

In `Apps/SafariExtension/Extension/Resources/contentScript.js`, extend `icon()` paths with:

```js
    mic: '<path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><path d="M12 19v3"/><path d="M8 22h8"/>',
```

Add to the composer tools in `ensurePanel()` before send:

```html
            <button class="sloppy-icon-button" type="button" data-sloppy-voice aria-label="Voice mode">${icon("mic")}</button>
```

Add a voice panel before the settings dialog:

```html
    <section class="sloppy-voice" data-sloppy-voice-panel hidden>
      <div class="sloppy-voice-orb" data-sloppy-voice-orb></div>
      <p data-sloppy-voice-status>Say something...</p>
      <div class="sloppy-voice-actions">
        <button class="sloppy-icon-button" type="button" data-sloppy-voice-cancel aria-label="Cancel">${icon("close")}</button>
        <button class="sloppy-icon-button" type="button" data-sloppy-voice-record aria-label="Record">${icon("mic")}</button>
      </div>
    </section>
```

Add `voice: { state: "idle", transcript: "", recognition: null }` to `state`.

Add functions:

```js
function setVoiceState(nextState, message = "") {
  state.voice.state = nextState;
  const panel = document.querySelector("[data-sloppy-voice-panel]");
  const status = document.querySelector("[data-sloppy-voice-status]");
  const orb = document.querySelector("[data-sloppy-voice-orb]");
  if (panel) {
    panel.hidden = nextState === "idle";
  }
  if (status) {
    status.textContent = message || (nextState === "listening" ? "Say something..." : nextState);
  }
  if (orb) {
    orb.dataset.state = nextState;
  }
}

function startLocalVoice() {
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SpeechRecognition) {
    setVoiceState("error", "Speech recognition is unavailable in this browser.");
    return;
  }
  const recognition = new SpeechRecognition();
  recognition.lang = state.voiceConfig?.input?.language === "auto" ? "" : state.voiceConfig?.input?.language || "";
  recognition.interimResults = true;
  recognition.continuous = false;
  state.voice.recognition = recognition;
  state.voice.transcript = "";
  recognition.onresult = (event) => {
    state.voice.transcript = Array.from(event.results)
      .map((result) => result[0]?.transcript || "")
      .join(" ")
      .trim();
    setVoiceState("listening", state.voice.transcript || "Say something...");
  };
  recognition.onerror = () => setVoiceState("error", "Microphone or speech recognition failed.");
  recognition.onend = () => submitVoiceTranscript();
  setVoiceState("listening", "Say something...");
  recognition.start();
}

function cancelVoice() {
  state.voice.recognition?.abort?.();
  state.voice.recognition = null;
  state.voice.transcript = "";
  setVoiceState("idle");
}

function submitVoiceTranscript() {
  const prompt = buildVoicePrompt(state.voice.transcript);
  if (!prompt) {
    setVoiceState("error", "No speech detected.");
    return;
  }
  const promptInput = document.querySelector("[data-sloppy-prompt]");
  if (promptInput) {
    promptInput.value = prompt;
  }
  setVoiceState("sending", "Sending...");
  document.querySelector("[data-sloppy-composer]")?.requestSubmit?.();
}
```

Wire the new buttons in `wirePanel(frame)`:

```js
  frame.querySelector("[data-sloppy-voice]")?.addEventListener("click", () => startLocalVoice());
  frame.querySelector("[data-sloppy-voice-record]")?.addEventListener("click", () => startLocalVoice());
  frame.querySelector("[data-sloppy-voice-cancel]")?.addEventListener("click", () => cancelVoice());
```

- [ ] **Step 5: Add CSS**

Append to `Apps/SafariExtension/Extension/Resources/panel.css`:

```css
.sloppy-voice {
  position: absolute;
  inset: 0;
  z-index: 4;
  display: grid;
  place-items: center;
  gap: 24px;
  background: rgba(18, 18, 18, 0.96);
  color: #e8e8e8;
}

.sloppy-voice[hidden] {
  display: none;
}

.sloppy-voice-orb {
  width: 190px;
  aspect-ratio: 1;
  border-radius: 50%;
  background: radial-gradient(circle, rgba(230, 230, 230, 0.95) 1px, transparent 2px);
  background-size: 12px 12px;
  opacity: 0.76;
}

.sloppy-voice-orb[data-state="listening"] {
  animation: sloppy-voice-pulse 1.3s ease-in-out infinite;
}

.sloppy-voice-actions {
  display: flex;
  gap: 18px;
}

@keyframes sloppy-voice-pulse {
  0%, 100% { transform: scale(0.96); opacity: 0.68; }
  50% { transform: scale(1.04); opacity: 0.9; }
}
```

- [ ] **Step 6: Verify**

Run:

```bash
cd Apps/SafariExtension/Extension && npm test
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Apps/SafariExtension/Extension/Resources/panel.js Apps/SafariExtension/Extension/Resources/contentScript.js Apps/SafariExtension/Extension/Resources/panel.css Apps/SafariExtension/Extension/Tests/panelPayload.test.mjs Apps/SafariExtension/Extension/Tests/manifest.test.mjs
git commit -m "Add local voice mode to Safari extension"
```

---

### Task 5: Core OpenAI Voice Endpoints

**Files:**
- Create: `Sources/sloppy/Voice/OpenAIVoiceModeClient.swift`
- Modify: `Sources/sloppy/CoreService+VoiceMode.swift`
- Modify: `Sources/sloppy/Gateway/Routers/SystemAPIRouter.swift`
- Modify: `Tests/sloppyTests/CoreRouterTests.swift`

**Interfaces:**
- Consumes: `VoiceModeTranscriptionRequest`, `VoiceModeSpeechRequest`.
- Produces: `CoreService.transcribeVoice(_:) async throws -> VoiceModeTranscriptionResponse`.
- Produces: `CoreService.synthesizeVoice(_:) async throws -> VoiceModeSpeechResponse`.
- Produces: `POST /v1/voice/transcriptions` and `POST /v1/voice/speech`.

- [ ] **Step 1: Write failing endpoint error tests**

Append to `Tests/sloppyTests/CoreRouterTests.swift`:

```swift
@Test
func voiceTranscriptionEndpointReturnsConfigErrorWithoutOpenAI() async throws {
    var config = CoreConfig.test
    config.voiceMode = .init(enabled: true, provider: .openAI, openAI: .init(enabled: true))
    config.models = []
    let router = CoreRouter(service: CoreService(config: config))
    let body = try JSONEncoder().encode(VoiceModeTranscriptionRequest(audioBase64: "d2F2", mimeType: "audio/webm"))

    let response = await router.handle(method: "POST", path: "/v1/voice/transcriptions", body: body)

    #expect(response.status == 409)
    let payload = try JSONDecoder().decode(ErrorResponse.self, from: response.body)
    #expect(payload.error == "voice_openai_not_configured")
}

@Test
func voiceSpeechEndpointReturnsBadRequestForEmptyText() async throws {
    var config = CoreConfig.test
    config.voiceMode = .init(enabled: true, provider: .openAI, openAI: .init(enabled: true))
    let router = CoreRouter(service: CoreService(config: config))
    let body = try JSONEncoder().encode(VoiceModeSpeechRequest(text: "   "))

    let response = await router.handle(method: "POST", path: "/v1/voice/speech", body: body)

    #expect(response.status == 400)
    let payload = try JSONDecoder().decode(ErrorResponse.self, from: response.body)
    #expect(payload.error == "invalid_body")
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter voiceTranscriptionEndpoint
swift test --filter voiceSpeechEndpoint
```

Expected: FAIL because routes do not exist.

- [ ] **Step 3: Add service methods and errors**

In `Sources/sloppy/CoreService+VoiceMode.swift`, add:

```swift
    public enum VoiceModeError: Error {
        case invalidPayload
        case openAINotConfigured
        case requestFailed(String)
    }

    public func transcribeVoice(_ request: VoiceModeTranscriptionRequest) async throws -> VoiceModeTranscriptionResponse {
        let config = await getConfig()
        guard Self.voiceModeOpenAIConfigured(config) else {
            throw VoiceModeError.openAINotConfigured
        }
        guard !request.audioBase64.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.mimeType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw VoiceModeError.invalidPayload
        }

        guard let apiKey = Self.voiceModeOpenAIAPIKey(config) else {
            throw VoiceModeError.openAINotConfigured
        }
        return try await OpenAIVoiceModeClient().transcribe(request: request, config: config, apiKey: apiKey)
    }

    public func synthesizeVoice(_ request: VoiceModeSpeechRequest) async throws -> VoiceModeSpeechResponse {
        let config = await getConfig()
        guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoiceModeError.invalidPayload
        }
        guard Self.voiceModeOpenAIConfigured(config) else {
            throw VoiceModeError.openAINotConfigured
        }

        guard let apiKey = Self.voiceModeOpenAIAPIKey(config) else {
            throw VoiceModeError.openAINotConfigured
        }
        return try await OpenAIVoiceModeClient().speech(request: request, config: config, apiKey: apiKey)
    }
```

- [ ] **Step 4: Add OpenAI audio client**

Create `Sources/sloppy/Voice/OpenAIVoiceModeClient.swift`:

```swift
import Foundation
import Protocols

struct OpenAIVoiceModeClient: Sendable {
    private let session: URLSession

    init(session: URLSession = SloppyURLSessionFactory.shared) {
        self.session = session
    }

    func transcribe(
        request: VoiceModeTranscriptionRequest,
        config: CoreConfig,
        apiKey: String
    ) async throws -> VoiceModeTranscriptionResponse {
        let audioData = Data(base64Encoded: request.audioBase64) ?? Data()
        guard !audioData.isEmpty else {
            throw CoreService.VoiceModeError.invalidPayload
        }

        let boundary = "sloppy-voice-\(UUID().uuidString)"
        var urlRequest = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = multipartBody(
            boundary: boundary,
            fields: [
                "model": config.voiceMode.openAI.transcriptionModel,
                "response_format": "json"
            ].merging(optionalFields(request: request)) { current, _ in current },
            fileField: "file",
            filename: filename(for: request.mimeType),
            mimeType: request.mimeType,
            data: audioData
        )

        let (data, response) = try await session.data(for: urlRequest)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(OpenAITranscriptionResponse.self, from: data)
        return VoiceModeTranscriptionResponse(
            text: decoded.text.trimmingCharacters(in: .whitespacesAndNewlines),
            provider: "openai",
            model: config.voiceMode.openAI.transcriptionModel
        )
    }

    func speech(
        request: VoiceModeSpeechRequest,
        config: CoreConfig,
        apiKey: String
    ) async throws -> VoiceModeSpeechResponse {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw CoreService.VoiceModeError.invalidPayload
        }
        let voice = request.voice?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? config.voiceMode.openAI.voice
        let instructions = request.instructions?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? config.voiceMode.openAI.instructions
        var payload: [String: String] = [
            "model": config.voiceMode.openAI.ttsModel,
            "voice": voice,
            "input": text,
            "response_format": "mp3"
        ]
        if !instructions.isEmpty {
            payload["instructions"] = instructions
        }

        var urlRequest = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: urlRequest)
        try validate(response: response, data: data)
        return VoiceModeSpeechResponse(
            audioBase64: data.base64EncodedString(),
            mimeType: "audio/mpeg",
            provider: "openai",
            model: config.voiceMode.openAI.ttsModel,
            voice: voice
        )
    }

    private func optionalFields(request: VoiceModeTranscriptionRequest) -> [String: String] {
        var fields: [String: String] = [:]
        if let language = request.language?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty, language != "auto" {
            fields["language"] = language
        }
        if let prompt = request.prompt?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
            fields["prompt"] = prompt
        }
        return fields
    }

    private func multipartBody(
        boundary: String,
        fields: [String: String],
        fileField: String,
        filename: String,
        mimeType: String,
        data: Data
    ) -> Data {
        var body = Data()
        for (name, value) in fields {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n")
        return body
    }

    private func filename(for mimeType: String) -> String {
        if mimeType.contains("wav") { return "voice.wav" }
        if mimeType.contains("mpeg") || mimeType.contains("mp3") { return "voice.mp3" }
        if mimeType.contains("mp4") { return "voice.mp4" }
        return "voice.webm"
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CoreService.VoiceModeError.requestFailed("invalid_response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(decoding: data.prefix(240), as: UTF8.self)
            throw CoreService.VoiceModeError.requestFailed("openai_http_\(http.statusCode): \(message)")
        }
    }

    private struct OpenAITranscriptionResponse: Decodable {
        let text: String
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
```

- [ ] **Step 5: Add API key resolver**

In `Sources/sloppy/CoreService+VoiceMode.swift`, add this resolver near `voiceModeOpenAIConfigured`:

```swift
    static func voiceModeOpenAIAPIKey(_ config: CoreConfig) -> String? {
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envKey.isEmpty {
            return envKey
        }
        return config.models.first { model in
            !model.disabled &&
            model.apiUrl.localizedCaseInsensitiveContains("openai.com") &&
            !model.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }?.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
```

- [ ] **Step 6: Register endpoints**

In `Sources/sloppy/Gateway/Routers/SystemAPIRouter.swift`, after `/v1/voice/config`:

```swift
        router.post("/v1/voice/transcriptions", metadata: RouteMetadata(summary: "Transcribe voice audio", description: "Transcribes bounded browser audio through configured OpenAI voice settings", tags: ["System"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: VoiceModeTranscriptionRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            do {
                let response = try await service.transcribeVoice(payload)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch CoreService.VoiceModeError.invalidPayload {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            } catch CoreService.VoiceModeError.openAINotConfigured {
                return CoreRouter.json(status: HTTPStatus.conflict, payload: ["error": "voice_openai_not_configured"])
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": "voice_transcription_failed"])
            }
        }

        router.post("/v1/voice/speech", metadata: RouteMetadata(summary: "Generate voice speech", description: "Generates spoken audio through configured OpenAI voice settings", tags: ["System"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: VoiceModeSpeechRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            do {
                let response = try await service.synthesizeVoice(payload)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch CoreService.VoiceModeError.invalidPayload {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            } catch CoreService.VoiceModeError.openAINotConfigured {
                return CoreRouter.json(status: HTTPStatus.conflict, payload: ["error": "voice_openai_not_configured"])
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": "voice_speech_failed"])
            }
        }
```

- [ ] **Step 7: Verify**

Run:

```bash
swift test --filter voiceTranscriptionEndpoint
swift test --filter voiceSpeechEndpoint
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/sloppy/Voice/OpenAIVoiceModeClient.swift Sources/sloppy/CoreService+VoiceMode.swift Sources/sloppy/Gateway/Routers/SystemAPIRouter.swift Tests/sloppyTests/CoreRouterTests.swift
git commit -m "Add voice mode API endpoints"
```

---

### Task 6: Safari Extension OpenAI Proxy Wiring

**Files:**
- Modify: `Apps/SafariExtension/Extension/Resources/panel.js`
- Modify: `Apps/SafariExtension/Extension/Resources/background.js`
- Modify: `Apps/SafariExtension/Extension/Resources/contentScript.js`
- Modify: `Apps/SafariExtension/Extension/Tests/panelPayload.test.mjs`

**Interfaces:**
- Consumes: `/v1/voice/config`, `/v1/voice/transcriptions`, `/v1/voice/speech`.
- Produces: `fetchVoiceConfig`, `transcribeVoiceAudio`, `synthesizeVoiceSpeech` helpers.
- Produces: background messages `sloppy.voice.config.get`, `sloppy.voice.transcribe`, `sloppy.voice.speech`.

- [ ] **Step 1: Write failing helper tests**

Append to `Apps/SafariExtension/Extension/Tests/panelPayload.test.mjs`:

```js
test("fetchVoiceConfig reads sanitized voice config from Core", async () => {
  const requests = [];
  const fetchImpl = async (url) => {
    requests.push(String(url));
    return Response.json({ enabled: true, effectiveProvider: "openai", openAIConfigured: true });
  };

  const config = await fetchVoiceConfig({ coreURLString: "http://127.0.0.1:25101" }, fetchImpl);

  assert.equal(config.effectiveProvider, "openai");
  assert.equal(requests[0], "http://127.0.0.1:25101/v1/voice/config");
});

test("transcribeVoiceAudio posts audio to Core", async () => {
  const fetchImpl = async (url, options) => {
    assert.equal(String(url), "http://127.0.0.1:25101/v1/voice/transcriptions");
    assert.deepEqual(JSON.parse(options.body), {
      audioBase64: "abcd",
      mimeType: "audio/webm",
      language: "auto",
      prompt: ""
    });
    return Response.json({ text: "hello", provider: "openai", model: "gpt-4o-mini-transcribe" });
  };

  const result = await transcribeVoiceAudio(
    { coreURLString: "http://127.0.0.1:25101" },
    { audioBase64: "abcd", mimeType: "audio/webm", language: "auto", prompt: "" },
    fetchImpl
  );

  assert.equal(result.text, "hello");
});
```

Add imports for `fetchVoiceConfig` and `transcribeVoiceAudio`.

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
cd Apps/SafariExtension/Extension && npm test
```

Expected: FAIL because helpers do not exist.

- [ ] **Step 3: Add panel proxy helpers**

In `Apps/SafariExtension/Extension/Resources/panel.js`, add:

```js
export async function fetchVoiceConfig(settings, fetchImpl = fetch) {
  const coreURL = normalizeCoreURL(settings.coreURLString);
  const response = await fetchImpl(`${coreURL}/v1/voice/config`, {
    headers: headersForSettings(settings)
  });
  return normalizeVoiceConfig(await parseJSONResponse(response));
}

export async function transcribeVoiceAudio(settings, payload, fetchImpl = fetch) {
  const coreURL = normalizeCoreURL(settings.coreURLString);
  const response = await fetchImpl(`${coreURL}/v1/voice/transcriptions`, {
    method: "POST",
    headers: headersForSettings(settings),
    body: JSON.stringify(payload)
  });
  return parseJSONResponse(response);
}

export async function synthesizeVoiceSpeech(settings, payload, fetchImpl = fetch) {
  const coreURL = normalizeCoreURL(settings.coreURLString);
  const response = await fetchImpl(`${coreURL}/v1/voice/speech`, {
    method: "POST",
    headers: headersForSettings(settings),
    body: JSON.stringify(payload)
  });
  return parseJSONResponse(response);
}
```

- [ ] **Step 4: Add background message handlers**

In `Apps/SafariExtension/Extension/Resources/background.js`, import the new helpers and add handlers before the browser context handler:

```js
    if (message?.type === "sloppy.voice.config.get") {
      void (async () => {
        const settings = await loadSettings();
        const config = await fetchVoiceConfig(settings);
        sendResponse({ config });
      })().catch((error) => sendResponse({ error: error.message || "Voice config unavailable." }));
      return true;
    }
    if (message?.type === "sloppy.voice.transcribe") {
      void (async () => {
        const settings = await loadSettings();
        const result = await transcribeVoiceAudio(settings, message.payload || {});
        sendResponse({ result });
      })().catch((error) => sendResponse({ error: error.message || "Voice transcription failed." }));
      return true;
    }
    if (message?.type === "sloppy.voice.speech") {
      void (async () => {
        const settings = await loadSettings();
        const result = await synthesizeVoiceSpeech(settings, message.payload || {});
        sendResponse({ result });
      })().catch((error) => sendResponse({ error: error.message || "Voice speech failed." }));
      return true;
    }
```

- [ ] **Step 5: Add content-script provider selection**

In `Apps/SafariExtension/Extension/Resources/contentScript.js`, add:

```js
async function loadVoiceConfig() {
  const response = await chrome.runtime.sendMessage({ type: "sloppy.voice.config.get" }).catch((error) => ({ error: error.message }));
  state.voiceConfig = normalizeVoiceConfig(response?.config || {});
  return state.voiceConfig;
}

function blobToBase64(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result || "").split(",")[1] || "");
    reader.onerror = () => reject(reader.error || new Error("Unable to read audio."));
    reader.readAsDataURL(blob);
  });
}

async function startOpenAIVoice(config) {
  if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder !== "function") {
    setVoiceState("error", "Microphone recording is unavailable in this browser.");
    return;
  }
  const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  const chunks = [];
  const recorder = new MediaRecorder(stream);
  recorder.ondataavailable = (event) => {
    if (event.data?.size > 0) {
      chunks.push(event.data);
    }
  };
  recorder.onstop = async () => {
    stream.getTracks().forEach((track) => track.stop());
    setVoiceState("transcribing", "Transcribing...");
    const blob = new Blob(chunks, { type: recorder.mimeType || "audio/webm" });
    const audioBase64 = await blobToBase64(blob);
    const response = await chrome.runtime.sendMessage({
      type: "sloppy.voice.transcribe",
      payload: {
        audioBase64,
        mimeType: blob.type || "audio/webm",
        language: config.input.language,
        prompt: ""
      }
    });
    if (response?.error) {
      setVoiceState("error", response.error);
      return;
    }
    state.voice.transcript = response?.result?.text || "";
    submitVoiceTranscript();
  };
  state.voice.recorder = recorder;
  setVoiceState("listening", "Say something...");
  recorder.start();
  window.setTimeout(() => {
    if (recorder.state === "recording") {
      recorder.stop();
    }
  }, 12000);
}
```

Change the voice button handler to:

```js
async function startVoice() {
  const config = await loadVoiceConfig();
  if (config.effectiveProvider === "openai") {
    await startOpenAIVoice(config);
    return;
  }
  startLocalVoice();
}
```

Wire buttons to `startVoice()` instead of `startLocalVoice()`.

- [ ] **Step 6: Verify**

Run:

```bash
cd Apps/SafariExtension/Extension && npm test
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Apps/SafariExtension/Extension/Resources/panel.js Apps/SafariExtension/Extension/Resources/background.js Apps/SafariExtension/Extension/Resources/contentScript.js Apps/SafariExtension/Extension/Tests/panelPayload.test.mjs
git commit -m "Wire Safari extension voice config proxy"
```

---

### Task 7: Dashboard Voice Button Reuse

**Files:**
- Create: `Dashboard/src/shared/voice/voiceModeClient.ts`
- Modify: `Dashboard/src/shared/api/coreApi.ts`

**Interfaces:**
- Consumes: `/v1/voice/config`, `/v1/voice/transcriptions`, `/v1/voice/speech`.
- Produces: reusable Dashboard-side helpers for later chat-surface voice buttons.

- [ ] **Step 1: Add API client methods**

In `Dashboard/src/shared/api/coreApi.ts`, add methods to the API type and factory:

```ts
fetchVoiceConfig: () => Promise<AnyRecord>;
transcribeVoice: (payload: AnyRecord) => Promise<AnyRecord>;
synthesizeVoice: (payload: AnyRecord) => Promise<AnyRecord>;
```

Implement them with existing `requestJSON` style:

```ts
    fetchVoiceConfig: async () => requestJSON({
      path: "/v1/voice/config"
    }),
    transcribeVoice: async (payload) => requestJSON({
      path: "/v1/voice/transcriptions",
      method: "POST",
      body: payload
    }),
    synthesizeVoice: async (payload) => requestJSON({
      path: "/v1/voice/speech",
      method: "POST",
      body: payload
    }),
```

- [ ] **Step 2: Add reusable Dashboard voice helper**

Create `Dashboard/src/shared/voice/voiceModeClient.ts`:

```ts
export function normalizeVoiceConfig(config: Record<string, any> = {}) {
  return {
    enabled: Boolean(config.enabled),
    effectiveProvider: config.effectiveProvider === "openai" ? "openai" : "local",
    input: {
      mode: config.input?.mode === "auto_submit" ? "auto_submit" : "push_to_talk",
      language: String(config.input?.language || "auto"),
      previewBeforeSend: config.input?.previewBeforeSend !== false
    },
    local: {
      enabled: config.local?.enabled !== false,
      voiceName: String(config.local?.voiceName || ""),
      rate: Number.isFinite(Number(config.local?.rate)) ? Number(config.local.rate) : 1,
      pitch: Number.isFinite(Number(config.local?.pitch)) ? Number(config.local.pitch) : 1
    }
  };
}

export function browserVoiceSupport(windowLike: any = window) {
  return {
    recognition: typeof windowLike.SpeechRecognition === "function" || typeof windowLike.webkitSpeechRecognition === "function",
    synthesis: Boolean(windowLike.speechSynthesis),
    recorder: Boolean(windowLike.MediaRecorder && windowLike.navigator?.mediaDevices?.getUserMedia)
  };
}
```

- [ ] **Step 3: Verify Dashboard**

```bash
cd Dashboard && npm run typecheck && npm run build
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Dashboard/src/shared/api/coreApi.ts Dashboard/src/shared/voice/voiceModeClient.ts
git commit -m "Add dashboard voice mode client helpers"
```

---

### Task 8: Final Verification

**Files:**
- No planned source edits unless verification reveals a bug.

**Interfaces:**
- Consumes all previous tasks.
- Produces a verified branch ready for review.

- [ ] **Step 1: Run Swift focused tests**

```bash
swift test --filter voiceMode
swift test --filter voiceConfigEndpoint
swift test --filter voiceTranscriptionEndpoint
swift test --filter voiceSpeechEndpoint
swift test --filter BrowserContextModelsTests
```

Expected: PASS.

- [ ] **Step 2: Run Dashboard verification**

```bash
cd Dashboard && npm run typecheck && npm run build
```

Expected: PASS.

- [ ] **Step 3: Run Safari Extension tests**

```bash
cd Apps/SafariExtension/Extension && npm test
```

Expected: PASS.

- [ ] **Step 4: Run package build**

```bash
swift build -c release --product sloppy
```

Expected: PASS.

- [ ] **Step 5: Commit verification fixes if needed**

If any verification command required a source fix, stage the exact files reported by `git status --short` and commit them:

```bash
git status --short
git add path/to/fixed-file
git commit -m "Fix voice mode verification issues"
```

If no fixes were needed, do not create an empty commit.
