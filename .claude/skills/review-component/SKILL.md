---
name: review-component
description: Review a pull request or a local change to Bicep components — run the checks CI runs, then judge what they can't. Use before opening a pull request, or when asked to review one.
---

# Review a component change

## 1. Run what CI runs

```bash
scripts/check-versions.sh
scripts/build.sh
scripts/update-readme.sh --check
scripts/check-snapshots.sh
```

A failure here is the answer: report it with the script's message. Don't review further until
they pass, and don't fix a check by changing the script.

## 2. Judge what CI can't

- **Bump size.** Does the version step match the change (`bump-version` table)? A removed
  parameter in a minor bump passes CI and breaks a consumer.
- **Snapshot diff.** Read every changed `*.snapshot.json`. Is each changed resource meant to
  change? A rename means a delete and a create; a moved resource means a new stack owner.
- **Ownership.** Does a solution create something another stack already owns? It should be
  referenced, not redeployed. Would `actionOnUnmanage: deleteAll` delete something still in
  use when this stack drops it? Stacks that hold management groups or subscription placements
  stay on `detachAll` in `platform.json`.
- **Order.** Does a `02-workloads` solution depend on another workload, or a `01-core` one on
  something a later number creates? `rebuild.yml` deploys in folder order.
- **Descriptions.** Would someone choose the right value from the README alone?
- **Consumers.** Which configurations pick up the change now, and which stay behind? Is that
  intended?

## 3. Report

One line per finding: file, what is wrong, what to do. Separate what blocks the merge from what
is a suggestion. Say which checks you ran.
