# Live provider measurement

This harness compares `mcp.list_tools` with `system.search_tools`, followed by
`mcp.call_tool`, in the built Sloppy runtime against its real OpenAI Codex OAuth
provider. The MCP catalog is a synthetic read-only fixture; successful tasks
require matching typed receipts from that fixture.

```sh
python3 bench/tool-discovery-live/run.py --sizes 16 128 --trials 3
python3 bench/tool-discovery-live/summarize.py bench/results/tool-discovery-live-2026-10-18/raw-results.json
```

Requirements: a release build of `sloppy`, Python 3, and an existing working
Sloppy OpenAI OAuth identity in `~/.sloppy/auth/openai-oauth-auth.json` for the
configured model. Run with network and loopback permissions. The real model calls
consume that account's quota.

The harness starts a disposable Core with one model and one fixture MCP server.
Its private OAuth copy excludes the refresh token; the user's original file and
running Core are not modified. The copy and local Core credentials are removed
when the run stops. Benchmark agents can only discover tools and call the fixture.
Their untrusted-context guard is explicitly off for this trusted fixture; product
defaults are unchanged. Native tool inventory and scope are identical in both arms.

Each paired session performs two different tasks. Full listing can reuse its
catalog for the next task; targeted search may require another model round.
Both total input and cache-read input are measured from provider usage records,
not local estimates. All actual model requests count toward the result.

The default series has 24 task turns. A separate budget stops after more than
96 observed model requests or 2 million input tokens. HTTP/measurement failures
stop the run and remain in `raw-results.json`; unsuccessful task receipts also
remain in the data. Arm order alternates across trials and catalog sizes.

The resulting report records token-count availability separately from attribution
coverage and retains raw accounting flags. See its methodology before drawing
latency, cache, or monetary conclusions.
