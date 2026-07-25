# Sloppy License 1.0 — counsel-review draft

> **DRAFT — NOT AN OFFER OR A LICENSE GRANT.** This document becomes effective
> only when incorporated into an Order Form signed by the Licensor and
> Customer. It must be reviewed by qualified counsel before use.

## 1. Parties and scope

"Licensor", "Customer", the licensed legal entities, and any permitted
affiliates are identified in the Order Form. "Software" means the Sloppy core
software and proprietary Sloppy Enterprise modules identified there, including
updates made available during the Updates Term.

Subject to payment and compliance with this Agreement, Licensor grants Customer
a non-exclusive, non-transferable license to install, run, reproduce for
backup, and internally modify the Software for Customer's internal business
operations.

## 2. Licensed deployment

Unless the Order Form says otherwise, the license covers:

- one production Sloppy control plane;
- up to the stated number of active human users;
- reasonable development, test, staging, backup, and disaster-recovery
  installations used only in support of that production control plane; and
- unlimited agents, worker nodes, tasks, tools, and model tokens.

An "active human user" is a natural person whose account is enabled to access
the production control plane. Service accounts, agents, and worker identities
do not consume human-user capacity.

## 3. Affiliates

Only affiliates explicitly named in the Order Form may use the Software. The
Customer remains responsible for each permitted affiliate's compliance.

## 4. Restrictions

Customer may not, without a separate written addendum:

- redistribute, sublicense, sell, rent, lease, or otherwise provide the
  Software to a third party;
- operate the Software as a hosted, managed, bureau, or time-sharing service
  for third parties;
- embed or bundle the Software in an OEM product; or
- remove copyright, attribution, license, or proprietary notices.

These restrictions do not limit rights that Customer receives independently
under an applicable open-source license for separately identified components.

## 5. Updates, support, and perpetual fallback

The Order Form specifies an `updatesUntil` date. Customer may use indefinitely
each Software version that Licensor released to Customer on or before that
date, subject to this Agreement. Versions first released after `updatesUntil`,
and support or maintenance after the stated term, require renewal or another
written agreement.

Expiration of the Updates Term must not remotely disable an already licensed
version. User-capacity enforcement may prevent activation of additional human
users but must not lock out existing licensed users. A missing, invalid, or
mismatched Enterprise entitlement may prevent proprietary Enterprise modules
from loading; it must not disable Sloppy Community.

## 6. Fees and verification

Fees, payment schedule, taxes, user capacity, support, and deployment terms are
stated only in the Order Form. On reasonable written notice, Customer will
provide records sufficient to confirm production control-plane and active-user
counts, no more than once per year unless a material discrepancy is found.

## 7. Ownership and feedback

Licensor and its suppliers retain all rights in the Software not expressly
granted. Customer retains ownership of its data and of modifications authored
solely by Customer, while those modifications may be used only with the
Software under this Agreement. Any license to feedback must be stated in the
Order Form.

## 8. Confidentiality and security

Confidentiality, security commitments, data processing, and incident-notice
terms are governed by the Order Form or an attached agreement. Customer must
not place credentials or secrets in support materials.

## 9. Warranty, liability, indemnity, and law

Warranty, disclaimers, indemnities, limitation of liability, governing law,
venue, export controls, sanctions, assignment, termination, cure periods, and
survival must be completed in the signed Order Form or master agreement after
legal and tax review. No public draft supplies those terms.

## 10. Open-source alternative

Sloppy Community components remain available under their published
open-source licenses. For components offered under both AGPL and commercial
terms, Customer may choose the commercial rights in this Agreement instead of
the AGPL obligations for the licensed deployment. The repository license map
identifies MIT-licensed SDK and client components.
