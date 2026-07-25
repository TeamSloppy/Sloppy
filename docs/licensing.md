# Licensing

Sloppy v2 uses an open-core dual-licensing model.

## Sloppy Community

The Sloppy server, agent runtime, Dashboard, and SloppyNode are
`AGPL-3.0-only`. Community is free for individuals and companies of every
size—there is no revenue, net-worth, employee-count, seat, agent, task, node,
token, or model-usage threshold.

If you modify these components and let users interact with the modified
software over a network, AGPL section 13 requires offering those users the
Corresponding Source of the version they use. See the
[full AGPL text](https://github.com/TeamSloppy/Sloppy/blob/main/LICENSE) and
[source offer](https://github.com/TeamSloppy/Sloppy/blob/main/SOURCE_OFFER.md).

## MIT integration surfaces

The wire protocols, PluginSDK, SloppySDK, plugin examples, native client, and
the client computer-control package remain MIT licensed. This boundary lets
organizations build closed-source plugins and client applications without
placing those integrations under copyleft merely because they use the public
SDK.

The authoritative path list is the
[repository license map](https://github.com/TeamSloppy/Sloppy/blob/main/LICENSES/README.md).
Third-party dependencies retain their own licenses.

## Sloppy Enterprise

Sloppy Enterprise is a privately delivered commercial package for internal
agent control planes. A signed Sloppy License and Order Form permit the named
customer and approved affiliates to use Sloppy core without AGPL obligations
for the licensed deployment.

The intended unit is one production control plane and an agreed number of
active human users, with development/test installations and unlimited agents,
worker nodes, tasks, tools, and tokens included. Redistribution, OEM embedding,
or providing Sloppy to third parties as a service needs a separate agreement.

Enterprise entitlements use a perpetual fallback: a customer may continue
running versions released through its `updatesUntil` date; renewal is required
for newer releases and continuing support. Enterprise pricing belongs in the
Order Form, not in the license text. [Contact sales](https://sloppy.team/).

## Earlier versions

`v1.3.1` is the final MIT release. Copies of `v1.3.1` and earlier keep the MIT
rights granted with them permanently. The v2 license transition is not
retroactive.

This page describes the product model and is not legal advice.
