---
layout: doc
title: Visor memory and bulletins
---

# Visor: memory and bulletins

Visor supervises the runtime, runs **memory maintenance** (decay, prune, optional merge), and produces **bulletins**—short operational digests of what the system is doing. This page clarifies how Visor relates to **agent memory** and what bulletins are (and are not).

## Hybrid memory maintenance

Visor schedules periodic passes (default: hourly) that adjust how hybrid memory ages:

- **Decay** — slowly reduces importance for stale entries.  
- **Pruning** — soft-deletes very low-importance, old entries.  
- **Merge** (optional) — consolidates near-duplicate entries when enabled and similarity thresholds are met.

These operations apply to the **hybrid memory store** (SQLite and optional external index). They do **not** replace agent-authored `USER.md` / `MEMORY.md` files; see [Agent memory](/agents/memory) for file limits and tools.

Configuration keys for intervals and thresholds live under `visor.*` in `sloppy.json`—see [Visor configuration](/visor/configuration).

## Bulletins: operational snapshots

A **bulletin** is a compact, periodically generated **status digest** (headline + text) built from runtime signals: channels, workers, recent events, and similar context. When a model is configured, Visor can **synthesize** a readable briefing; otherwise it falls back to a simpler text summary.

Bulletins are meant for **ambient awareness** (injected into prompts as background context) and for **operators** viewing the Visor area in the Dashboard. They are **not** the same as:

- **Hybrid memory entries** listed under **Agents → Memories** (those come from `memory.save` and related flows with explicit **scope**), or  
- **Agent `MEMORY.md`**, which is long-form markdown on disk, updated via agent document tools or **memory checkpoints**.

Visor bulletins are **not** treated as durable, user-editable “agent memory rows” in the hybrid taxonomy. Use `memory.save` with proper scope for facts you want in the Memories list, and `agent.documents.set_memory_markdown` (or checkpoints) for narrative `MEMORY.md`.

## Tool: `visor.status`

Agents can call **`visor.status`** to read Visor readiness and the latest bulletin digest. This is an **operational snapshot** tool—not a substitute for hybrid recall or for editing `MEMORY.md`.

## Memory checkpoints and Visor

**Memory checkpoints** (see [Agent memory](/agents/memory)) may run when the **context compactor** crosses a threshold on an agent session channel, or when sessions end or roll over. Those checkpoints refresh markdown files using allowlisted tools and **do not** post assistant text into the user-visible chat. They are orchestrated at the service layer; Visor still runs its own bulletin and maintenance loops independently.

## Related

- [Agent memory](/agents/memory) — hybrid store, `MEMORY.md`, tools, scopes, checkpoints  
- [Visor overview](/visor/overview) — supervision, signals, dashboard  
- [Visor configuration](/visor/configuration) — `visor.*` settings  
- [Context compactor](/agents/context-compactor) — threshold events  
