---
name: bump-version
description: Choose and apply the version bump for a changed component, and bump every consumer that should pick it up. Use whenever a .bicep file under types/, modules/ or solutions/ changes, or when check-versions.sh says "already released".
---

# Bump a version

A released version never changes. A changed component gets a new version, in three places
that must agree: `metadata.json`, `metadata version` in `main.bicep`, the top of `CHANGELOG.md`.

## Which bump

| Change | Bump |
|---|---|
| Fix, refactor, description, new output, pin bump of a dependency | patch |
| New optional parameter, new resource, a changed default value | minor |
| Removed or renamed parameter, a new required parameter, anything that recreates a resource | major |
| A new component | starts at `1.0.0` |

When unsure between two, take the higher one and say why in the changelog.

## Steps

1. Find the newest release: `git tag -l '<component>/v*' --sort=-v:refname | head -1`.
   Bump from that, not from a version that only exists on another branch.
2. Write the new version into `metadata.json` and `metadata version`.
3. Add a changelog entry on top, today's date in ISO format:

   ```markdown
   ## 1.2.0 - 2026-10-20

   Features:
   - What changed, for someone who uses the component.
   ```

   Headings: `Features:`, `Fixes:`, `Breaking:` (a major bump always has `Breaking:` with the
   migration step).
4. Consumers: nothing updates on its own. For each component that should get the change,
   raise its pin (`br/platform:<path>:v1.2.0`) and bump that consumer too, a patch unless the
   change reaches its own parameters. Repeat up to the configurations that should deploy it.
   A configuration may stay on an older released version, for example prod one step behind dev.
5. Regenerate: `scripts/update-readme.sh` and `scripts/check-snapshots.sh --update`.
6. Check: `scripts/check-versions.sh`.
