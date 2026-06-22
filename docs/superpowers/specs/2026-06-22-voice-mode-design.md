# Voice Mode Design

## Goal

Add a hybrid voice mode for the Dashboard and Safari Extension so a user can talk to an agent by voice. The mode should use OpenAI audio services when the user explicitly configures them, and fall back to local browser speech APIs when OpenAI voice is not configured or unavailable.

## Scope

This design covers:

- A new Voice Mode section in Dashboard settings.
- Runtime configuration for voice mode.
- Dashboard and Safari Extension voice capture, transcription, agent message submission, and speech playback.
- Core endpoints needed for OpenAI-backed transcription and text-to-speech.

This design does not cover realtime WebRTC speech-to-speech as the first implementation. Realtime can be added later after the bounded transcription and TTS flow is stable.

## User Experience

Dashboard settings gets a dedicated `Voice Mode` tab. The user can enable voice mode, select `Auto`, `Local`, or `OpenAI`, choose microphone input behavior, choose language, and configure OpenAI transcription and TTS defaults.

In the Safari Extension drawer, a microphone button opens a voice mode surface. The surface follows the existing compact drawer style and exposes:

- Start or hold-to-talk recording.
- Stop/cancel recording.
- Current state: idle, listening, transcribing, sending, speaking, or error.
- Transcript preview before send when configured.
- Mute/stop playback.

In Dashboard chat surfaces, the same client voice controller can be reused behind a voice button, but the first implementation should focus on the settings tab and Safari Extension entry point.

## Configuration

Add `CoreConfig.VoiceMode` and persist it under `voiceMode` in `sloppy.json`.

Suggested shape:

```json
{
  "voiceMode": {
    "enabled": false,
    "provider": "auto",
    "input": {
      "mode": "push_to_talk",
      "language": "auto",
      "previewBeforeSend": true
    },
    "openAI": {
      "enabled": false,
      "transcriptionModel": "gpt-4o-mini-transcribe",
      "ttsModel": "gpt-4o-mini-tts",
      "voice": "coral",
      "instructions": ""
    },
    "local": {
      "enabled": true,
      "voiceName": "",
      "rate": 1,
      "pitch": 1
    }
  }
}
```

`provider` values:

- `auto`: use OpenAI when `voiceMode.openAI.enabled` is true and Core can resolve OpenAI credentials; otherwise use local browser speech APIs.
- `openai`: require OpenAI voice. If unavailable, show a configuration error instead of silently falling back.
- `local`: use browser speech APIs only.

## Core Behavior

Core remains the trust boundary for OpenAI credentials. Browser code must not receive raw provider API keys.

Add a voice effective-config API:

- `GET /v1/voice/config`
- Returns sanitized settings plus availability: effective provider, local availability hint, OpenAI configured status, model IDs, voice, language, and UI defaults.
- Does not return API keys.

Add bounded audio endpoints:

- `POST /v1/voice/transcriptions`
- Accepts multipart or JSON base64 audio, language hint, and optional prompt.
- Uses configured OpenAI transcription model.
- Returns `{ text, provider, model }`.

- `POST /v1/voice/speech`
- Accepts text plus optional voice/instructions.
- Uses configured OpenAI TTS model and returns an audio response or base64 audio payload.

OpenAI credential resolution should reuse the existing provider configuration and environment credential paths where possible. If no OpenAI voice credentials are available, endpoints return a stable 409-style configuration error that the clients can display.

## Client Flow

For local mode:

1. Browser requests microphone permission or uses SpeechRecognition where available.
2. Speech is transcribed locally.
3. The transcript is sent through the existing agent/browser context message endpoint.
4. Assistant text is played using `speechSynthesis`.

For OpenAI mode:

1. Browser records audio with `MediaRecorder`.
2. Audio is sent to Core `/v1/voice/transcriptions`.
3. Transcript is sent through the existing agent/browser context message endpoint.
4. Assistant text is sent to Core `/v1/voice/speech`.
5. Browser plays returned audio.

For `auto` mode:

1. Client reads `/v1/voice/config`.
2. If effective provider is OpenAI, use OpenAI flow.
3. Otherwise use local flow.
4. If OpenAI fails at runtime and provider is `auto`, fall back to local only when the failure is configuration or availability related, and surface the fallback state.

## Dashboard Changes

Add a settings section in `Dashboard/src/features/config/configModel.ts`:

- `id: "voice-mode"`
- title `Voice Mode`
- icon `mic`
- search terms for voice, speech, transcription, TTS, OpenAI, microphone.

Add `VoiceModeEditor.tsx` under `Dashboard/src/features/config/components/`.

The editor should use existing settings form patterns:

- Checkbox/toggle for enabled.
- Segmented control for provider.
- Text inputs for model IDs and instructions.
- Custom dropdown pattern for voice choice, not native `select`.
- Numeric controls for local rate and pitch.
- Status copy that distinguishes configured OpenAI voice from local fallback.

Normalize `voiceMode` in Dashboard config model so missing configs load with safe defaults and raw config round-trips.

## Safari Extension Changes

Extend settings sanitization and storage with voice settings only when needed for local fallback. Core remains authoritative for the current voice mode.

Content script:

- Add microphone icon and voice mode overlay/surface.
- Implement a small voice state machine.
- Reuse existing browser context message streaming so voice prompts enter the same session flow as typed prompts.
- Speak only assistant text responses, not tool-event metadata.

Background service worker:

- Add message handlers for reading effective voice config.
- Add message handlers for OpenAI transcription and TTS proxy calls to Core.
- Keep existing browser context send/stream flow unchanged.

Manifest:

- Add microphone/audio permissions only if required by Safari Web Extension packaging. Prefer runtime permission prompts where supported.

## Error Handling

Handle these states explicitly:

- Microphone permission denied.
- SpeechRecognition unavailable in the current browser.
- MediaRecorder unsupported or unsupported MIME type.
- OpenAI voice disabled or missing credentials.
- Transcription returns empty text.
- Agent request fails after transcription.
- TTS generation fails; show text response and do not block the conversation.
- Audio playback blocked by browser autoplay policy; expose a play button.

Avoid deciding state from assistant text content. Voice mode state must come from typed client state, Core response fields, and streaming events.

## Testing

Swift:

- `CoreConfig` decodes defaults for missing `voiceMode`.
- `CoreConfig` round-trips configured voice mode.
- Voice config endpoint returns sanitized effective config.
- OpenAI voice endpoints return configuration errors without credentials.
- Browser context flow remains unchanged.

Dashboard:

- Config normalization includes `voiceMode`.
- Voice Mode settings save and reload through existing config save flow.
- Editor renders local fallback and OpenAI configured states.

Safari Extension:

- Panel payload tests cover voice transcript submission through existing browser context payload.
- Background message tests cover effective config and error propagation.
- Manifest tests cover any new permission requirements.

Manual verification:

- Local mode: microphone to transcript to agent response to browser speech.
- OpenAI mode: recorded audio to Core transcription, agent response, Core TTS playback.
- Auto mode: OpenAI unavailable falls back to local; OpenAI required mode does not silently fall back.

## Implementation Phases

1. Add config model, Dashboard Voice Mode tab, and tests.
2. Add Core sanitized config endpoint and tests.
3. Add Safari Extension local voice flow.
4. Add Core OpenAI transcription and TTS endpoints with tests.
5. Wire Safari Extension OpenAI flow and fallback behavior.
6. Add Dashboard reusable client voice controller after the Safari flow is stable.

## Follow-Up: Realtime

After bounded audio works, add an optional Realtime mode:

- Core creates ephemeral Realtime client secrets.
- Browser connects via WebRTC.
- Tool/context integration still routes through typed Core events instead of prompt text heuristics.

Realtime should be a separate implementation plan because it changes transport, session lifecycle, latency behavior, and cost controls.
