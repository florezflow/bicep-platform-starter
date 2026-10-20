#!/usr/bin/env bash
# The bootstrap against a fake az and gh: a dry run changes nothing and names every change,
# an existing setup needs no change, and a real run writes the IDs into platform.json.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=assert.sh
. "$here/assert.sh"
src=$(git -C "$here" rev-parse --show-toplevel)

fake=$(mktemp -d)
export AZ_LOG="$fake/calls.log"
cat > "$fake/az" <<'FAKE'
#!/usr/bin/env bash
echo "az $*" >> "$AZ_LOG"
case "$*" in
  "account show"*) echo 11111111-1111-1111-1111-111111111111 ;;
  "provider show"*) if [ -n "${EXISTS:-}" ]; then echo Registered; else echo NotRegistered; fi ;;
  "ad sp show"*|"ad group list"*|"role assignment list"*) if [ -n "${EXISTS:-}" ]; then echo some-id; else exit 1; fi ;;
  "ad app list"*) if [ -n "${EXISTS:-}" ]; then echo some-app-id; fi ;;
  "ad app federated-credential list"*)
    if [ -n "${EXISTS:-}" ]; then
      for s in ref:refs/heads/main environment:dev environment:prod environment:dev-preview environment:prod-preview; do echo "repo:octo/demo:$s"; done
    fi ;;
  "ad app create"*) echo new-app-id ;;
  "ad sp create"*) echo new-principal-id ;;
esac
FAKE
cat > "$fake/gh" <<'FAKE'
#!/usr/bin/env bash
echo "gh $*" >> "$AZ_LOG"
FAKE
chmod +x "$fake/az" "$fake/gh"
export PATH="$fake:$PATH"

# A copy of the repo, so the real run writes its own platform.json
repo=$(mktemp -d)
(cd "$src" && git ls-files -co --exclude-standard | tar -cf - -T -) | tar -xf - -C "$repo"
git -C "$repo" init -q -b main
bootstrap="$repo/solutions/00-init-000-bootstrap/bootstrap.sh"
before=$(cat "$repo/platform.json")
writes='(create|register|set|PUT)'

echo "-- dry run on an empty tenant"
check_fails "the repository is required" "usage: bootstrap.sh" "$bootstrap" --dry-run
dry="$fake/dry-run.txt"
check "runs" bash -c "'$bootstrap' --repo octo/demo --dry-run --github > '$dry'"
check "registers missing providers in every subscription" \
  grep -q "would run: az provider register --namespace Microsoft.AAD --subscription 00000000-0000-0000-0000-00000000f201" "$dry"
check "creates the Domain Controller Services service principal" grep -q "would run: az ad sp create --id 2565bd9d-da50-47d4-8b85-4c97f669dc36" "$dry"
check "creates the AAD DC Administrators group" grep -q "would run: az ad group create --display-name AAD DC Administrators" "$dry"
check "trusts main and the approved environments for the deployer" bash -c \
  "grep -c 'federated-credential create --id <github-demo-deployer app ID>' '$dry' | grep -qx 3"
check "trusts only the preview environments for the previewer" grep -q 'federated-credential create --id <github-demo-previewer app ID> --parameters {"name":"github-environment-prod-preview","issuer":"https://token.actions.githubusercontent.com","subject":"repo:octo/demo:environment:prod-preview"' "$dry"
check "the deployer is Owner at the tenant root group" grep -q "role assignment create --assignee-object-id <github-demo-deployer principal ID> --assignee-principal-type ServicePrincipal --role Owner --scope /providers/Microsoft.Management/managementGroups/11111111-1111-1111-1111-111111111111" "$dry"
check "the previewer is Reader there" grep -q "role assignment create --assignee-object-id <github-demo-previewer principal ID> .*--role Reader" "$dry"
check "the previewer gets its own client ID in the preview environments" grep -q "would run: gh variable set AZURE_CLIENT_ID --repo octo/demo --env prod-preview" "$dry"
check "nothing was changed in Azure or on GitHub" bash -c "! grep -E '$writes' '$AZ_LOG'"
equals "platform.json is untouched" "$(cat "$repo/platform.json")" "$before"

echo "-- an existing setup"
rm -f "$AZ_LOG"
check "runs" bash -c "EXISTS=1 '$bootstrap' --repo octo/demo --dry-run > '$dry'"
check "has nothing to change" bash -c "grep -q 'Reader at the tenant root group' '$dry' && ! grep -q 'would run' '$dry'"

echo "-- a real run"
rm -f "$AZ_LOG"
check "runs" "$bootstrap" --repo octo/demo
check "creates the apps" grep -q "az ad app create --display-name github-demo-deployer" "$AZ_LOG"
check "leaves GitHub alone without --github" bash -c "! grep -q '^gh ' '$AZ_LOG'"
equals "writes the tenant and both principals into platform.json" \
  "$(jq -c '[.tenantId, .identities.deployerPrincipalId, .identities.previewerPrincipalId]' "$repo/platform.json")" \
  '["11111111-1111-1111-1111-111111111111","new-principal-id","new-principal-id"]'

rm -rf "$fake" "$repo"
done_testing
