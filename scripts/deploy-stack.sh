#!/usr/bin/env bash
# Deploy one configuration as a deployment stack, or retire the stack. The stack is the lifecycle:
# it owns every resource the solution creates, so removing one from the template removes it from
# Azure (deleteAll, deleteResources) or lets it go (detachAll), and retiring removes them all.
# Where the stack lives (subscription or management group), its actionOnUnmanage and deny
# settings come from platform.json, so the preview and the deployment can't disagree.
#
# Usage: scripts/deploy-stack.sh <solution>/<environment> <deploy|retire>
#   needs az, logged in with rights to manage deployment stacks at the stack's scope
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

usage="usage: deploy-stack.sh <solution>/<environment> <deploy|retire>"
stack_context "${1:?$usage}"
action=${2:?$usage}

case "$action" in
  deploy)
    # An init solution deploys from source (using '../main.bicep'); every other one a published version
    version=$(sed -nE "s/^using '[^']*:v([0-9.]+)'.*/\1/p" "$ROOT/$PARAMS")
    version=${version:-$(version_of "solutions/$SOLUTION")}
    az stack "$SCOPE" create --name "$STACK_NAME" --location "$LOCATION" "$SCOPE_FLAG" "$TARGET_ID" \
      --parameters "$ROOT/$PARAMS" --action-on-unmanage "$UNMANAGE" --deny-settings-mode "$DENY_MODE" \
      --description "solutions/$SOLUTION v$version, $ENVIRONMENT, commit ${GITHUB_SHA:-$(git -C "$ROOT" rev-parse HEAD)}" \
      --yes --only-show-errors \
      --query "{state: provisioningState, resources: length(resources)}" --output table
    summary "Deployed \`$STACK_NAME\` v$version at $SCOPE_FLAG $TARGET_ID (actionOnUnmanage $UNMANAGE)."
    ;;
  retire)
    az stack "$SCOPE" delete --name "$STACK_NAME" "$SCOPE_FLAG" "$TARGET_ID" \
      --action-on-unmanage "$UNMANAGE" --yes --only-show-errors
    summary "Retired \`$STACK_NAME\` at $SCOPE_FLAG $TARGET_ID (actionOnUnmanage $UNMANAGE)."
    ;;
  *) echo "$usage" >&2; exit 2 ;;
esac
