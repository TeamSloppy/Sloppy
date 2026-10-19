# Live tool-discovery measurement

Model: `openai-oauth:gpt-6.1-sol` through Sloppy's existing OpenAI Codex OAuth provider (`chatgpt.com`).
Started: `2026-10-18T19:18:55Z`. Finished: `2026-10-18T19:24:03Z`.

Verified MCP task outcomes: **24/24**. Strategy compliance: **24/24**. Observed model requests: **69**.

## Two-task workflows

Each cell is the arithmetic mean of 3 paired repetitions (rounded). Each workflow contains a new-session task and a different task in the same conversation. All extra queries remain in these averages; medians and individual workflows are also saved in summary.json.

| MCP tools | Strategy | Input tokens | Cache-read tokens | Uncached input | Requests | Wall time |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 16 | listing | 73 778 | 39 595 | 34 183 | 5.00 | 18.09 s |
| 16 | search | 84 977 | 46 507 | 38 471 | 6.33 | 37.75 s |
| 128 | listing | 143 272 | 36 224 | 107 048 | 5.00 | 20.38 s |
| 128 | search | 89 756 | 56 917 | 32 838 | 6.67 | 24.60 s |

Paired input-token changes (search / listing - 1):

- 16 tools: input **+15.2%**, uncached input **+12.5%**, wall time **+108.6%** (ratios of means).
- 128 tools: input **-37.4%**, uncached input **-69.3%**, wall time **+20.7%** (ratios of means).

## Individual tasks

| MCP tools | Task position | Strategy | Input, median | Requests, median | Wall time, median |
| ---: | --- | --- | ---: | ---: | ---: |
| 16 | first | listing | 42 274 | 3 | 10.82 s |
| 16 | first | search | 38 044 | 3 | 17.27 s |
| 16 | next, same session | listing | 31 504 | 2 | 8.00 s |
| 16 | next, same session | search | 41 685 | 3 | 16.65 s |
| 128 | first | listing | 77 024 | 3 | 11.92 s |
| 128 | first | search | 38 044 | 3 | 12.69 s |
| 128 | next, same session | listing | 66 250 | 2 | 7.32 s |
| 128 | next, same session | search | 41 682 | 3 | 11.06 s |

## Observations

- 2 empty targeted-search results required query refinement; these attempts are included in the totals.
- Query refinement costs are visible in the raw tool-call arguments and every extra model request remains in the averages.
- Compare input, cached input, request counts and latency separately. Fewer tokens do not guarantee lower wall time when discovery adds model rounds.
- Listing can reuse all returned schemas on a later task; targeted search may need to acquire another schema. The second-task measurements include this difference.
- These results support keeping the discovery strategy conditional on catalog size and workflow. Two catalog sizes do not identify a universal crossover threshold.

## Method and limits

- Real model inference and the actual built Sloppy Core, `system.search_tools`, `mcp.list_tools`, and `mcp.call_tool`; MCP data itself is synthetic and read-only.
- Catalog sizes 16 and 128; three task families (stock, incident status, artifact digest); three repetitions, two tasks per conversation, both strategies. Arm order alternates across pairs.
- Both arms use the same three native tool definitions and permission scope. This isolates the catalog-acquisition strategy; installation overhead of the extra native search definition is not measured.
- The second task uses a different tool. Listing may reuse all previously returned schemas. Search may need another discovery request. All extra requests and retained context are included.
- MCP connection and metadata discovery are prepared during agent policy setup before timed turns. Server startup is excluded from both arms.
- Token counts come from `usage_requests` populated from provider response usage, not `TokenPressureEstimator`, character counts, or the discovery baseline estimate.
- [OpenAI usage/cache semantics](https://developers.openai.com/api/docs/guides/prompt-caching): cache-read share is summed cached input divided by summed input. The report does not convert subscription usage to dollars. Cache-write counts are not interpreted because the current OAuth usage path does not expose their availability.
- A first task is not guaranteed to be cache-cold; native prompt prefixes can already be cached. The observed cache counts are reported, not an assumed warm/cold state.
- `usage_requests.complete` describes local attribution completeness (including `previous_response_id`); a false value does not mean provider totals are missing. Provider total availability is checked independently.
- The decoder used for this measurement marked successful Responses requests as failed when `error:null` was present (`UsageWireDecoder.swift`, error-field presence check). This has since been fixed for new requests; historical raw flags are retained. Task success here requires a typed, validated MCP receipt with matching target and exact arguments; no model-text success heuristic is used.
- Three repetitions per configuration are exploratory evidence, not a statistically established threshold or a production-wide latency guarantee.
- No user documents, production MCP calls, or changes to the running user Core configuration. The temporary OAuth copy has no refresh token and is deleted when the isolated Core stops.

Raw per-request records, calls and session events: [raw-results.json](raw-results.json). Machine-readable aggregates: [summary.json](summary.json).

## Post-fix regression check

The rebuilt debug Core was checked separately on the same real provider with a
16-tool synthetic MCP catalog. Without a route instruction the model used
`mcp.list_tools` then `mcp.call_tool`. An explicit search request in a fresh
session used `system.search_tools` then `mcp.call_tool`. Both returned validated
MCP receipts, and all six provider requests were persisted with `failed=0` and
provider token totals. This checks routing and accounting, not relative latency.

Reproduce with `python3 bench/tool-discovery-live/verify-default-usage.py`.
The binary hash and individual request records are in
[default-usage-verification.json](default-usage-verification.json).
