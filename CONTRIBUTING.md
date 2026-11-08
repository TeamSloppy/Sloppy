# Contributing to Sloppy

Thank you for contributing.

Use the same [contributor workflow](docs/designs/contributor-workflow.md) as coding agents.
The [validation guide](docs/guides/contributor-validation.md) covers environment setup, commands,
Git hooks, report statuses, TDD evidence and independent review. Start by inspecting the proposed
checks with `python scripts/check_contribution.py plan --base origin/main`.

New features require an English design presented to and approved by the human before implementation.
Improvements update the affected design; fixes within an existing contract use the shorter bug flow.
After approval, implementation, scripted validation and separate-agent review proceed without
additional routine approval requests. Existing authorization remains valid.

All features include a discoverable user guide or a substantial update to an existing article;
public improvements update their guides. ADRs and design documents do not replace usage documentation.

Before an external contribution can be merged, the contributor must accept the
current [Contributor License Agreement](CLA.md) through the acceptance process
published by the maintainers. A pull request checkbox or a `Signed-off-by`
trailer does not replace the CLA.

Contributions must:

- follow the repository guidance in `AGENTS.md`;
- include focused tests for behavioral changes;
- preserve third-party copyright and license notices;
- identify copied or generated third-party material and its license;
- pass the narrow relevant test target and applicable CI checks.

By default, accepted contributions are published under the license assigned to
their path by [`LICENSES/README.md`](LICENSES/README.md). The CLA also permits
the project copyright holder to offer commercial licensing.

Security vulnerabilities should not be filed as public issues. Contact the
maintainers privately through the security channel published in the GitHub
repository.
