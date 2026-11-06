# Native loop ownership and artifact closure

User authorization: 2026-11-06 response annotation 1: finish the five listed implementation limitations.
Independent review remains deferred; no commit, publication or destructive migration is requested.

1. Exclusive storage/session ownership and callback reentry: production host and approval tests,
   crash-safe lock lifetime, rejection before effects, original FIFO preserved.
2. Complete artifact persistence, bounded validated reads/export and reference-aware orphan cleanup:
   actual filesystem/journal tests including >25 MiB, corruption and protected authority.
3. Embedded artifact presentation/API integration with usage fixtures and guide.
4. Supported-native owner consolidation, compatibility adapters, owning and downstream tests.
5. Final source-refreshed owning suites, docs build, code-stage diagnostics and issue-register update.

Each slice retains actual Red/Green evidence where applicable. Do not remove compatibility API tests
or claim unavailable Apple/live/release validation. Keep other worktree changes intact.


Implementation delivered:

- FileOwnershipLease provides exclusive OS ownership; shared weak authority tokens fence retained
  Core stores. Core stop joins inbox workers, and actual late writes keep the original lease alive.
- Embedded callbacks reject inherited-context reentry; cross-host/session contention fails before input
  admission. Legacy selector APIs forward to the common native owner and eligible history imports as
  non-authoritative context, leaving original bytes intact.
- Artifact schema 2 externalizes complete data/error payloads; Core profile 8 and embedded marker 4
  guard writers. Verified bounded reads, pull streaming, export, old orphan cleanup and embedded
  transcript/UI integration are implemented.
- Native generation scheduling, reconnect, fallback and context-reset owners were consolidated into
  AgentLoop. The old AnyLanguageModel public generation APIs remain. Native third-party integrations
  require the single-step capability. Actual frame context-ledger diagnostics were restored with Red/Green.

Validation and remaining failures are recorded in native-agent-loop-issues.md. Review remains deferred.
No commit or publication was performed. The quick code stage is a content check, not complete CI parity.
