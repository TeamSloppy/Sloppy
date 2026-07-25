# Sloppy v2 IP-chain inventory

This is a release-control record, not legal advice and not evidence of consent.

Repository history currently shows one external author whose contribution is
still present in AGPL-default v2 paths:

| Contributor | Commits | Surviving paths observed by blame |
| --- | --- | --- |
| `vmityuklyaev` | `c643be68`, `9a6dd694` | `Sources/sloppy/GitWorktreeService.swift`, `Dashboard/src/features/onboarding/OnboardingView.tsx` |

Those commits were originally accepted under MIT. Before the v2 license
transition is released, obtain and archive the contributor's explicit
permission for both AGPL publication and commercial relicensing using the
[consent template](relicensing-consent-template.md) or counsel-approved
equivalent.

Re-run this inventory against the release commit:

```console
git shortlog -sne v1.3.1..HEAD
git blame -- Sources/sloppy Dashboard
```

The release owner must reconcile any additional external author with a CLA or
specific consent record. Do not check signatures, private addresses, or
contract records into the public repository.
