# ACP SDK Parsing Comparison

This document compares inbound JSON-RPC parsing behavior across SDK references tracked in `reference/`.

## Scope

- Swift: `Sources/ACP/Internal/ProcessManager.swift`, `Sources/ACPModel/Message.swift`
- Rust: `reference/rust-sdk/src/agent-client-protocol/src/rpc.rs`
- TypeScript: `reference/typescript-sdk/src/stream.ts`, `reference/typescript-sdk/src/acp.ts`
- Python: `reference/python-sdk/src/acp/connection.py`
- Kotlin: `reference/kotlin-sdk/acp-model/src/commonMain/kotlin/com/agentclientprotocol/rpc/JsonRpc.kt`, `reference/kotlin-sdk/acp/src/commonMain/kotlin/com/agentclientprotocol/transport/StdioTransport.kt`

## Behavior Matrix

| Case | Swift (current) | Rust SDK | TypeScript SDK | Python SDK | Kotlin SDK |
|---|---|---|---|---|---|
| NDJSON line framing | Yes | Yes | Yes | Yes | Yes |
| Invalid JSON line | Drop line and continue | Drop line and continue | Drop line and continue | Drop line and continue | Drop line and continue |
| Non-JSON prefix + JSON same line | Recover and parse JSON | Drop line | Drop line | Drop line | Recover and parse JSON |
| `method` + `id: null` | Interpreted as notification | Interpreted as notification | Interpreted as request | Interpreted as request | Parse failure (drop line) |
| `method` + invalid `id` type (object) | Interpreted as notification | Parse failure (drop line) | Interpreted as request | Interpreted as request | Parse failure (drop line) |
| Default request timeout | None (opt-in only) | None in core RPC | None in core connection | None in core connection | None in transport parser |

## Evidence

### Swift

- Prefix recovery and malformed-line skip:
  - `Sources/ACP/Internal/ProcessManager.swift:343`
  - `Sources/ACP/Internal/ProcessManager.swift:410`
  - `Sources/ACP/Internal/ProcessManager.swift:418`
- `method + id` fallback to notification when request decode fails:
  - `Sources/ACPModel/Message.swift:25`
- No default request timeout:
  - `Sources/ACP/Client.swift:130`
  - `Sources/ACP/Client.swift:409`

### Rust SDK

- Reads newline-delimited input and parses each line:
  - `reference/rust-sdk/src/agent-client-protocol/src/rpc.rs:179`
  - `reference/rust-sdk/src/agent-client-protocol/src/rpc.rs:185`
- Parse failures logged and skipped:
  - `reference/rust-sdk/src/agent-client-protocol/src/rpc.rs:245`
- Notification branch when `id` is absent:
  - `reference/rust-sdk/src/agent-client-protocol/src/rpc.rs:229`

### TypeScript SDK

- Parses each trimmed line via `JSON.parse`; invalid lines are logged/skipped:
  - `reference/typescript-sdk/src/stream.ts:50`
  - `reference/typescript-sdk/src/stream.ts:54`
- Message classification by key presence (`"method"` and `"id"`):
  - `reference/typescript-sdk/src/acp.ts:977`

### Python SDK

- Reads line-by-line and `json.loads` each line; parse errors skipped:
  - `reference/python-sdk/src/acp/connection.py:151`
  - `reference/python-sdk/src/acp/connection.py:155`
- Message classification by `method` and key presence of `id`:
  - `reference/python-sdk/src/acp/connection.py:164`
  - `reference/python-sdk/src/acp/connection.py:167`

### Kotlin SDK

- Reads line-by-line; decode failures skipped:
  - `reference/kotlin-sdk/acp/src/commonMain/kotlin/com/agentclientprotocol/transport/StdioTransport.kt:45`
  - `reference/kotlin-sdk/acp/src/commonMain/kotlin/com/agentclientprotocol/transport/StdioTransport.kt:60`
- Prefix recovery by scanning first `{`:
  - `reference/kotlin-sdk/acp-model/src/commonMain/kotlin/com/agentclientprotocol/rpc/JsonRpc.kt:209`
  - `reference/kotlin-sdk/acp-model/src/commonMain/kotlin/com/agentclientprotocol/rpc/JsonRpc.kt:213`
- Request ID serializer accepts only int/string (no null/object):
  - `reference/kotlin-sdk/acp-model/src/commonMain/kotlin/com/agentclientprotocol/rpc/JsonRpc.kt:74`
  - `reference/kotlin-sdk/acp-model/src/commonMain/kotlin/com/agentclientprotocol/rpc/JsonRpc.kt:90`

## Practical Guidance

- Keep transport-level resilience (line-level skip and optional prefix recovery) to avoid hangs from noisy stdout.
- Decide protocol strictness policy explicitly:
  - Strict policy: drop malformed `id` messages.
  - Lenient policy: reinterpret malformed `id` messages as notifications.
- If strict cross-SDK consistency is the target, Rust + Kotlin are the conservative baseline for malformed `id`.
