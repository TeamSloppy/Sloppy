# Tool catalog discovery

- Date: `2026-10-18`
- Status: Stage 1 implemented; verification recorded with the delivery
- Related: [Skills and MCP Tooling](skills-mcp-tooling.md), [Coding Harness Reliability](coding-harness.md)

## Goal and delivery boundaries

Reduce large catalog dumps by finding tools before returning their schemas. The
catalog is metadata, the registry owns execution, and runtime exposure is a
separate concern. Decisions use tool IDs, policies and typed results, never
assistant prose or localized intent heuristics.

1. **Current stage:** policy-aware catalog search, compact built-in summaries,
   selected MCP schemas, calls through `mcp.call_tool`, and discovery metrics.
2. **Later:** dynamically expose built-in native schemas in the runtime. Replace
   irretrievable budget pruning with discovery; preserve transcript and ledger.
3. **Later:** provider-native deferred definitions and tool references.

Stage 1 does not change eager/lazy selection, the 30% `ToolSchemaBudget` window
fraction, provider transports, client UI, database schema or provider cache settings.
The default MCP path remains `mcp.list_tools` followed by `mcp.call_tool`, reusing
schemas already present in the conversation. `system.search_tools` is optional
when the user requests targeted catalog search; there is no automatic switch based
on catalog size. It is registered once as an ordinary, budget-prunable tool, while
`mcp.list_tools` and `mcp.call_tool` retain preferred priority. Existing
`system.list_tools` and `mcp.list_tools` remain compatible.

## Catalog and ownership

- `ToolRegistry` owns built-in implementations and their `parameters` schemas.
- `ToolCatalog.discoveryEntries` joins built-in metadata and argument names from
  the registry with the current session's `MCPDynamicTool` definitions. It does
  not use the legacy manually maintained `parameterSchemas` dictionary.
- `ToolDiscoveryService` filters before ranking, sorts ties by canonical ID and
  returns a bounded page. Exact canonical IDs take precedence; free-text queries
  use case-insensitive lexical matches across names, titles, descriptions and
  top-level argument names. There is no model call, intent classification,
  translation, embedding dependency or hard-coded list of intent phrases.
- MCP discovery follows all `tools/list` pages under the existing per-server
  timeout. Repeated cursors and excessive pagination fail that server. A failed
  refresh does not retain old tools as current. Partial catalogs are explicitly
  marked `metrics.catalogComplete=false`; an empty partial result is not proof
  that a tool does not exist. Existing retry/backoff still applies.

## Model-facing contract

`system.search_tools` accepts:

| Argument | Contract |
| --- | --- |
| `query` | Up to 512 characters; lexical search. Mutually exclusive with nonempty `ids`. |
| `ids` | Up to 10 exact canonical IDs. |
| `server` | Optional MCP server filter; server alone lists its permitted tools. |
| `limit` | Integer 1-10; default 5. |
| `offset` | Integer 0-100000; default 0; use returned `nextOffset`. |
| `includeSchemas` | Boolean; default true. False returns compact summaries only. |

At least one of query, ids or server is required. Bad types, empty selectors and
invalid pagination return `invalid_arguments` without a network discovery call.

Each result contains `name`, `title`, a bounded one-line `description`, and
`source` (`builtin` or `mcp`). Built-in matches remain summaries: search does not
make a budget-pruned native function callable.

An MCP match also returns:

```json
{
  "name": "mcp.tracker.search_issues",
  "source": "mcp",
  "invocation": {
    "name": "mcp.call_tool",
    "arguments": {"server": "tracker", "tool": "search_issues"}
  },
  "parameters": {"type": "object", "properties": {"query": {"type": "string"}}},
  "definitionHash": "sha256-of-canonical-input-schema",
  "schemaStatus": "included"
}
```

The agent fills `mcp.call_tool.arguments.arguments` using `parameters` (the
existing wrapper accepts an object or JSON-encoded object). Search executes no
MCP tool. Schema hashes describe the observed schema; they are not authorization
or concurrency tokens. A later invocation rechecks the current exposed target.

Results reserve metadata space and fit within the smaller of 24 KiB and the tool
output guardrail. Complete schemas are included only when they fit. Otherwise
`schemaStatus=omitted_budget` is returned without a partial schema. A budget too
small for even one summary returns `discovery_output_limit`. `nextOffset` is
explicit; it is null when no matches remain. Pagination is against the current
catalog, not a durable snapshot across configuration changes.

## Scope and authorization

- Filter canonical IDs through the agent policy before ranking or counting.
  Saved dynamic overrides survive server unavailability and process restarts;
  policy updates and actual invocations still validate tool IDs.
- Apply the delegated session allowlist and read-only coordinator/worker scope
  before emitting results. An empty explicit discovery scope exposes nothing.
- MCP targets require both target permission and permission for `mcp.call_tool`.
  A dynamic ID colliding with a built-in ID is hidden and cannot inherit its permission.
- Use the session-specific MCP registry, including ACP-supplied servers; do not
  search another session's servers or the global registry instead.
- `mcp.call_tool` resolves the target again against the current exposed catalog
  and checks the current invocation's policy and delegated scope. Disabled,
  unexposed, unknown or forbidden targets cannot be called through the wrapper.
- Discovery results contain server-controlled descriptions and schemas, so
  `system.search_tools` is an untrusted-output tool for the existing taint guard.
  A search does not make a subsequent risky call trusted.
- Existing wrapper approvals, hooks, loop guards and call/result events remain
  in the normal execution path. Discovery itself creates no approval grant.

## Metrics and evidence

Every successful search returns a typed `metrics` object, persisted through the
normal session tool-result event:

- visible `catalogTools`, `matchedTools`, `returnedTools`, `returnedSchemas`;
- `schemaBudgetOmissions` and `catalogComplete`;
- `catalogMCPSchemaEstimatedTokens` and `returnedSchemaEstimatedTokens`;
- end-to-end `durationMs`, including catalog discovery.

Schema token counts use `TokenPressureEstimator` and are explicitly estimates.
The full-catalog estimate is a comparison baseline, not tokens actually billed
or tokens known to have been saved. It excludes hidden tools and is computed
from MCP input schemas, not provider-native serialization overhead.

Metrics/OTel exports use the `sloppy.tool.discovery` prefix:

- `requests` counter with outcome `matched`, `empty`, `incomplete`, or `invalid_arguments`;
- `schemas_returned`, `schema_budget_omissions` counters;
- `catalog_tools`, `matched_tools`, `catalog_mcp_schema_estimated_tokens`,
  `returned_schema_estimated_tokens` recorders;
- `duration` timer;
- `mcp_calls` counter with outcome `success`, `server_error`, `transport_error`,
  `forbidden`, `unknown_target`, or `discovery_incomplete`, covering wrapper invocations, not inferred search conversions.

Logs contain session/agent correlation IDs and counts, not search queries or
schemas. Metric dimensions never contain session IDs, tool IDs, queries or
server-provided text. Export is enabled through the existing observability
configuration (`SLOPPY_OTEL_ENABLED=1`). Actual input/cache tokens, generated tool calls, result/replay
cost and failures continue through the existing usage request/component ledger;
compare whole-session cost and success rates rather than the first prompt only.
No cost or cache benefit is claimed until measured with real providers.

## Prompt caching and future exposure policy

Stage 1 keeps the native tool array fixed after initial registration. Selected
MCP schemas enter tool results at the tail of the conversation. It avoids
changing the native tool prefix for every search; it does not guarantee a cache
hit, which still depends on provider, adapter, prompt stability and cache policy.

For later native-schema loading, start with `auto` / `eager` / `lazy` configuration.
An initial auto threshold of 10% is a hypothesis: compare the *unpruned permitted
native schema cost* with the effective input window. Include compact catalog,
search tool, current history and response reserves in the overall budget. Do not
count every MCP schema as initially native when it is only available via the
wrapper. Fix the mode for a session until model/policy/configuration changes.

Keep a stable per-session canonical-to-provider name map computed from the full
catalog, loaded IDs and definition versions. Ordinary native `tools` array changes
may invalidate prefix caches; additive loading and deterministic order reduce
churn but cannot guarantee preservation. Anthropic-native `defer_loading` plus
`tool_reference` has different cache behavior and requires explicit support in
the model/endpoint/adapter capability contract. The current immutable
`LanguageModelSession.tools` requires a defined model-loop boundary for expansion,
not a session reset in the middle of a tool batch. Neither is part of Stage 1.

## Verification

- Deterministic ranking, exact IDs, parameter-name search, pagination and validation.
- Policy/default-deny, wrapper permission and delegated allowlist intersections.
- MCP schemas returned verbatim, compact-only mode and oversize-schema omissions.
- Search on a real local stdio MCP fixture, including multiple pages; invoke the
  selected tool with supplied arguments and verify persisted search metrics.
- Permission/config changes after search must reject stale target invocations.
- Incomplete discovery must be observable and isolated per session.
- Existing registry, authorization, concurrency, subagent and ACP MCP tests.

## Live measurement (2026-10-18)

The actual release Core was measured on `openai-oauth:gpt-6.1-sol` through the
existing first-party Codex OAuth path, using synthetic read-only MCP data.
The main series contains 24 verified tasks and 69 provider requests: two catalog
sizes, three paired repetitions, and two different tasks per conversation.
Both arms expose the same three native functions. All provider token totals are
present; local attribution completeness is tracked separately.

Mean totals per two-task workflow (all attempts included):

| MCP tools | Listing input | Search input | Search input change | Listing time | Search time |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 16 | 73,778 | 84,977 | +15.2% | 18.09 s | 37.75 s |
| 128 | 143,272 | 89,756 | -37.4% | 20.38 s | 24.60 s |

For 128 tools, uncached input fell by 69.3%; observed cache-read share was 25.3%
for listing and 63.4% for search. For 16 tools, uncached input rose by 12.5%.
Search required additional rounds for a new capability; two empty search results
also required query refinement. Token reduction did not produce a wall-time
improvement in this small series. This supports conditional discovery; two
catalog sizes do not establish a universal threshold, nor does this test measure
provider-native deferred transport or before/after registration overhead.

Reproduction: `bench/tool-discovery-live/run.py` and `summarize.py`.
Detailed methodology, per-request usage, session events, individual workflows,
and accounting caveats: `bench/results/tool-discovery-live-2026-10-18/`.
The decoder used for this measurement marked `error:null` as a failure; historical
raw flags are retained. The decoder now ignores null error fields while preserving
explicit provider failure events and transport failures. Task success in this
measurement was checked using typed validated MCP receipts.
No dollar savings are inferred from subscription token usage.

After restoring listing as the default and fixing the decoder, a separate live
smoke check used the rebuilt debug Core and the same real provider with a
16-tool synthetic catalog. The default task called `mcp.list_tools` then
`mcp.call_tool`; a fresh session with an explicit search request called
`system.search_tools` then `mcp.call_tool`. Both produced validated MCP receipts.
All six provider requests had token totals and `failed=0`. This is a route and
accounting regression check, not another latency comparison. Reproduce with
`bench/tool-discovery-live/verify-default-usage.py`; results are in
`bench/results/tool-discovery-live-2026-10-18/default-usage-verification.json`.
