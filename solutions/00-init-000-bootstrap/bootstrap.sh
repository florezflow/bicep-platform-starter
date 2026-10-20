#!/usr/bin/env bash
# Prepare a tenant for the platform, once, before anything else can deploy. Safe to run again:
# whatever exists is left alone. Run it as a Global Administrator with elevated access
# (Microsoft Entra ID > Properties > Access management for Azure resources), from the repo root.
#
#   1. registers the resource providers in every subscription in platform.json
#   2. creates what Entra Domain Services needs before it can deploy: the Domain Controller
#      Services service principal and the AAD DC Administrators group
#   3. creates two app registrations that GitHub Actions signs in as, with OIDC credentials (no secrets):
#        deployer   Owner at the tenant root group: creates management groups, moves subscriptions
#                   (that needs role assignment rights on them), deploys and retires stacks
#        previewer  Reader at the tenant root group: what-if and stack what-if, nothing else
#   4. writes tenantId and both principal IDs into platform.json, for you to review and commit
#   5. with --github: creates the GitHub environments and sets the variables the workflows read
#
# Usage: solutions/00-init-000-bootstrap/bootstrap.sh --repo OWNER/REPO [--github] [--dry-run]
#   --repo OWNER/REPO   the GitHub repository whose workflows sign in (the OIDC subject)
#   --github            also create the environments and set the variables (needs gh, logged in)
#   --dry-run           read what exists, print every change, change nothing
set -euo pipefail

root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
platform="$root/platform.json"
usage="usage: bootstrap.sh --repo OWNER/REPO [--github] [--dry-run]"

repo=""
github=false
dry_run=false
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo=${2:?$usage}; shift 2 ;;
    --github) github=true; shift ;;
    --dry-run) dry_run=true; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "$usage" >&2; exit 2 ;;
  esac
done
case "$repo" in */*) ;; *) echo "$usage" >&2; exit 2 ;; esac

providers="Microsoft.AAD Microsoft.ContainerRegistry Microsoft.Network Microsoft.OperationalInsights Microsoft.SecurityInsights Microsoft.Storage"
dc_services_app_id=2565bd9d-da50-47d4-8b85-4c97f669dc36 # Domain Controller Services, the same in every tenant
issuer=https://token.actions.githubusercontent.com
name=${repo#*/}

ok() { printf '\033[32mOK\033[0m    %s\n' "$*"; }

# run <command...>: a call that changes something. Printed; skipped with --dry-run
run() {
  if $dry_run; then echo "would run: $*"; else echo "+ $*"; "$@"; fi
}

tenant=$(az account show --query tenantId --output tsv)
tenant_root="/providers/Microsoft.Management/managementGroups/$tenant"
echo "Tenant $tenant, repository $repo$($dry_run && echo ', dry run')"

echo "== 1. Resource providers"
for sub in $(jq -r '[.environments[].subscriptions[]] | unique[]' "$platform"); do
  for ns in $providers; do
    state=$(az provider show --namespace "$ns" --subscription "$sub" --query registrationState --output tsv 2>/dev/null || true)
    if [ "$state" = Registered ]; then ok "$ns in $sub"; continue; fi
    run az provider register --namespace "$ns" --subscription "$sub"
  done
done

echo "== 2. Entra Domain Services prerequisites"
if az ad sp show --id "$dc_services_app_id" --query id --output tsv > /dev/null 2>&1; then
  ok "Domain Controller Services service principal"
else
  run az ad sp create --id "$dc_services_app_id"
fi
if [ -n "$(az ad group list --display-name "AAD DC Administrators" --query '[0].id' --output tsv)" ]; then
  ok "AAD DC Administrators group"
else
  run az ad group create --display-name "AAD DC Administrators" --mail-nickname AADDCAdministrators \
    --description "Administrators of the Entra Domain Services managed domain"
fi

# identity <role> <subject...>: an app registration with a service principal and one federated
# credential per GitHub OIDC subject. Sets APP_ID and PRINCIPAL_ID.
identity() {
  local display="github-$name-$1" existing subject params
  shift
  APP_ID=$(az ad app list --display-name "$display" --query '[0].appId' --output tsv)
  if [ -n "$APP_ID" ]; then
    ok "app registration $display"
  elif $dry_run; then
    echo "would run: az ad app create --display-name $display"
    APP_ID="<$display app ID>"
  else
    APP_ID=$(az ad app create --display-name "$display" --query appId --output tsv)
    echo "+ created app registration $display ($APP_ID)"
  fi
  PRINCIPAL_ID=$(az ad sp show --id "$APP_ID" --query id --output tsv 2>/dev/null || true)
  if [ -n "$PRINCIPAL_ID" ]; then
    ok "service principal of $display"
  elif $dry_run; then
    echo "would run: az ad sp create --id $APP_ID"
    PRINCIPAL_ID="<$display principal ID>"
  else
    PRINCIPAL_ID=$(az ad sp create --id "$APP_ID" --query id --output tsv)
    echo "+ created service principal of $display ($PRINCIPAL_ID)"
  fi
  existing=$(az ad app federated-credential list --id "$APP_ID" --query '[].subject' --output tsv 2>/dev/null || true)
  for subject in "$@"; do
    if printf '%s\n' "$existing" | grep -qxF "$subject"; then ok "$display trusts $subject"; continue; fi
    params=$(jq -nc --arg name "github-$(printf '%s' "${subject#repo:*/*:}" | tr -c 'a-zA-Z0-9' '-')" \
      --arg issuer "$issuer" --arg subject "$subject" \
      '{name: $name, issuer: $issuer, subject: $subject, audiences: ["api://AzureADTokenExchange"]}')
    run az ad app federated-credential create --id "$APP_ID" --parameters "$params"
  done
}

# assign <principal ID> <role>: a role at the tenant root group, inherited by every group and subscription
assign() {
  if [ -n "$(az role assignment list --assignee "$1" --role "$2" --scope "$tenant_root" --query '[0].id' --output tsv 2>/dev/null || true)" ]; then
    ok "$2 at the tenant root group"
    return
  fi
  run az role assignment create --assignee-object-id "$1" --assignee-principal-type ServicePrincipal \
    --role "$2" --scope "$tenant_root"
}

echo "== 3. Identities for GitHub Actions"
# The deployer signs in from main (publish.yml) and from the approved environments (deploy.yml)
identity deployer "repo:$repo:ref:refs/heads/main" "repo:$repo:environment:dev" "repo:$repo:environment:prod"
deployer_app=$APP_ID
deployer_principal=$PRINCIPAL_ID
assign "$deployer_principal" Owner
# The previewer only from the preview environments, which need no approval
identity previewer "repo:$repo:environment:dev-preview" "repo:$repo:environment:prod-preview"
previewer_app=$APP_ID
previewer_principal=$PRINCIPAL_ID
assign "$previewer_principal" Reader

echo "== 4. platform.json"
current=$(jq -r '[.tenantId, .identities.deployerPrincipalId, .identities.previewerPrincipalId] | join(" ")' "$platform")
if [ "$current" = "$tenant $deployer_principal $previewer_principal" ]; then
  ok "platform.json has the tenant and both principal IDs"
elif $dry_run; then
  echo "would write: tenantId $tenant, identities.deployerPrincipalId, identities.previewerPrincipalId"
else
  jq --arg t "$tenant" --arg d "$deployer_principal" --arg p "$previewer_principal" \
    '.tenantId = $t | .identities.deployerPrincipalId = $d | .identities.previewerPrincipalId = $p' \
    "$platform" > "$platform.new"
  mv "$platform.new" "$platform"
  echo "+ wrote tenantId and the principal IDs: review with git diff platform.json, then commit"
fi

echo "== 5. GitHub"
if $github; then
  for env in dev prod dev-preview prod-preview; do
    run gh api --method PUT "repos/$repo/environments/$env" --silent
  done
  run gh variable set AZURE_TENANT_ID --repo "$repo" --body "$tenant"
  run gh variable set AZURE_CLIENT_ID --repo "$repo" --body "$deployer_app"
  for env in dev-preview prod-preview; do
    run gh variable set AZURE_CLIENT_ID --repo "$repo" --env "$env" --body "$previewer_app"
  done
else
  echo "skipped (--github): set AZURE_TENANT_ID=$tenant and AZURE_CLIENT_ID=$deployer_app on the repository,"
  echo "and AZURE_CLIENT_ID=$previewer_app on the environments dev-preview and prod-preview"
fi

echo
echo "Next, by hand:"
echo "  - add required reviewers to the environments dev and prod: the deploy job waits for them"
echo "  - deploy the registry: scripts/deploy-stack.sh $(jq -r '.registry.config' "$platform") deploy"
echo "  - turn Azure on: gh variable set AZURE_ENABLED --repo $repo --body true"
echo "  - publish, then rebuild each environment: README.md, Turn on Azure"
