---
name: bicep-conventions
description: How Bicep is written in this repo — tiers, naming, sections, descriptions, shared types, registry references, what a solution owns and what it only references. Use when writing or changing any .bicep or .bicepparam file.
---

# Bicep conventions

CI checks what it can compute (versions, pins, builds, linter, prefixes, READMEs, snapshots,
targets). This file covers what it can't: the choices a reviewer would otherwise make by hand.

## Where code goes

| Layer | Holds | Scope |
|---|---|---|
| `types/` | `@export()` types and naming functions, nothing deployable | none |
| `modules/<area>/<name>/` | one resource, or a few that never exist alone (`app-network`: subnet + NSG) | resource group |
| `modules/platform/<name>/` | one platform subscription's content: its resource group, network, workspace | subscription |
| `solutions/<tier>-<NNN>-<name>/` | one lifecycle: everything created and deleted together | subscription or management group |

A solution is one deployment stack per environment. Cut solutions along lifecycles: if two
things are deleted at different times, they are two solutions.

- `00-init-*`: runs before the registry and the pipeline exist. Self-contained, no `br/`
  references, `using '../main.bicep'`, deployed once by an admin. Not in `deploy.yml`.
- `01-core-*`: the landing zone. `000` creates the management groups and places the
  subscriptions (a management group stack at the tenant root group, `detachAll`: a group or a
  placement leaving the template must never delete it). `010` deploys the platform at the
  platform management group, one composite per subscription.
- `02-workloads-*`: one application in its own subscription, a subscription stack.

The number inside a tier is the deploy order. `rebuild.yml` deploys `01-core` one after the other
and `02-workloads` in parallel, so a workload never depends on another workload.

## Ownership across stacks

A resource another stack owns is referenced, never redeployed: pass its coordinates in a type
from `types/` (`hubVnetType`) and build its ID with `resourceId(...)`. A peering has two halves,
one on each network: the spoke's stack owns both (`scope: resourceGroup(hub.subscriptionId,
hub.resourceGroupName)` for the hub half), so retiring a workload removes its peering from the hub.

A virtual network never declares `subnets`: a PUT without them leaves existing subnets alone,
while `subnets: []` deletes them all. Subnets are their own module, owned by the stack that uses them.

## Naming

- Parameters `p`, variables `v`, resources `r`, modules `m`, outputs `o`, then PascalCase:
  `pContext`, `vPlatformGroups`, `rRg`, `mVnet`, `oSubnetId`. Types end in `Type`. CI checks these.
- Sections in this order, each as `// --- Name ---`: Types, Parameters, Variables, Resources,
  Modules, Outputs (imports at the top, without a heading)
- Resource names come from `resourceName()` in `types/`: `<abbreviation>-<name>-<env>-<region>-<nnn>`,
  for example `vnet-hub-prod-szn-001`. Abbreviations from the Cloud Adoption Framework (`rg`,
  `vnet`, `snet`, `nsg`, `log`, `cr`, `st`). Names Azure fixes stay as they are (`GatewaySubnet`).
- Management groups: `<root>-<group>`, for example `contoso-platform-identity`
- Tags lowercase: `workload`, `owner`

## Descriptions

The README is generated from them, so they are the documentation.

- Every parameter, output, type and type property has `@description`: one sentence on what it is
  for, not its type
- Examples go into `@metadata({ example: … })`, never into the description
- Never write the default, "Required", "Optional" or a badge: the generator adds them from the
  compiled template, and CI fails a description that has them

## Types

Use a type from `types/` before declaring one. A shape used by two components goes into
`types/` (a minor bump there, then the consumers bump their pin). Import only what you use:
`no-unused-imports` is an error. Every module takes `pContext contextType` for environment,
region and tags.

## References

- Another component: `br/platform:<path>:vX.Y.Z`, exact version, never a relative path
- A configuration: `using 'br/platform:solutions/<name>:vX.Y.Z'`, its own solution only; values
  from `platform.json` through `loadJsonContent('../../../platform.json')`
- To use a version you're changing in the same pull request, pin it anyway: CI builds it from
  the branch. Don't wait for a release.
- A new configuration needs a target in `platform.json` and a line in `deploy.yml`'s choices
