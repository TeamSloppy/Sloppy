# AnyLanguageModel single-step API

Status: implementation authorized by the user's chat instruction on 2026-11-06.

AnyLanguageModel owns a declaration-only `LanguageModelStepProvider` capability and an
`HTTPModelStepProvider` implementation for Responses, Chat Completions, Anthropic,
Gemini (including Code Assist), and Ollama. One generation returns preview events,
tool call arguments, usage, a typed stop reason, and opaque provider continuation.
It never executes tools or automatically follows a tool call. Cancellation reaches
the network task; bounded framing and byte buffering remain enforced.

Requests contain messages, tool schemas, output options, request identity and cache
affinity. Sloppy's run IDs, projection revisions, approval/replay policy, recovery,
tool execution and persistence remain in Sloppy. PluginSDK translates those types
at the library boundary. Its historical codec entry points may remain thin adapters
for source compatibility, with no HTTP or provider parsing implementation.

Transport and codecs move into the vendored library. Credentials, proxy/trust
configuration and account headers are supplied by the host. OAuth's one credential
refresh on HTTP 401 is explicit configuration; it does not retry completed generations.
The existing LanguageModel/LanguageModelSession respond and streamResponse APIs
remain source compatible and retain their existing orchestration behavior.

Acceptance: all existing single-step contract tests pass; library tests exercise
one request returning a tool call without executing it, continuation, malformed
arguments, cancellation and failures; legacy API behavior remains tested. No new
framework or dependency on Sloppy is introduced into AnyLanguageModel. Independent
review is deferred at the user's explicit request. Known limitations go in a
separate issues file. Linux validation uses byte-identical source mirrors.
