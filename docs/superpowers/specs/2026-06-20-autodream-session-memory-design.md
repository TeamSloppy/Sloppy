# Autodream Session Memory Design

## Goal

Add an automatic background pass that periodically reviews recent agent sessions and turns durable learnings into existing agent/project memory, without revisiting unchanged sessions.

## Design

Autodream is a separate runner owned by `CoreService`, not part of the existing self-improvement curator. The runner uses the existing memory checkpoint path so the model can only use the checkpoint allowlist: `visor.status`, `memory.search`, `memory.save`, agent markdown updates, and project meta memory updates.

Configuration lives under `visor.autodream` with `enabled`, `intervalSeconds`, `jitterSeconds`, `sessionLimitPerRun`, and `model`. The default interval is 6 hours with jitter, and the model can be set to a cheaper small model. When absent, checkpoint execution falls back to `visor.model`, then the agent/default model behavior.

Processed sessions are tracked in SQLite with `(agent_id, session_id)` plus the session `updated_at` value that was reviewed. If a session changes later, it becomes eligible again. Failed reviews record an error and can be retried on a later pass.

## Testing

Tests cover config defaults/decoding, SQLite/fallback review state, candidate filtering, and runner overlap behavior. The implementation should reuse existing checkpoint tests for actual model/tool behavior rather than duplicate checkpoint prompt assertions.
