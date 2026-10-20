#!/usr/bin/env bash
# Unit tests for the helpers in scripts/lib.sh
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"
# shellcheck source=assert.sh
. "$(dirname "$0")/assert.sh"

equals "relpath to a sibling folder" "$(relpath /r/modules/network/app-network /r/modules/network/nsg/main.bicep)" "../nsg/main.bicep"
equals "relpath up to the root" "$(relpath /r/solutions/app /r/types/main.bicep)" "../../types/main.bicep"
equals "relpath into a subfolder" "$(relpath /r/solutions/app/configurations /r/solutions/app/main.bicep)" "../main.bicep"
equals "relpath into the cache" "$(relpath /r/solutions/app/configurations /r/.refcache/solutions/app/v1.0.0/solutions/app/main.bicep)" "../../../.refcache/solutions/app/v1.0.0/solutions/app/main.bicep"

file=$(mktemp)
cat > "$file" <<'EOF'
import { a } from 'br/platform:types:v1.2.3'
// module old 'br/platform:modules/x/y:v0.0.1' = {
module m 'br/platform:modules/network/nsg:v1.0.0' = {
module n 'br/platform:modules/network/nsg:v1.0.0' = {
EOF
equals "registry_refs skips comments and duplicates" "$(registry_refs "$file" | tr '\n' ' ')" "br/platform:modules/network/nsg:v1.0.0 br/platform:types:v1.2.3 "
rm -f "$file"

tenant=$(jq -r '.tenantId' "$ROOT/platform.json")
stack_context 02-workloads-000-sample-app/prod
equals "a subscription stack is named <solution>-<environment>" "$STACK_NAME" "02-workloads-000-sample-app-prod"
equals "it deploys at the subscription platform.json names" "$SCOPE $SCOPE_FLAG $TARGET_ID" \
  "sub --subscription $(jq -r '.environments.prod.subscriptions.sampleApp' "$ROOT/platform.json")"
equals "with the defaults" "$UNMANAGE $DENY_MODE $WHATIF" "deleteAll none true"
stack_context 01-core-000-management-groups/dev
equals "the management groups deploy at the tenant root group" "$SCOPE $SNAPSHOT_FLAG $TARGET_ID" "mg --management-group-id $tenant"
equals "they detach, and skip what-if" "$UNMANAGE $WHATIF" "detachAll false"
equals "a management group stack ID" "$STACK_ID" \
  "/providers/Microsoft.Management/managementGroups/$tenant/providers/Microsoft.Resources/deploymentStacks/01-core-000-management-groups-dev"
stack_context 01-core-010-platform/dev
equals "the platform deploys at its own management group" "$TARGET_ID" "contoso-canary-platform"
check_fails "a configuration that doesn't exist" "no configuration" stack_context 02-workloads-000-sample-app/test
check_fails "not <solution>/<environment>" "expected <solution>/<environment>" stack_context 02-workloads-000-sample-app

equals "configs_of lists one environment in deploy order" "$(configs_of prod | tr '\n' ' ')" \
  "00-init-010-module-registry/prod 01-core-000-management-groups/prod 01-core-010-platform/prod 02-workloads-000-sample-app/prod "
equals "configs_of one tier" "$(configs_of dev 01-core | tr '\n' ' ')" "01-core-000-management-groups/dev 01-core-010-platform/dev "

done_testing
