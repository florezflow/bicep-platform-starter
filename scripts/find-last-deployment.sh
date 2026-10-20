#!/usr/bin/env bash
# Find the commit of a stack's last successful deployment to an environment.
# Reads the deployment records that record-deployment.sh writes to GitHub (task "stack:<name>").
#
# Prints "<sha> <action>" (action: deploy or retire), or nothing if the stack was never deployed.
# A record counts once it has any success status: later deployments set older ones to inactive.
#
# Usage: scripts/find-last-deployment.sh <environment> <stack>
#   needs GITHUB_REPOSITORY and GH_TOKEN; tests set FIXTURES=<dir> to read JSON files instead
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

env=${1:?usage: find-last-deployment.sh <environment> <stack>}
stack=${2:?usage: find-last-deployment.sh <environment> <stack>}

deployments() { # newest first, one JSON object per line
  if [ -n "${FIXTURES:-}" ]; then
    jq -c --arg e "$env" --arg t "stack:$stack" '.[] | select(.environment == $e and .task == $t)' "$FIXTURES/deployments.json"
  else
    gh api --paginate "repos/$GITHUB_REPOSITORY/deployments?environment=$env&task=stack:$stack&per_page=100" --jq '.[] | tojson'
  fi
}

states() { # every status state of one deployment
  if [ -n "${FIXTURES:-}" ]; then
    jq -r '.[].state' "$FIXTURES/statuses-$1.json" 2>/dev/null || true
  else
    gh api --paginate "repos/$GITHUB_REPOSITORY/deployments/$1/statuses?per_page=100" --jq '.[].state'
  fi
}

while IFS= read -r deployment; do
  [ -n "$deployment" ] || continue
  id=$(jq -r '.id' <<< "$deployment")
  sha=$(jq -r '.sha' <<< "$deployment")
  action=$(jq -r '.payload.action // "deploy"' <<< "$deployment")
  if ! states "$id" | grep -qx success; then continue; fi
  if ! git -C "$ROOT" cat-file -e "$sha^{commit}" 2>/dev/null; then
    echo "deployment $id points at $sha, which isn't in this history; trying an older one" >&2
    continue
  fi
  echo "$sha $action"
  exit 0
done <<< "$(deployments)"
