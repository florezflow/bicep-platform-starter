# AGENTS.md

Bicep for an Azure landing zone, released like packages: every component has one version, every
consumer pins an exact version, every configuration deploys as one deployment stack.
`CLAUDE.md` points here.

## Layout

- `types/` shared types and naming functions (`@export()` only) · `modules/` one resource or a
  small composite · `solutions/<tier>-<NNN>-<name>/` one lifecycle, deployed per environment
  from `configurations/<env>.bicepparam`
- Tiers, deployed in this order: `00-init` (once, by an admin, before the pipeline can run),
  `01-core` (management groups, then the platform), `02-workloads` (one per application)
- `platform.json` decides where each configuration deploys (subscription or management group),
  its `actionOnUnmanage` and whether what-if can preview it. Subscription IDs live only there.
- Each component: `main.bicep`, `metadata.json`, `CHANGELOG.md`, generated `README.md`
- `scripts/` every check CI runs, in Bash; `scripts/tests/run.sh` tests them

## Rules

1. Other components only by registry reference, `br/platform:<path>:vX.Y.Z`, exact version.
   `00-init` solutions are the exception: self-contained, `using '../main.bicep'`, no registry.
2. A change to a released component needs a version bump: use the `bump-version` skill.
3. Never edit generated files: component `README.md` (`scripts/update-readme.sh`) and
   `*.snapshot.json` (`scripts/check-snapshots.sh --update`). Review their diff instead.
4. Never deploy, publish or delete in Azure. Preview and deploy run in GitHub Actions, after
   approval. The bootstrap only as `solutions/00-init-000-bootstrap/bootstrap.sh --dry-run --repo …`.
5. A red check is information. Don't loosen a rule, add a suppression or skip a check to pass.

## Before you push

`scripts/check-versions.sh && scripts/build.sh && scripts/update-readme.sh --check && scripts/check-snapshots.sh`

Conventions for writing Bicep: the `bicep-conventions` skill. Reviewing a change: `review-component`.
