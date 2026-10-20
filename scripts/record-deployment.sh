#!/usr/bin/env bash
# Record a successful stack deployment (or retirement) on GitHub, so find-last-deployment.sh can
# compare the next deployment against this commit. Shows up under the repo's Deployments.
#
# Usage: scripts/record-deployment.sh <environment> <stack> <deploy|retire> [log-url]
#   needs GITHUB_REPOSITORY, GITHUB_SHA and GH_TOKEN with deployments: write
set -euo pipefail

env=${1:?usage: record-deployment.sh <environment> <stack> <deploy|retire> [log-url]}
stack=${2:?}
action=${3:?}
log_url=${4:-}

# required_contexts: [] because the commit was already checked before it reached main
id=$(jq -n --arg ref "$GITHUB_SHA" --arg env "$env" --arg task "stack:$stack" --arg action "$action" \
  '{ref: $ref, environment: $env, task: $task, auto_merge: false, required_contexts: [],
    payload: {action: $action}, description: "\($action) stack \($task | ltrimstr("stack:"))"}' \
  | gh api --method POST "repos/$GITHUB_REPOSITORY/deployments" --input - --jq '.id')

jq -n --arg url "$log_url" '{state: "success", log_url: $url, auto_inactive: false}' \
  | gh api --method POST "repos/$GITHUB_REPOSITORY/deployments/$id/statuses" --input - --silent

echo "recorded $action of $stack in $env as deployment $id ($GITHUB_SHA)"
