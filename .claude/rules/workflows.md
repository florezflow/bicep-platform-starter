---
paths:
  - ".github/workflows/**"
  - ".github/actions/**"
  - "scripts/**"
---

<!-- SKILL-CANARY: workflows/v1 -->
Workflows stay thin: the logic lives in `scripts/`, so a check runs the same locally and in CI.
Keep scripts Bash 3.2 compatible (macOS) and shellcheck-clean, pin actions to a commit SHA with
the version as a comment, and add a test under `scripts/tests/` for every new rule.
