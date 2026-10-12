# ADR 0005: Default Free Voice Stack

- Status: Accepted
- Date: 2026-10-12

## Context

OpenAI voice is paid, and browser speech APIs are inconsistent. Users need a free or local path with good Russian accuracy, and a paid path for best quality.

## Decision

Support these providers behind the ADR 0004 abstractions, in this priority order for implementation:

**Speech-to-text**
1. **Groq Whisper** (`whisper-large-v3-turbo`), OpenAI-compatible multipart API, free tier. First new provider because it reuses the OpenAI request shape.
2. **Local server STT** via `whisper.cpp` (Metal on macOS) or `faster-whisper`, run by Core as a managed subprocess or HTTP sidecar. No network, no cost.
3. OpenAI (`gpt-4o-mini-transcribe`) remains available.

**Text-to-speech**
1. **Edge TTS** (`ru-RU-DmitryNeural`, `ru-RU-SvetlanaNeural`) as the free default. It is an unofficial API, so it must be isolated, time-limited and fail with a typed error.
2. **Silero TTS** / Piper as the fully offline option.
3. **ElevenLabs** as the optional high-quality paid option.
4. OpenAI (`gpt-4o-mini-tts`) remains available.

Default `auto` resolution: configured paid key if explicitly enabled, otherwise Groq STT with Edge TTS, otherwise local. Silent fallback happens only for configuration or availability errors and is surfaced to the client as a typed field; explicit provider choices never fall back silently.

## Consequences

- Free path works without any OpenAI key.
- Edge TTS carries availability risk; offline Silero/Piper is the documented fallback.
- Local STT adds an optional binary/model download; it is opt-in and never required to start Core.
- Linux CI must not depend on macOS-only engines; such tests use fakes.

## Implementation notes (2026-10-12)

- Implemented: Groq STT, ElevenLabs TTS, macOS `say` as the offline TTS, and **on-device STT via whisper.cpp** (`voiceMode.whisper`, `transcriptionProvider: "whisper"`).
- On-device STT runs `ffmpeg` (browser webm/mp4 to 16 kHz mono WAV) then `whisper-cli` as short-lived subprocesses with a hard timeout. Tool and model paths are explicit config or auto-detected (PATH plus Homebrew locations, since a launchd-started Core has a minimal PATH). It is never required to start Core.
- Recommended model: `ggml-large-v3-turbo-q5_0.bin` (about 570 MB). Verified end to end on Apple Silicon: Russian speech synthesized by `say -v Milena` is recognized verbatim.
- `auto` resolution for STT: OpenAI, then Groq, then on-device.
- Not implemented: Edge TTS (unofficial, signed-token WebSocket), Silero/Piper (non-macOS offline TTS), Parakeet.
