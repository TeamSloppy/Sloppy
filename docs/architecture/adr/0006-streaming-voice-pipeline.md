# ADR 0006: Streaming Voice Pipeline

- Status: Accepted
- Date: 2026-10-12

## Context

The current flow records a whole utterance, transcribes it, waits for the full agent reply, then synthesizes the full reply. End-to-end latency is several seconds, playback starts late, and the user cannot interrupt the agent.

## Decision

Make the cascaded pipeline streaming end to end:

1. **Capture and VAD on the client.** Silero VAD (or equivalent) detects end of speech for hands-free mode; push-to-talk stays supported.
2. **Streaming agent output.** Voice reuses the existing session event stream; the voice layer consumes typed text-delta events only.
3. **Sentence-level TTS.** Core segments assistant text into speakable chunks using a deterministic segmenter on punctuation/length boundaries (a text-formatting concern, not a behavior heuristic) and synthesizes chunks as they arrive. Audio chunks are delivered over SSE or WebSocket as typed events (`voice.audio.chunk`, `voice.audio.done`, `voice.error`).
4. **Barge-in.** When VAD detects user speech during playback, the client sends an explicit `voice.interrupt` message; Core cancels pending synthesis and the in-flight turn through typed cancellation.

Voice state (`idle`, `listening`, `transcribing`, `thinking`, `speaking`, `error`) is a typed state machine fed by client state, Core response fields and runtime events. It is never derived from assistant or transcript text, in line with `AGENTS.md`.

Existing bounded endpoints (`/v1/voice/transcriptions`, `/v1/voice/speech`) are kept for compatibility.

## Consequences

- Time to first audio drops from full-reply latency to roughly first-sentence latency.
- New transport and cancellation paths need router/service tests with realistic payloads.
- Chunk segmentation must handle Russian and English punctuation and be covered by deterministic tests.

## Implementation notes (2026-10-12)

- First iteration segments sentences **in the Dashboard** (`extractSpeakableSentences`) and reuses the bounded `/v1/voice/speech` endpoint per sentence, with the current and next sentence synthesizing while one plays. Core-side segmentation with SSE/WebSocket audio chunks remains the target for clients that cannot segment (Safari Extension).
- Segmentation is deterministic formatting: sentence-final punctuation, a minimum fragment length, and holding back unterminated fenced code. It does not inspect text for intent.
- **Hands-free input** is implemented in the Dashboard (`useHandsFree`): continuous 16 kHz-resampled PCM capture through an AudioWorklet with a 450 ms pre-roll, an energy-based `VoiceActivityDetector` (adaptive noise floor, hysteresis, 300 ms minimum speech, 800 ms hangover, 30 s cap) and one WAV transcription request per utterance, sent in order. Silero VAD was not used: the energy detector is dependency-free and deterministic, and can be swapped behind the same events if accuracy in noisy rooms requires it.
- **Barge-in** stops assistant playback when the user speaks over it. While audio plays, the speech threshold is raised 2.5x and speech must last 250 ms, which limits self-triggering from speakers; headphones are still recommended. Barge-in does not interrupt a running agent turn. Stopping the turn remains an explicit action.
- **Sending policy** follows the existing settings: an utterance is sent to the agent automatically only when input mode is `auto_submit` and `previewBeforeSend` is off; otherwise the transcript is placed in the input box. If the agent is busy, the transcript also goes to the input box instead of being dropped.
- A server-side `voice.interrupt` message is still not needed for this client-driven design and is not implemented.
