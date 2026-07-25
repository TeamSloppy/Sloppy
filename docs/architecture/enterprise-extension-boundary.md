# Enterprise extension boundary

Sloppy Community must build and run from the public repository with no private
dependency, entitlement file, registration, or network license check.

The MIT-licensed `PluginSDK/EnterpriseExtensions.swift` file is the stable seam
between public core and the separately delivered `SloppyEnterprise` package.
Public core accepts `[any EnterpriseModule]` at `CoreService` construction. An
empty array is the complete Community configuration.

## Startup contract

The Enterprise executable is responsible for this sequence:

1. Read the offline signed entitlement.
2. Verify its Ed25519 signature against an embedded public-key ring.
3. Verify customer/deployment identity, feature grants, human-user limit, and
   that the running core release date is on or before `updatesUntil`.
4. Construct and inject Enterprise modules only after validation succeeds.
5. Register module-owned OIDC authorization/callback routes on `CoreRouter`.

If validation fails, the process may continue as Community, but it must not
load proprietary Enterprise modules. There is no phone-home fallback.

## Public extension points

- `IdentityProvider` validates external bearer tokens and returns a Sloppy
  profile, provider ID, and groups. Built-in password authentication remains
  available for a protected break-glass admin.
- `AuthorizationPolicyProvider` evaluates typed
  `subject/action/resource/context` requests. Core applies all installed
  providers and fails closed on a provider error.
- `AuditSink` receives append-only, pre-redacted typed events and exports
  bounded JSONL data.
- `EnterpriseModule` publishes capabilities, providers, sinks, and Dashboard UI
  contributions.
- `EntitlementProvider` exposes only a verified `EntitlementSnapshot`; raw
  signed envelopes are never treated as authority by public core.

`GET /v1/system/edition` returns Community with empty capabilities when no
module is injected. For Enterprise, it returns module/capability/UI metadata
and a limited entitlement summary; it never returns a key or signature.

## Enforcement invariants

- Expiry does not turn off an already entitled version.
- `updatesUntil` controls version eligibility, not runtime uptime.
- Human-user capacity is checked only before activating another user.
- Agents, service identities, workers, nodes, tasks, tools, and tokens do not
  consume seats.
- OIDC failure does not remove the local break-glass admin path.
- Policy-provider errors deny the requested Enterprise-authorized action.
- Audit metadata must never contain authorization headers, cookies, passwords,
  provider tokens, API keys, raw entitlement payloads, or signatures.

## Private test contract

The private repository CI must build against an exact public core tag and
cover:

- valid Ed25519 signatures, modified payloads, modified signatures, unknown
  keys, and customer/deployment mismatch;
- releases before, exactly on, and after `updatesUntil`;
- seat activation below, at, and above the human-user limit;
- Entra ID, Okta, and Google Workspace OIDC discovery/callback flows;
- group-to-role mapping for Admin, Operator, Approver, Auditor, and Viewer;
- project/tool permission matrices and centralized approval rules;
- break-glass login during OIDC outage;
- JSONL export/retention and secret-redaction fixtures.

The private artifact version must record the exact public Sloppy core tag and
commit used to build it.
