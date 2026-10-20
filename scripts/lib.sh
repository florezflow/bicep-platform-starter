#!/usr/bin/env bash
# Shared helpers for the scripts in this folder. Source it, don't run it.
# Written for bash 3.2 (macOS) and bash 5 (GitHub runners): no associative arrays, no mapfile.

ROOT=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
export ROOT
ALIAS=platform
# shellcheck disable=SC2034 # used by the scripts that source this file
SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
# shellcheck disable=SC2034 # solution folders: <tier>-<NNN>-<name>
SOLUTION_RE='^(00-init|01-core|02-workloads)-[0-9]{3}-[a-z0-9]+(-[a-z0-9]+)*$'

errors=0
warnings=0

in_actions() { [ "${GITHUB_ACTIONS:-}" = "true" ]; }

# error <file> <message>: an annotation on GitHub, a red line locally
error() {
  errors=$((errors + 1))
  if in_actions; then echo "::error file=$1::$2"; else printf '\033[31mERROR\033[0m %s: %s\n' "$1" "$2"; fi
}

warn() {
  warnings=$((warnings + 1))
  if in_actions; then echo "::warning file=$1::$2"; else printf '\033[33mWARN\033[0m  %s: %s\n' "$1" "$2"; fi
}

ok() { printf '\033[32mOK\033[0m    %s\n' "$*"; }

# summary <markdown line>: appended to the job summary on GitHub, ignored locally
summary() {
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY"; fi
}

# components: every folder with a metadata.json, as a path relative to the repo root
components() {
  (cd "$ROOT" && find types modules solutions -name metadata.json -not -path '*/.refcache/*' 2>/dev/null \
    | sed 's|/metadata.json$||' | sort)
}

# version_of <component>: the version in its metadata.json
version_of() {
  jq -r '.version // empty' "$ROOT/$1/metadata.json" 2>/dev/null
}

# tag_of <component> <version>: the git tag that marks a released version
tag_of() { echo "$1/v$2"; }

tag_exists() { git -C "$ROOT" rev-parse -q --verify "refs/tags/$1" > /dev/null; }

# relpath <from-dir> <to-file>: relative path between two absolute paths
relpath() {
  local to=$2 common=$1 up=""
  while [ "${to#"$common"/}" = "$to" ]; do
    common=$(dirname "$common")
    up="../$up"
  done
  echo "${up}${to#"$common"/}"
}

# registry_refs <file>: the br/platform:<path>:v<version> references in one file, one per line
registry_refs() {
  grep -v '^[[:space:]]*//' "$1" \
    | grep -oE "'br/$ALIAS:[a-z0-9./-]+:v[0-9]+\.[0-9]+\.[0-9]+'" \
    | tr -d "'" | sort -u || true
}

# repo_files <pattern...>: files in the working tree, tracked or new, without ignored ones (like .refcache/)
repo_files() {
  (cd "$ROOT" && git ls-files -co --exclude-standard -- "$@" | sort -u \
    | while IFS= read -r f; do if [ -f "$f" ]; then echo "$f"; fi; done)
}

# bicep_files: every .bicep and .bicepparam file
bicep_files() { repo_files '*.bicep' '*.bicepparam'; }

# config_files: every solution configuration
config_files() { repo_files 'solutions/*/configurations/*.bicepparam'; }

# stack_context <solution>/<environment>: what one configuration deploys as, read from platform.json.
# Sets SOLUTION, ENVIRONMENT, PARAMS (the .bicepparam, relative to the root) and
#   STACK_NAME     <solution>-<environment>: the dev and prod stacks of a solution can share a scope
#   SCOPE          sub or mg, the az command group (az stack sub, az stack mg, ...)
#   TARGET_ID      the subscription or management group the stack deploys at
#   SCOPE_FLAG     --subscription or --management-group-id, for az
#   SNAPSHOT_FLAG  --subscription-id or --management-group-id, for bicep snapshot
#   STACK_ID       the stack's resource ID
#   UNMANAGE       actionOnUnmanage (default deleteAll), DENY_MODE (default none)
#   WHATIF         false when what-if can't preview the solution (the snapshot diff is the preview)
#   TENANT_ID, LOCATION
stack_context() {
  SOLUTION=${1%%/*}
  ENVIRONMENT=${1#*/}
  PARAMS="solutions/$SOLUTION/configurations/$ENVIRONMENT.bicepparam"
  if [ "$SOLUTION/$ENVIRONMENT" != "$1" ] || [ ! -f "$ROOT/$PARAMS" ]; then
    echo "no configuration $PARAMS for '$1' (expected <solution>/<environment>)" >&2
    return 1
  fi
  local line
  line=$(jq -r --arg s "$SOLUTION" --arg e "$ENVIRONMENT" '
    .solutions[$s] as $sol | ($sol.targets[$e]? // {}) as $t
    | [ (if $t.subscription then "sub" elif $t.managementGroup or $t.tenantRootGroup then "mg" else "" end),
        (if $t.subscription then (.environments[$e].subscriptions[$t.subscription] // "")
         elif $t.tenantRootGroup == true then .tenantId
         else ($t.managementGroup // "") end),
        ($sol.actionOnUnmanage? // "deleteAll"),
        ($sol.denySettingsMode? // "none"),
        (if $sol.whatIf? == false then "false" else "true" end),
        .tenantId, .location ]
    | join("|")' "$ROOT/platform.json") || return 1
  IFS='|' read -r SCOPE TARGET_ID UNMANAGE DENY_MODE WHATIF TENANT_ID LOCATION <<< "$line"
  if [ -z "$SCOPE" ] || [ -z "$TARGET_ID" ]; then
    echo "platform.json has no target for $SOLUTION in $ENVIRONMENT: set solutions.$SOLUTION.targets.$ENVIRONMENT to a subscription (a key of environments.$ENVIRONMENT.subscriptions), a managementGroup or tenantRootGroup: true" >&2
    return 1
  fi
  STACK_NAME="$SOLUTION-$ENVIRONMENT"
  if [ "$SCOPE" = sub ]; then
    SCOPE_FLAG=--subscription
    SNAPSHOT_FLAG=--subscription-id
    STACK_ID="/subscriptions/$TARGET_ID/providers/Microsoft.Resources/deploymentStacks/$STACK_NAME"
  else
    SCOPE_FLAG=--management-group-id
    SNAPSHOT_FLAG=--management-group-id
    STACK_ID="/providers/Microsoft.Management/managementGroups/$TARGET_ID/providers/Microsoft.Resources/deploymentStacks/$STACK_NAME"
  fi
  export SOLUTION ENVIRONMENT PARAMS STACK_NAME SCOPE TARGET_ID SCOPE_FLAG SNAPSHOT_FLAG STACK_ID \
    UNMANAGE DENY_MODE WHATIF TENANT_ID LOCATION
}

# configs_of <environment> [tier]: the <solution>/<environment> configurations of one environment,
# in deploy order (the folder number), optionally only one tier (00-init, 01-core, 02-workloads)
configs_of() {
  local p name
  for p in $(config_files); do
    name=${p#solutions/}
    name=${name%%/*}
    case "$p" in
      "solutions/${2:-}"*"/configurations/$1.bicepparam") echo "$name/$1" ;;
    esac
  done
}

finish() {
  echo
  if [ "$errors" -gt 0 ]; then
    echo "$errors error(s), $warnings warning(s)"
    exit 1
  fi
  echo "No errors, $warnings warning(s)"
}
