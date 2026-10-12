# ADR 0004: Pluggable Voice Providers

- Status: Accepted
- Date: 2026-10-12

## Context

Voice Mode (see `docs/superpowers/specs/2026-06-22-voice-mode-design.md`) is implemented only on top of OpenAI: `OpenAIVoiceModeClient` calls `/v1/audio/transcriptions` and `/v1/audio/speech`, and `CoreService+VoiceMode` resolves OpenAI credentials directly. The `local` provider means browser `SpeechRecognition` / `speechSynthesis`, which is unreliable across Safari and Chrome and weak for Russian. There is no free, accurate, server-side option, and adding a second provider would currently mean copying the OpenAI-specific branches in `CoreService`.

## Decision

Introduce a provider abstraction in `Sources/sloppy/Voice/`:

- `VoiceTranscriptionProvider`: `transcribe(request:) async throws -> VoiceModeTranscriptionResponse`
- `VoiceSpeechProvider`: `speech(request:) async throws -> VoiceModeSpeechResponse`

Providers are `Sendable` structs registered in a small `VoiceProviderRegistry`. `CoreService+VoiceMode` resolves the STT and TTS provider independently from `CoreConfig.voiceMode`, so STT and TTS may come from different vendors.

Core remains the trust boundary for credentials. Browser and Safari Extension code never receives provider API keys. Provider selection and fallback are driven by typed config and typed errors (`VoiceModeError`), never by inspecting transcript or assistant text.

`voiceMode.provider` keeps `auto | openai | local` for backward compatibility. New per-direction fields (`voiceMode.stt.provider`, `voiceMode.tts.provider`) are additive and optional; missing values preserve current behavior.

## Consequences

- Adding a provider is one file plus a registry entry, with tests via router/service using injected fakes.
- `OpenAIVoiceModeClient` is adapted to the protocols without changing wire behavior.
- Public API (`/v1/voice/*`) stays backward compatible; responses already carry `provider` and `model`.
- Dashboard `VoiceModeEditor` gains provider pickers using the custom `.actor-team-search` dropdown pattern.
