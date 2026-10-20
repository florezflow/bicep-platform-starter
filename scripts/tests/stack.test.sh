#!/usr/bin/env bash
# preview-stack.sh and deploy-stack.sh against a fake az that records its arguments, so the
# Azure path is tested without Azure: the preview and the deployment must get the same settings,
# at the scope platform.json gives the configuration.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=assert.sh
. "$here/assert.sh"
scripts="$here/.."

fake=$(mktemp -d)
export AZ_LOG="$fake/az.log" WHATIF_JSON="$fake/whatif.json"
cat > "$fake/az" <<'FAKE'
#!/usr/bin/env bash
echo "az $*" >> "$AZ_LOG"
case "$1 $2 $3" in
  "stack sub show"|"stack mg show")
    [ -n "${STACK_EXISTS:-}" ] || { echo "DeploymentStackNotFound" >&2; exit 3; }
    case "$*" in *--query*) printf '%s\n' /subscriptions/x/resourceGroups/rg-sampleapp-dev-szn-001 ;; esac ;;
  "deployment sub what-if"|"deployment mg what-if") echo "Resource changes: 3 to create." ;;
  "stack-whatif sub create"|"stack-whatif mg create") cat "$WHATIF_JSON" ;;
esac
FAKE
chmod +x "$fake/az"
export PATH="$fake:$PATH"

cat > "$WHATIF_JSON" <<'JSON'
{"properties": {"changes": {"resourceChanges": [
  {"id": "/subscriptions/x/resourceGroups/rg-sampleapp-dev-szn-001/providers/Microsoft.Storage/storageAccounts/old", "changeType": "delete"},
  {"id": "/subscriptions/x/resourceGroups/rg-sampleapp-dev-szn-001", "changeType": "noChange"},
  {"id": "/subscriptions/x/resourceGroups/rg-sampleapp-dev-szn-001/providers/Microsoft.Network/networkSecurityGroups/nsg", "changeType": "modify"}
]}}}
JSON

app=02-workloads-000-sample-app
dev_sub=$(jq -r '.environments.dev.subscriptions.sampleApp' "$here/../../platform.json")
tenant=$(jq -r '.tenantId' "$here/../../platform.json")

echo "-- preview, subscription stack"
check_fails "an unknown configuration" "no configuration" "$scripts/preview-stack.sh" $app/test deploy
check_fails "an unknown action" "usage: preview-stack.sh" "$scripts/preview-stack.sh" $app/dev redeploy
check_output "first deployment: what-if only" "First deployment of $app-dev" "$scripts/preview-stack.sh" $app/dev deploy
check "what-if at the configuration's subscription, read-only validation" \
  grep -q "deployment sub what-if --name $app-dev --location switzerlandnorth --subscription $dev_sub .*--validation-level ProviderNoRbac" "$AZ_LOG"
check "no stack what-if for a stack that doesn't exist" bash -c "! grep -q stack-whatif '$AZ_LOG'"

rm -f "$AZ_LOG"
export STACK_EXISTS=1
check_output "existing stack: a deletion is named" "the stack would delete /subscriptions/x/resourceGroups/rg-sampleapp-dev-szn-001/providers/Microsoft.Storage/storageAccounts/old" \
  "$scripts/preview-stack.sh" $app/dev deploy
check "stack what-if gets the stack id" \
  grep -q "stack-whatif sub create --name $app-dev --stack-id /subscriptions/$dev_sub/providers/Microsoft.Resources/deploymentStacks/$app-dev" "$AZ_LOG"
check "stack what-if keeps its result for a day" grep -q "stack-whatif .*--retention-interval P1D" "$AZ_LOG"
check_output "retire lists what the stack manages" "rg-sampleapp-dev-szn-001" "$scripts/preview-stack.sh" $app/dev retire

echo "-- preview, management group stacks"
rm -f "$AZ_LOG"
check_output "the platform: what-if at its management group" "Nothing would be deleted" \
  bash -c "jq '.properties.changes.resourceChanges |= map(select(.changeType != \"delete\"))' '$WHATIF_JSON' > '$fake/w2' && WHATIF_JSON='$fake/w2' '$scripts/preview-stack.sh' 01-core-010-platform/prod deploy"
check "deployment what-if at the management group" \
  grep -q "deployment mg what-if --name 01-core-010-platform-prod --location switzerlandnorth --management-group-id contoso-platform" "$AZ_LOG"
check "stack what-if at the management group" \
  grep -q "stack-whatif mg create --name 01-core-010-platform-prod --stack-id /providers/Microsoft.Management/managementGroups/contoso-platform/providers/Microsoft.Resources/deploymentStacks/01-core-010-platform-prod" "$AZ_LOG"
rm -f "$AZ_LOG"
check_output "management groups: no what-if, the snapshot diff instead" "whatIf: false" \
  "$scripts/preview-stack.sh" 01-core-000-management-groups/dev deploy
check "no what-if of either kind" bash -c "! grep -qE 'what-if|stack-whatif' '$AZ_LOG'"
check "the stack is looked up at the tenant root group" \
  grep -q "stack mg show --name 01-core-000-management-groups-dev --management-group-id $tenant" "$AZ_LOG"

echo "-- deploy"
check "deploy runs" "$scripts/deploy-stack.sh" $app/dev deploy
check "deploy creates the stack from the config, at its subscription" \
  grep -q "stack sub create --name $app-dev --location switzerlandnorth --subscription $dev_sub --parameters .*/solutions/$app/configurations/dev.bicepparam" "$AZ_LOG"
check "the description names the version" grep -q "solutions/$app v1.0.0, dev" "$AZ_LOG"
check "management groups deploy at the tenant root group, detaching what leaves" bash -c \
  "'$scripts/deploy-stack.sh' 01-core-000-management-groups/prod deploy > /dev/null && grep -q 'stack mg create --name 01-core-000-management-groups-prod --location switzerlandnorth --management-group-id $tenant .*--action-on-unmanage detachAll' '$AZ_LOG'"
check "an init solution names the version in its metadata.json" bash -c \
  "'$scripts/deploy-stack.sh' 00-init-010-module-registry/prod deploy > /dev/null && grep -q 'solutions/00-init-010-module-registry v1.0.0, prod' '$AZ_LOG'"
check "retire deletes the stack" "$scripts/deploy-stack.sh" $app/dev retire
check "retire passes actionOnUnmanage" grep -q "stack sub delete --name $app-dev --subscription $dev_sub --action-on-unmanage deleteAll --yes" "$AZ_LOG"

echo "-- preview and deploy agree"
settings() { grep "$1" "$AZ_LOG" | grep -oE -- "--(action-on-unmanage|deny-settings-mode|location|subscription|management-group-id) [^ ]+" | sort | tr '\n' ' '; }
prod_sub=$(jq -r '.environments.prod.subscriptions.sampleApp' "$here/../../platform.json")
for case in "$app/prod|--subscription $prod_sub" "01-core-010-platform/dev|--management-group-id contoso-canary-platform"; do
  config=${case%%|*}
  rm -f "$AZ_LOG"
  "$scripts/preview-stack.sh" "$config" deploy > /dev/null 2>&1
  "$scripts/deploy-stack.sh" "$config" deploy > /dev/null 2>&1
  equals "$config: deploy gets its target and settings from platform.json" "$(settings 'stack [a-z]* create')" \
    "--action-on-unmanage deleteAll --deny-settings-mode none --location switzerlandnorth ${case#*|} "
  equals "$config: the preview gets the same" "$(settings 'stack-whatif [a-z]* create')" "$(settings 'stack [a-z]* create')"
done

rm -rf "$fake"
done_testing
