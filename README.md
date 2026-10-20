# bicep-platform-starter

A small Azure landing zone in Bicep, released like packages. Every component has one version and
every consumer pins an exact one. A pull request builds versions that aren't published yet, and
each configuration deploys as one deployment stack: previewed, approved, recorded, and retired
when it's done.

The write-up with the reasoning behind each piece: [Run Bicep like packages: pinned versions, one stack per lifecycle](https://florezflow.com/enterprise-bicep/).

Everything a pull request checks runs offline, on your machine and in GitHub Actions. The Azure
steps (publish to a registry, what-if, deploy) are switched off until you set `AZURE_ENABLED`.
None of it has run against a real tenant yet: see [Not verified in Azure yet](#not-verified-in-azure-yet).

## The landing zone

Three tiers, deployed in this order. The folder name says which tier a solution is in and where
it goes in the order: `<tier>-<NNN>-<name>`.

| Solution | Deploys at | What |
|---|---|---|
| `00-init-000-bootstrap` | tenant | A script, run once: resource providers, Entra Domain Services prerequisites, the two identities GitHub Actions signs in as |
| `00-init-010-module-registry` | management subscription | The container registry everything else is published to. Self-contained, deployed once from source |
| `01-core-000-management-groups` | tenant root group | Deployment 1: the management group hierarchy and which subscription sits where |
| `01-core-010-platform` | `<root>-platform` | Deployment 2: the hub network, Entra Domain Services, the platform Log Analytics workspace, Microsoft Sentinel. One subscription each |
| `02-workloads-000-sample-app` | its own subscription | A spoke network peered with the hub, a subnet with its network security group, a storage account only that subnet reaches |

```text
Tenant root group
└── contoso                      (dev: contoso-canary, a second hierarchy to try changes on)
    ├── contoso-platform         ← 01-core-010-platform deploys here
    │   ├── -security            security subscription: Sentinel
    │   ├── -management          management subscription: Log Analytics, the registry
    │   ├── -connectivity        connectivity subscription: the hub
    │   └── -identity            identity subscription: Entra Domain Services
    ├── contoso-landingzones
    │   ├── -corp                sample-app subscription
    │   └── -online
    ├── contoso-sandbox
    └── contoso-decommissioned
```

Each environment, dev and prod, is a hierarchy of its own with its own subscriptions. Dev has
no Entra Domain Services: a tenant can have only one managed domain.

The two core deployments are separate stacks, not stages of one: the groups and placements live
for the life of the tenant (`detachAll`, nothing there is ever deleted by a stack), the platform
changes every month. Run one after the other, they rebuild an environment.

## What's in it

| Path | What |
|---|---|
| `types/` | Shared types and the naming functions: `vnet-hub-prod-szn-001` comes from `resourceName()` |
| `modules/network/*` | Virtual network (never declares subnets), subnet, network security group, app network (subnet + its NSG), peering (one direction), private DNS zone |
| `modules/{monitor,security,identity,storage}/*` | Log Analytics workspace, Sentinel, Entra Domain Services managed domain, storage account |
| `modules/platform/*` | What one platform subscription holds: connectivity, identity, management, security |
| `solutions/*/configurations/` | One `.bicepparam` per environment, and its committed `.snapshot.json` |
| `platform.json` | Tenant, subscriptions, the registry, and for each configuration where it deploys |
| `scripts/` | Every check, in Bash, with tests in `scripts/tests/` |
| `.github/workflows/` | `pr.yml` (checks), `publish.yml` (tags, registry), `deploy.yml` (one stack), `rebuild.yml` (one environment) |
| `AGENTS.md`, `.claude/`, `.github/instructions/` | The conventions, where Claude Code and GitHub Copilot load them |

Each component folder holds `main.bicep`, `metadata.json` (the version), `CHANGELOG.md` and a
`README.md` generated from the compiled template.

## Try it locally

You need Bash (3.2 is enough), git, jq and the [Bicep CLI](https://learn.microsoft.com/azure/azure-resource-manager/bicep/install)
in the version `platform.json` pins (`bicepVersion`), or later. No Azure account.

```bash
git clone https://github.com/florezflow/bicep-platform-starter && cd bicep-platform-starter
scripts/check-versions.sh          # versions agree, released versions unchanged, targets valid
scripts/build.sh                   # every template and config builds against local files
scripts/update-readme.sh --check   # READMEs match the templates
scripts/check-snapshots.sh         # snapshots match what the configs deploy
scripts/tests/run.sh               # the scripts' own tests
```

Then break something and watch the right check fail:

- Change `modules/network/nsg/main.bicep` after a release tag exists → `check-versions.sh`: already released, bump the version
- Pin a version that doesn't exist → `convert-registry-refs.sh`: neither the version on this branch nor a released tag
- Rename a parameter `pName` to `name` → `update-readme.sh --check`: needs the prefix p
- Put `Example: …` into a `@description` → `update-readme.sh --check`: use `@metadata({ example: … })`
- Change an address range in a `.bicepparam` → `check-snapshots.sh`: out of date
- Add a folder `solutions/03-apps-000-x` → `check-versions.sh`: solution folders are named `<tier>-<NNN>-<name>`

## How a change travels

1. **Pull request.** Bump the component, pin the new version in its consumers, regenerate READMEs
   and snapshots. CI points every registry reference at local files (the branch, or a release tag
   for older pins), so the whole chain builds in one pull request. The one required check is `gate`.
2. **Merge.** `publish.yml` tags every new version as `<component>/v<version>`. With Azure on, it
   also publishes each one to the registry and locks it against changes. Init solutions are
   tagged, never published.
3. **Deploy.** Run `deploy.yml` from `main`, pick a configuration. It shows what changed since
   that stack's last successful deployment, then what-if and stack what-if, then waits for an
   approval on the environment. After the deployment it records the commit for next time.
   `retire` deletes the stack and, as `platform.json` says, what it manages.

## Rebuild an environment

`rebuild.yml` deploys every configuration of one environment through `deploy.yml`: the `01-core`
solutions one after the other in folder order, then all `02-workloads` in parallel. Each step has
its own preview and approval. It's the same chain for a new environment, an environment rebuilt
after a disaster, or bringing everything up to date. Init solutions aren't part of it.

## Turn on Azure

You need a Global Administrator with
[elevated access](https://learn.microsoft.com/azure/role-based-access-control/elevate-access-global-admin)
for the first step, and the subscriptions already created.

1. Put your tenant, subscriptions and a registry name of your own into `platform.json`
   (registry names are global), and the same registry into `bicepconfig.json`. Pick your own
   managed domain name in `solutions/01-core-010-platform/configurations/prod.bicepparam`.
2. Bootstrap: `solutions/00-init-000-bootstrap/bootstrap.sh --dry-run --repo <owner>/<repo> --github`,
   read what it would do, then run it without `--dry-run`. Commit the IDs it writes into `platform.json`.
3. Add required reviewers and the deployment branch `main` to the environments `dev` and `prod`.
4. Deploy the registry, once, as the admin: `scripts/deploy-stack.sh 00-init-010-module-registry/prod deploy`.
5. `gh variable set AZURE_ENABLED --body true`, then run `publish.yml` once by hand.
6. Run `rebuild.yml` for dev, then for prod.

## platform.json

| Key | What |
|---|---|
| `bicepVersion`, `bicepSha256` | The Bicep CLI CI installs and checks |
| `tenantId`, `location` | Where everything deploys |
| `registry.name`, `registry.config` | The registry, and the configuration that deploys it (its subscription is that configuration's target) |
| `identities` | Principal IDs of the deployer (AcrPush) and the previewer (AcrPull) |
| `environments.<env>.subscriptions` | Subscription IDs by role. Configurations read them with `loadJsonContent` |
| `solutions.<name>.targets.<env>` | Where a configuration deploys: `{ "subscription": "<role>" }`, `{ "managementGroup": "<id>" }` or `{ "tenantRootGroup": true }` |
| `solutions.<name>.actionOnUnmanage` | `deleteAll` (default), `deleteResources` or `detachAll` |
| `solutions.<name>.denySettingsMode` | `none` (default), `denyDelete` or `denyWriteAndDelete` |
| `solutions.<name>.whatIf` | `false` when what-if can't preview it (groups that don't exist yet); the snapshot diff is the preview then |

Stacks are named `<solution>-<environment>`: the dev and prod management group stacks both live
at the tenant root group.

## Protect the releases

- A tag ruleset on `types/**`, `modules/**` and `solutions/**`: creation allowed, update and
  deletion blocked. A released version then stays what it was.
- A branch ruleset on `main`: pull request required, status check `gate` required.

## Not verified in Azure yet

The offline checks and the scripts' tests pass; these need a first run in a real tenant:

- A management group stack deploying into subscriptions two levels below it (the platform).
  Fallback: one subscription stack per platform subscription, with the same composites.
- A subscription stack creating the hub half of a peering in another subscription.
- Whether Reader is enough for stack what-if, which stores its result as a resource.
- Hub peerings surviving a redeployment of the hub network.
- What-if at management group scope once the groups exist.

## License

[MIT](LICENSE)
