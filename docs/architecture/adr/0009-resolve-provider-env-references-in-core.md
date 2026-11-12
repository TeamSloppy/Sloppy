# Resolve provider ENV references in Core

- Status: accepted
- Date: 2026-11-12

## Context

OpenAI-compatible gateways can require custom tokens such as `ELIZA_TOKEN`.
Pasting a token into provider settings stores that secret in configuration;
passing `$ELIZA_TOKEN` previously sent the reference itself as the bearer token.
The browser/client may connect to a remote Core with a different environment.

## Decision

Resolve whole-value `$NAME` and `${NAME}` references in Core, through a shared
resolver for OpenAI API runtime construction, connection probes and model catalogs.
Keep the reference in configuration. Existing literal keys and empty-key fallback
to `OPENAI_API_KEY` retain their priority rules. Resolve only the selected value;
a request-level key overrides the saved key.

An explicit missing, empty or malformed reference fails before transport, never
falling back to a different account or keyless LAN access. Probes/catalogs report
a diagnostic without the secret; runtime construction returns no API provider.
Do not run shell commands, interpolate strings, recursively expand variables or
introduce client-side environment lookup. Other provider types and OAuth are not
changed by this implementation.

## Consequences

Core's service/container environment must contain the variable; a shell export
in a separate terminal is insufficient. Restart Core after environment changes.
Runtime providers capture the resolved value at construction; probes/catalogs
resolve it per operation. No configuration schema or UI changes are required.
An API key beginning with `$` is now interpreted as a reference in this provider.

## Verification

`ProviderEnvironmentKeyTests` covers reference syntax, missing/empty values,
priority safety, config serialization and Authorization headers in probes,
model catalogs and a real SDK request with an isolated URLProtocol transport.
See [provider setup](../../guides/models.md#custom-env-references-for-openai-compatible-api-keys).
