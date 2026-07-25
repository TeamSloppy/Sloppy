# Sloppy v2 licensing release gate

The following are release prerequisites, not claims of completion:

- [ ] Obtain and archive written relicensing consent from every external
      contributor whose code is present in Sloppy v2.
- [ ] Reconcile the current
      [IP-chain inventory](ip-chain-inventory.md) against the release commit.
- [ ] Have counsel approve Sloppy License 1.0, the CLA, IP chain, governing
      law, warranty, indemnity, and limitation-of-liability terms.
- [ ] Select a CLA signature/acceptance service and make its records
      auditable.
- [ ] Confirm the initial individual Licensor's authority, tax treatment, and
      a future contract/IP assignment path to a company.
- [ ] Run the dependency-license inventory and preserve every third-party
      notice in source and binary distributions.
- [ ] Verify the release archive contains AGPL, MIT, the license map, and the
      source offer.
- [ ] Verify the matching Git tag and source archive are public before
      publishing binaries.
- [ ] Confirm `v1.3.1` remains available with its original MIT license.
- [ ] After the consent and counsel records are archived, set the GitHub
      repository variable `SLOPPY_V2_LEGAL_APPROVED=true`; the release workflow
      blocks all `v2+` publication until this explicit gate is opened.
