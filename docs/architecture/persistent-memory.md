# Persistent memory lifecycle

Sloppy uses two complementary layers. Curated markdown provides a compact, editable
profile and reference notes. The SQLite memory store provides scoped, searchable
records. Reading configuration or starting a session must never regenerate curated
markdown from database rows: the two stores have different ownership and contents.

## Reading

- `AgentCatalogFileStore` loads `USER.md` and `MEMORY.md`, including existing per-user
  overrides. These documents remain the source of truth for their content.
- `RuntimeSystem.persistentMemoryContext` adds a separate session-start snapshot of
  semantic/procedural records explicitly scoped to the agent and current project.
  It prioritizes identity/preferences, importance, and recency; the default combined
  budget is 6,000 characters, divided between scopes, with at most 24 entries per scope.
- Before a response, semantic recall searches the agent, explicitly associated
  project, and current channel. Ranked hits share the existing eight-hit/6,000-character
  response-context budget. Project association comes from session metadata.
- Other sessions' channel-scoped records are not promoted to agent memory. Other
  agents, unrelated projects, and global scopes are not added automatically.
- Workspace-private project `.meta/MEMORY.md` is loaded even if the project has no
  repository. A project's memory is independent of whether it contains source code.

The initial snapshot is intentionally bounded. Search/get tools remain available for
specific details. Historical facts are not instructions; current corrections take
precedence and changeable claims require verification.

## Debug diagnostics

Dashboard **Debug → Session Context Inspector** exposes bootstrap selection checks, automatic recall, and
`memory.search` / `memory.recall` queries for the selected session. Each record includes
the query, source, scope, requested limit, monotonic retrieval duration, returned IDs,
scores, result character count, and estimated tokens. Hybrid retrieval also reports
provider, embedding, keyword, and graph stage durations/candidate counts and provider
errors (type/code, without raw provider response bodies), including failures followed by local fallback. Bootstrap
checks report listing candidates and bounded selection; their scores represent importance.
They may reuse an existing bootstrap, so the actual model snapshot remains the source
for what was sent. SQLite recall logs now store
the measured latency and the IDs actually returned.

The latest native runtime turn has a separate snapshot captured after context
preparation, before streaming. It contains ordered instructions (including tool
definitions), retained history, tool calls/results, and the pending user prompt.
The automatic memory block records its retrieval operation ID, included IDs, text,
size, and token estimate. Returned matches can exceed the final injected selection.
Images are represented by IDs and MIME/byte-count or URL metadata, without copying
binary image data. The snapshot is a runtime input view, not a provider wire payload
or a trace of subsequent provider-internal tool-loop requests. External ACP sessions
without this native turn path have no captured model context.

Diagnostics are process-local: the runtime retains the newest 200 recall requests
across all sessions and the latest input for up to 16 sessions. Statistics apply only
to the retained requests for the selected session. Query/hit text previews are capped;
context previews retain up to 500 entries and 128,000 text characters, with at most
16,000 characters per entry. Original sizes and truncation flags remain visible.
Token estimates are labeled separately from provider-reported usage. Debug reads do
not trigger recall, modify memory, or reconstruct a prompt from current documents.
The existing debug endpoint includes `memoryDiagnostics` and `contextLedger`:
`GET /v1/debug/session-context/:agentId/:sessionId`.

## Writing and review

The foreground agent is instructed to save preferences, corrections, environment
constraints, conventions, and verified lessons when they become clear, including in
short conversations. Personal facts belong in the current user's documents. Reusable
agent/project facts use explicit corresponding scopes; channel scope is reserved for
conversation-local knowledge. Full-document tools must preserve useful existing notes.
`memory.save(memory_id: ...)` updates the existing scoped record when a user corrects
a fact, retaining its ID and avoiding contradictory duplicates.

Background checkpoints retain the existing triggers (eight user turns, compaction,
explicit request, session transitions, and project task events). They read the current
user's documents and review the newest transcript within the existing budget, excluding
private thinking segments. The model receives only the checkpoint tool allowlist;
the invocation boundary independently enforces the same list. Ephemeral channel cleanup
also removes this allowlist and project association.

## Hermes comparison (local source inspection, 2026-09-05)

Hermes separates bounded `MEMORY.md` and `USER.md`, loads frozen prompt snapshots, and
supports add/replace/remove operations with live state returned by the memory tool.
Its `agent/system_prompt.py`, `agent/prompt_builder.py`, `agent/turn_context.py`, and
`agent/background_review.py` show proactive memory guidance plus a background review
triggered by a turn counter (default ten). Session history search and reusable skills
complement the small core memory.

Sloppy already had markdown, searchable storage, and checkpoints. The main gaps were
in the connections: database export overwrote curated markdown; automatic retrieval
searched only the current channel; checkpoint truncation discarded recent corrections;
checkpoint reads used root documents while writes could target a user override;
and projects without repositories lost their markdown on the read path.

## Live evaluation (`sloppy bench memory`)

`bench/memory/*.json` are multi-session scenarios run against a live Core (`sloppy bench memory --model <id>`).
Each run gets a throwaway agent and random per-run tokens (`{{A}}`, `{{B}}`, ...), teaches facts in one session and
asks in a fresh one. Pass/fail is an exact match for the planted token in the reply (and, for corrections, absence of
the old value). The report also says where each fact ended up (`docs` = curated markdown, `sqlite` = memory entries,
`nowhere`). Agents are isolated by default (`sharedMemoryEnabled: false`); `--shared-memory` measures the shared mode.

Scenarios: fact stated once, explicit "remember", correction, implicit convention, explicit checkpoint, one fact among
eight unrelated ones.

Results (isolated agents, isolated Core, embeddings through Ollama `nomic-embed-text`):

| model | before fixes | after fixes |
|---|---|---|
| gpt-6.1-sol | 17/18 (the miss: fact never saved, explicit checkpoint did not rescue it) | 12/12 |
| gemma4:31b-cloud | 0/12 | 11/18 (61%) |

What the evaluation found and what changed:

- **Facts land in two layers, chosen by the model.** Personal facts and conventions went to the per-user `USER.md`,
  project/service facts to SQLite. Both layers worked for a strong model, and a correction updated the entry in place.
- **`memory.search` without a scope searched the whole store**, including other agents' and unrelated projects' memory.
  It now searches the agent, the current project, the conversation, and shared memory only when enabled.
- **The model had to invent `scope_id`.** The only concrete example in the tool descriptions was `global`/`shared`,
  so weaker models used it, were rejected when shared memory was off, and did not recover. `scope_id` is now filled in
  from the session when only `scope_type` is given, descriptions lead with `agent`, and rejections list the scopes that
  work for the session.
- **Search results named the record id `id`**, which a weaker model returned as the answer to "what is the deploy key
  id?". The field is now `memory_id`, matching `memory.save`, in tool results and in the automatic recall block.
- **Vector search integrity** (found while reading the retrieval code): vectors of a different dimension were compared
  by their common prefix and scored as if comparable; the SQL `LIMIT` was applied before ranking so entries beyond the
  first 160 were never considered; and an embedding that failed at save time was never retried. Dimension mismatches
  now score zero and are re-embedded, missing vectors are backfilled, and all vectors in scope are ranked.

## Correcting facts

Tracing the correction scenario on a weaker model showed what actually failed. The correction was usually *stored*
correctly when the entry's UUID was visible, but then the model answered with that UUID ("what is the deploy key
id?" matched `memory_id`). With the UUID removed from the recall block, the model called `memory.search`, saw the
record, said "updated", and never called `memory.save`: the two-step "find the id, then update" protocol broke
halfway. Rewriting the same text by similarity was rejected: "deploy key of X = A" and "deploy key of Y = A" are
lexically almost identical, so any text-similarity merge would destroy a valid fact.

The fix is a typed key instead of inference:

- `memory.save` takes an optional `topic` (a short stable name such as "billing service deploy key id"). Saving again
  with the same topic in the same scope **replaces** the earlier entry in one call and reports `replaced_note`; older
  duplicates of that topic are removed. Matching is exact after case and punctuation folding (`MemoryTopic.key`).
  Entries without a topic are never replaced, and different topics never interact.
- The recall block shows `[topic]` before each entry and its header says to save again with the same topic, so the
  key is in front of the model exactly when it needs it. It no longer shows record ids at all.
- `memory.search`/`memory.get` results include `topic`. `memory_id` remains for editing one specific record.
- The memory rules prompt and the checkpoint prompt describe the topic protocol.

Results on `gemma4:31b-cloud` (isolated agents, 3 attempts per scenario):

| scenario | before | after |
|---|---|---|
| correction | 0-1 of 6 | 3/3 |
| correction-chain (two corrections) | n/a | 3/3 |
| similar-facts-coexist (two services, same wording) | n/a | 3/3 |
| all recall scenarios | 11/18 | 19/21 (90%) |

## Keeping what was saved

The remaining `checkpoint-recall` failures were not a failure to save. Across 16 runs the foreground agent called
`memory.save` every time, in the right scope, with the full note; `fact-recall` passed 8/8. The loss came afterwards:
the explicit memory checkpoint (a background review, run here by the strong default model) rewrote the finished entry
into a shorter paraphrase and dropped "its deploy key id is ...". The user had already been told "saved". A control
run with an obviously harmless attribute ("support queue code") instead of a "key id" passed 8/8, so the reviewer was
treating the id as credential-like, which the rules told it to avoid storing.

Two changes:

- **Rules.** Secrets are now defined as secret *values* (passwords, access tokens, private keys, the secret part of a
  key). Identifiers (names, ids including a key's or account's id, ports, versions, ticket numbers, URLs) may be stored.
  Both the memory rules and the checkpoint prompt say never to shorten a record or drop its details when updating.
- **A structural guard that does not depend on the model.** An update through `memory_id` or a topic is refused with
  `memory_update_would_lose_details` when it removes identifier-like tokens (a token with a digit, or an upper-case code
  of four or more letters) without adding any replacement. A correction that swaps a value for another is unaffected.
  The refusal names the dropped details and says how to proceed, and the original entry stays untouched
  (`MemoryNoteDiff`; it looks only at token shapes, never at wording).

`checkpoint-recall` on `gemma4:31b-cloud`: 4/8 -> 8/8, entry intact in all eight.

## Verification boundary

Regression tests cover curated-file survival across config reads and new sessions,
agent/project recall in a fresh session, exclusion of unrelated scopes, bounded
snapshots, newest-transcript retention, project memory without a repository, and
retrieval after reopening SQLite. These establish the storage/context contract.
They do not measure how often a real model chooses to save or whether its summaries
are useful. That requires a live multi-session evaluation with user corrections,
project decisions, a fresh session, and checks for accurate reuse without prompting.

Validation on 2026-09-05: 33 focused tests passed, including checkpoint scheduling.
Release builds of `sloppy` and `SloppyNode` passed; `sloppy --version` and
`SloppyNode --help` launched successfully. The full parallel suite was attempted
with loopback access and stopped after failures in project-file fallback, review
settings, and Mesh authorization tests; it did not produce a completed suite result.
No live-model learning-quality measurement was performed.
