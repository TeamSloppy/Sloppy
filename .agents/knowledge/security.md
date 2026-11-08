# Security boundaries

Provider credentials, OAuth tokens, channel secrets, MCP environment values and local
configuration must not enter source or public logs. The runner invokes detect-secrets
locally with online verification disabled and prints finding locations/types without values.
Heuristic scanning is useful evidence, not proof that every secret has been found.

An exception in `.agents/secret-exceptions.json` must name the exact path, detector type,
fingerprint and reviewed reason. Never suppress a whole directory to hide one finding.
Preserve approval/pre-hook checks in agent tools and typed validation at HTTP boundaries.

For tool/process execution, inspect argv handling, working directory/path boundaries,
approval context and cancellation. For persistence, exercise invalid input and transactional
failure. For auth, inspect the existing local-owner/remote-access contract and realistic
unauthorized requests. Reuse regression tests and browser/runtime scenarios that reach
the real boundary; a unit suite alone is not DAST.

Changed Python tooling dependencies use pip-audit. Other changed dependency graphs require
an explicit advisory-review command whose scope and provenance the reviewer can assess.
License checks and dependency resolution do not replace vulnerability analysis.

Imported AdaEngine orchestration, fixtures and skills retain the MIT notice in
`LICENSES/AdaEngine-contribution-MIT.txt`; provenance is recorded in `THIRD_PARTY_NOTICES.md`.
