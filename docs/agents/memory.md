# Memory

Agents in Sloppy can remember things. Every fact, decision, goal, or observation an agent encounters can be stored and recalled later — across different conversations, sessions, and even after a server restart. Memory is what lets an agent build context over time instead of starting fresh on every message.

## How memory works

When something worth remembering happens — a user states a preference, an agent reaches a decision, a task gets completed — a memory entry is created. Each entry has a short text (the "note"), an optional summary, a type, a scope that controls who can see it, and metadata like importance and confidence scores.

Memory entries are stored locally in a SQLite database inside your workspace. On every message, the agent automatically searches its memory for relevant context and injects the most useful pieces into its understanding of the conversation. You don't need to do anything to trigger this — it happens automatically as part of every interaction.

## Types of memory

Not all memories are equal. Sloppy categorizes memories in two dimensions: what they represent and how long they should live.

### What a memory represents

| Type | What it is |
|---|---|
| Fact | General knowledge: names, versions, tech choices |
| Preference | What the user prefers or avoids |
| Goal | An objective the agent or user is working toward |
| Decision | A choice that was made and should be remembered |
| Todo | An action item that's been created |
| Identity | Information about who the agent is working with |
| Event | Something that happened at a point in time |
| Observation | Something the agent noticed during a task |

Sloppy infers the type automatically from the content — entries starting with "[todo]" become todos, entries mentioning "decided" become decisions, and so on. You can also set the type explicitly when saving from a tool or plugin.

### How long a memory lives

| Class | What it is | Default lifespan |
|---|---|---|
| Semantic | Long-term knowledge: facts, preferences, identity | No automatic expiry |
| Procedural | Goals, decisions, and todos | No automatic expiry |
| Episodic | Time-bound events and observations | 90 days |
| Bulletin | System-generated status summaries | 180 days |

Episodic memories are meant to reflect "what happened", not "what is true", so they expire after 90 days by default. Long-term knowledge (semantic and procedural) stays until it decays in importance or gets pruned.

### Who can see a memory

Every memory has a scope that limits which conversations can access it.

| Scope | Visible to |
|---|---|
| Global | All agents and channels |
| Project | All conversations within a project |
| Channel | Only the specific conversation where it was created |
| Agent | Only the specific agent it belongs to |

When an agent recalls memory for a channel, it only sees entries scoped to that channel, the parent project, and global — not entries from other conversations.

## How recall works

When searching memory, Sloppy combines three signals to find the most relevant entries:

- **Semantic search** — finds entries that are conceptually similar to the query, even if the exact words differ. This requires either an external memory provider or local vector embeddings to be enabled.
- **Keyword search** — finds entries that contain the query words directly, using full-text search built into SQLite.
- **Graph expansion** — finds entries that are related to the top results via memory edges, surfacing connected context that might not match the query text directly.

The three signals are blended using configurable weights. By default, semantic search carries the most weight (55%), followed by keyword (35%), and graph expansion (10%). If you prioritize exact-term matching over conceptual similarity, you can shift weight toward keywords.

## Memory relationships

Memories can be linked to each other. When an agent finishes a focused sub-task (a "branch"), it automatically saves the conclusion as a memory and links it back to the memories that informed the work. These links let future searches traverse the graph and surface related knowledge even when the query doesn't exactly match.

Links have types: one memory can support another, contradict it, depend on it, derive from it, or supersede it. The "supersedes" relationship is used when two similar memories are merged into one.

## Memory operations

The following operations are available to agents and tools at runtime:

- **Recall** — search memory with a free-text query, optionally filtered by type, class, or scope. Returns ranked results with relevance scores.
- **Save** — write a new memory entry. Type and class are inferred from the text when not provided.
- **Link** — create a typed relationship between two existing entries.
- **List** — retrieve entries using structured filters (scope, type, class, include deleted/expired).
- **Update importance** — adjust the importance score of an entry.
- **Soft delete** — hide an entry from retrieval without erasing it from the database.

## Keeping memory healthy automatically

Left unchecked, memory would grow forever. Sloppy automatically runs maintenance on a schedule (by default, every hour) via the Visor supervisor.

**Decay** — older memories become less important over time. Each day, the importance score of every non-identity memory is reduced by 5% (configurable). This reflects the natural fading of relevance for things that haven't been touched in a while.

**Pruning** — memories that have fallen below an importance threshold (default 0.1) and are at least 30 days old are soft-deleted. They remain in the database but are excluded from recall.

**Merge** — when enabled, Visor periodically scans for pairs of memories that are very similar (above a configurable similarity threshold). When two entries cover the same ground, they are consolidated into one, the originals are soft-deleted, and a "supersedes" edge is written to preserve the history. If a model is configured, the merge produces a synthesized note; otherwise the two texts are joined.

All of these thresholds are configurable. See the [configuration reference](#configuration-reference) below.

## Connecting an external memory service

By default, Sloppy stores and searches memory entirely on your local machine using SQLite. This works out of the box without any additional setup.

If you need more powerful semantic search — for example, vector similarity powered by embeddings — you have two options.

### Local embeddings

You can enable Sloppy's built-in embedding service, which converts memory entries into numeric vectors and stores them alongside the text. At recall time, the query is also embedded and matched against stored vectors using cosine similarity. This makes semantic recall much more accurate, especially for conceptual queries.

To enable this, set `memory.embedding.enabled` to `true` in `sloppy.json` and configure the embedding model endpoint and API key. Any OpenAI-compatible embeddings endpoint works — including OpenAI itself, Ollama, or a self-hosted model server.

### HTTP provider

You can point Sloppy at an external HTTP service that handles memory storage and search. Sloppy will continue writing to its local SQLite database as a canonical record, but will also send every save and query to your external service. The external service handles the semantic indexing; Sloppy uses its results as one of the recall signals.

This is useful if you have an existing vector database, a custom retrieval service, or want to share memory across multiple Sloppy instances.

### MCP provider

If your memory service exposes an MCP (Model Context Protocol) server, Sloppy can integrate with it directly. You register the MCP server in your configuration and point the memory provider at it by server ID. Sloppy will call the server's tools for upsert, query, delete, and health check operations.

In all external-provider modes, Sloppy's local SQLite database remains the canonical source of truth. The external provider is an index. If the provider is temporarily unavailable, operations are queued in an outbox and retried automatically with exponential backoff.

## Configuration reference

All memory settings live under the `memory` key in `sloppy.json`.

### Provider settings (`memory.provider`)

| Setting | Default | What it controls |
|---|---|---|
| `mode` | `local` | Where semantic indexing happens: `local`, `http`, or `mcp` |
| `endpoint` | — | URL of the external HTTP memory service (required for `http` mode) |
| `mcpServer` | — | ID of the MCP server to use (required for `mcp` mode) |
| `timeoutMs` | `2500` | Timeout in milliseconds for external provider calls |
| `apiKeyEnv` | — | Name of the environment variable holding the API key for the HTTP provider |

### Retrieval weights (`memory.retrieval`)

| Setting | Default | What it controls |
|---|---|---|
| `topK` | `8` | How many results to return per recall query |
| `semanticWeight` | `0.55` | Weight given to semantic/vector search results |
| `keywordWeight` | `0.35` | Weight given to full-text keyword search results |
| `graphWeight` | `0.10` | Weight given to graph-expanded related entries |

### Retention (`memory.retention`)

| Setting | Default | What it controls |
|---|---|---|
| `episodicDays` | `90` | How many days episodic memories are kept before expiry |
| `todoCompletedDays` | `30` | How many days completed todos are kept |
| `bulletinDays` | `180` | How many days system bulletins are kept |

### Embeddings (`memory.embedding`)

| Setting | Default | What it controls |
|---|---|---|
| `enabled` | `false` | Whether local vector embeddings are computed and stored |
| `model` | `text-embedding-3-small` | Embedding model identifier |
| `dimensions` | `1536` | Vector size; must match the model's output |
| `endpoint` | — | Embeddings API URL; derived from configured model providers if omitted |
| `apiKeyEnv` | — | Name of the environment variable holding the embeddings API key |
