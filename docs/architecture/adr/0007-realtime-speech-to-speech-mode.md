# ADR 0007: Realtime Speech-to-Speech Mode

- Status: Accepted
- Date: 2026-10-12

## Context

The 2026-06-22 spec deferred Realtime until the bounded flow was stable. Cascaded STT, LLM and TTS cannot match native speech-to-speech on latency and conversational feel. A free option exists (Gemini Live on the AI Studio free tier); OpenAI Realtime is the paid alternative.

## Decision

Add Realtime as an optional, separate `voiceMode.provider` value (`realtime`) after ADRs 0004 to 0006 land:

- Core mints short-lived ephemeral credentials for the chosen vendor (Gemini Live or OpenAI Realtime); long-lived keys never reach the browser.
- The client connects directly (WebRTC or WebSocket) using the ephemeral credential.
- Tools and project context are bridged through typed Core events and tool-call records, not prompt text or phrase matching.
- Transcripts from the realtime session are persisted into the normal agent session so history, memory and Visor behave identically to typed chats.
- Cost controls: per-session time limit, idle timeout, and an explicit enable flag in config.

The cascaded pipeline stays the default and the fallback, because it works with any LLM configured in Sloppy.

## Consequences

- Lowest latency and natural interruption, at the cost of being bound to vendor models for the spoken turn.
- A separate implementation plan is required for session lifecycle, tool bridging and cost limits.
- Gemini Live is evaluated first because it is free to try.

## Implementation notes (2026-10-12)

- Configured as a separate `voiceMode.realtime` block (`enabled`, `apiKey`, `model`, `voice`, `systemInstruction`, `maxSessionSeconds`) rather than a new `voiceMode.provider` value, so existing `auto | openai | local` switches stay unchanged.
- `POST /v1/voice/realtime/session` mints a single-use Gemini ephemeral token (`uses: 1`, session lifetime capped by `maxSessionSeconds`, 60 s window to open the socket) and returns the token, constrained WebSocket URL, model, voice and system instruction. The API key is never returned. Key resolution: `voiceMode.realtime.apiKey`, `GEMINI_API_KEY`/`GOOGLE_API_KEY`, or a configured Gemini model.
- The token is not locked to a model with `liveConnectConstraints` yet; it is limited by single use and expiry.
- The Live model name is configurable (default `gemini-3.8-live`, taken from the current Gemini docs) because Live model names change often.

## Agent bridge (2026-10-12)

- **Tool bridge.** The Live session declares one function, `ask_agent(task)`. The Dashboard runs the task on the active chat session through the normal `POST /v1/agents/:id/sessions/:id/messages` path, so the agent keeps its tools, memory and approvals, and the work is visible in the chat timeline.
- **Non-blocking by design.** `ask_agent` returns `{status: "started"}` to Gemini immediately. When the agent finishes, its final answer is injected as a text input (`[Sloppy agent finished]` / `[Sloppy agent failed]` markers) and the model narrates the outcome. This does not depend on provider-side async function calling, which is not available on every Live model. While the agent works, the conversation continues normally.
- **Busy agent.** If the session is already running, the task fails fast with `agent_busy` and the model tells the user.
- **Transcript persistence.** Each completed turn is appended with `POST …/events` (no agent run) as `user`/`assistant` messages carrying the typed marker `userId: "voice-live"`. The agent sees them as ordinary history; auto-speak never reads them aloud again because it checks that field, not message text.
- **No double speech.** While a live session is active, auto-speak playback is paused and the model narrates agent results itself.
- Still open: approval prompts raised by the agent during a voice-initiated task are only visible in the chat UI, not by voice.
