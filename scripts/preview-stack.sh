#!/usr/bin/env bash
# Show what a deployment would do, before anyone approves it. Two views, because they answer
# different questions:
#   az deployment <sub|mg> what-if   which properties change on the resources in the template
#   az stack-whatif <sub|mg> create  what the stack does to everything it manages, including the
#                                    resources it would delete or detach because they left the template
# Both run with --validation-level ProviderNoRbac, so a read-only identity can preview.
# Scope, target, actionOnUnmanage and deny settings come from platform.json, as in deploy-stack.sh.
# A solution with "whatIf": false (management groups that don't exist yet) is previewed by its
# snapshot diff only.
#
# Usage: scripts/preview-stack.sh <solution>/<environment> <deploy|retire>
#   needs az, logged in with read access to the stack's scope
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

usage="usage: preview-stack.sh <solution>/<environment> <deploy|retire>"
stack_context "${1:?$usage}"
action=${2:?$usage}
case "$action" in deploy|retire) ;; *) echo "$usage" >&2; exit 2 ;; esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
plain() { sed $'s/\x1b\\[[0-9;]*m//g'; }
where="$SCOPE_FLAG $TARGET_ID"

exists=false
if az stack "$SCOPE" show --name "$STACK_NAME" "$SCOPE_FLAG" "$TARGET_ID" --output none --only-show-errors 2>/dev/null; then
  exists=true
fi

summary "### Preview: \`$STACK_NAME\` at $where ($action, actionOnUnmanage $UNMANAGE)"

if [ "$action" = retire ]; then
  if ! $exists; then
    echo "Stack $STACK_NAME doesn't exist at $where: nothing to retire."
    summary "Stack \`$STACK_NAME\` doesn't exist: nothing to retire."
    exit 0
  fi
  verb="delete"
  case "$UNMANAGE" in detachAll) verb="detach (they stay, unmanaged)" ;; deleteResources) verb="delete (resource groups and management groups stay)" ;; esac
  echo "Retiring $STACK_NAME would $verb:"
  az stack "$SCOPE" show --name "$STACK_NAME" "$SCOPE_FLAG" "$TARGET_ID" --query "resources[].id" --output tsv | tee "$work/resources.txt"
  summary "Retiring the stack would $verb these resources:"
  summary ""
  while IFS= read -r id; do summary "- \`$id\`"; done < "$work/resources.txt"
  exit 0
fi

if [ "$WHATIF" = false ]; then
  echo "platform.json sets whatIf: false for $SOLUTION: what-if can't preview resources whose parents don't exist yet."
  echo "The preview is the snapshot diff since the last successful deployment (scripts/check-snapshots.sh --against)."
  summary "What-if is off for \`$SOLUTION\` (platform.json): the snapshot diff since the last successful deployment is the preview."
  exit 0
fi

echo "== Deployment what-if"
az deployment "$SCOPE" what-if --name "$STACK_NAME" --location "$LOCATION" "$SCOPE_FLAG" "$TARGET_ID" \
  --parameters "$ROOT/$PARAMS" --validation-level ProviderNoRbac --no-prompt --only-show-errors \
  | plain | tee "$work/whatif.txt"
summary "<details><summary>Deployment what-if</summary>"
summary ""
summary '```'
summary "$(cat "$work/whatif.txt")"
summary '```'
summary "</details>"
summary ""

echo "== Stack what-if"
if ! $exists; then
  echo "First deployment of $STACK_NAME: nothing to delete or detach yet."
  summary "First deployment of \`$STACK_NAME\`: the stack has nothing to delete or detach yet."
  exit 0
fi
# The same actionOnUnmanage and deny settings as the deployment, or the preview shows another outcome
# The result is kept as a resource for 1 to 3 hours, no longer: Azure refuses anything else
az stack-whatif "$SCOPE" create --name "$STACK_NAME" --stack-id "$STACK_ID" --location "$LOCATION" \
  "$SCOPE_FLAG" "$TARGET_ID" --parameters "$ROOT/$PARAMS" \
  --action-on-unmanage "$UNMANAGE" --deny-settings-mode "$DENY_MODE" \
  --retention-interval PT3H --validation-level ProviderNoRbac \
  --no-pretty-print --output json --only-show-errors > "$work/stack.json"

jq -r '.properties.changes.resourceChanges // [] | group_by(.changeType)[] | "\(.[0].changeType): \(length)"' "$work/stack.json"
summary "| Change | Resources |"
summary "|---|---|"
summary "$(jq -r '.properties.changes.resourceChanges // [] | group_by(.changeType)[] | "| \(.[0].changeType) | \(length) |"' "$work/stack.json")"

# Deletes and detaches are what a template diff doesn't show: name them, loudly
jq -r '.properties.changes.resourceChanges // [] | .[]
  | select(.changeType | ascii_downcase | . == "delete" or . == "detach")
  | "\(.changeType)\t\(.id // (.identifiers | tostring))"' "$work/stack.json" > "$work/losses.tsv"
while IFS=$'\t' read -r change id; do
  warn "$PARAMS" "the stack would $change $id"
  summary "- **$change** \`$id\`"
done < "$work/losses.tsv"
if [ ! -s "$work/losses.tsv" ]; then
  echo "Nothing would be deleted or detached."
  summary ""
  summary "Nothing would be deleted or detached."
fi
