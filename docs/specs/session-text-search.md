# Session text search

Sloppy searches persisted conversation text through a derived SQLite FTS5 database at
`<workspace>/search/index.sqlite`. This database is independent of the main persistence
store. JSONL journals remain the source of truth. Stop the Core and remove only the
`search` directory to rebuild the index on its next startup.

## Coverage and matching

The index includes all agent sessions (including workers and heartbeat sessions), both
canonical dated journals and legacy journals, and channel sessions. It indexes message
text, persisted thinking, tool arguments and results, plans, input requests and answers,
build progress, run status and session titles. It does not extract text from binary
attachments, images or PDF files, or search arbitrary repository files.

`GET /v1/search?q=...&mode=text&limit=50&offset=0` returns matches, marked snippets,
source/session/event identifiers and the event's exclusive JSONL byte boundary. Optional
`agentId` and `projectId` filters constrain the results. Limits are 1–100 results, a
1,000-character query, and an offset up to 10,000.

- `text`: literal, case-insensitive substring matching using the trigram index, from
  three Unicode characters. Spaces and punctuation are preserved in the query.
- `words`: Unicode word matching, with a prefix on the last query token.
- One- and two-character queries use word-prefix matching in both modes.

FTS syntax is escaped before matching. Queries are parameterized. Snippets use U+E000
and U+E001 as highlight boundaries; clients render text rather than executing HTML.
`GET /v1/search/document?id=...` returns the complete matched event text without loading
its transcript. Missing or deleted sources return 404. Both endpoints use the regular
Core authentication and authorization middleware.

## Index lifecycle

Startup schedules a utility task to build or resume the index. It reconciles journals
in the background every two seconds; searches do not enumerate or parse history files.
New complete JSONL lines are indexed in batches. Incomplete trailing lines wait for a
later append. File checkpoints and FTS rows commit in the same transaction. Rewrites,
truncations and deletions invalidate the old projection. A prefix and boundary check
protect the incremental append path; unchanged files need no JSON decoding.

WAL mode and separate connections let reads continue during indexing. Responses expose
`indexing`, `indexedSources`, `failedSources` and `durationMs`; clients show incomplete
coverage and do not turn a failed request into an empty result. A query reads at most
one bounded result page, in descending index insertion order, without global BM25 ranking.
This order prioritizes newly indexed events and is not a strict chronological sort
across sessions during the initial backfill. Deleted source files are also checked before returning hits.

## Interfaces and verification

Dashboard exposes Search in the sidebar and with Command/Control-Shift-F. ClientNative
extends desktop toolbar search and provides a full-text search sheet on macOS and iOS.
The All instance selection queries each discovered server with its own endpoint and
authentication context. Each match opens its full text; Open chat opens its source
conversation. Project and chat title navigation remains available.

Run focused checks:

```sh
swift test --filter TextSearchTests
SLOPPY_SEARCH_BENCHMARK_COUNT=100000 swift test --filter TextSearchTests.measuresIndexedQueryLatency
(cd ClientNative && swift test --filter TextSearchAPITests)
(cd Dashboard && npm run typecheck && npm run build && node scripts/textSearchTest.mjs)
```

Browser tests can use an existing compatible Chromium executable through
`SLOPPY_TEST_BROWSER_EXECUTABLE`. The benchmark measures query execution against a
synthetic index and reports median, p95 and maximum latency; it is not an end-to-end
network or UI latency measurement.
