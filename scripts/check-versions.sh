#!/usr/bin/env bash
# Check every component's version bookkeeping. Runs on every pull request and before every publish.
#
# Per component (every folder with a metadata.json):
#   - metadata.json, `metadata version` in main.bicep and the top CHANGELOG entry agree
#   - the version isn't lower than the newest released one
#   - a released version (git tag <component>/v<version>) has no template changes since its tag:
#     a change needs a new version, or publishing would skip it
# Per solution folder:
#   - the name is <tier>-<NNN>-<name>, the tier one of 00-init, 01-core, 02-workloads
# Per solution configuration:
#   - platform.json gives it a target, and the solution's targetScope matches it
#   - 00-init: self-contained (using '../main.bicep', no registry references), deployed by hand,
#     so it's not in .github/workflows/deploy.yml
#   - every other tier: deploys a released or the current version of its own solution, from the
#     registry, and is listed in .github/workflows/deploy.yml
# platform.json:
#   - every solution it names exists, its actionOnUnmanage and denySettingsMode are valid
#   - the registry is the one bicepconfig.json resolves br/platform to
# Per .bicep/.bicepparam file:
#   - no local path that leaves its component: other components come from the registry
#
# Usage: scripts/check-versions.sh
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

semver_lt() { # a < b
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" = "$1" ]
}

latest_release() { # newest released version of a component, or nothing
  git -C "$ROOT" tag -l "$1/v*" | sed "s|^$1/v||" | grep -E "$SEMVER_RE" \
    | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 || true
}

summary "| Component | Version | Newest release | Result |"
summary "|---|---|---|---|"

for c in $(components); do
  before=$errors
  version=$(version_of "$c")
  released=$(latest_release "$c")

  if ! printf '%s' "$version" | grep -qE "$SEMVER_RE"; then
    error "$c/metadata.json" "\"version\" must be MAJOR.MINOR.PATCH, found \"$version\""
    continue
  fi

  if [ ! -f "$ROOT/$c/main.bicep" ]; then
    error "$c" "no main.bicep"
  else
    template=$(sed -nE "s/^metadata version = '([^']*)'.*/\1/p" "$ROOT/$c/main.bicep" | head -1)
    if [ "$template" != "$version" ]; then
      error "$c/main.bicep" "metadata version is '$template', metadata.json says $version"
    fi
  fi

  if [ ! -f "$ROOT/$c/CHANGELOG.md" ]; then
    error "$c" "no CHANGELOG.md"
  else
    top=$(grep -m1 '^## ' "$ROOT/$c/CHANGELOG.md" || true)
    if ! printf '%s' "$top" | grep -qE "^## $version - [0-9]{4}-[0-9]{2}-[0-9]{2}$"; then
      error "$c/CHANGELOG.md" "top entry is \"$top\", expected \"## $version - YYYY-MM-DD\""
    fi
  fi

  if [ -n "$released" ] && semver_lt "$version" "$released"; then
    error "$c/metadata.json" "version $version is lower than the released $released"
  fi

  tag=$(tag_of "$c" "$version")
  if tag_exists "$tag"; then
    changed=$(git -C "$ROOT" diff --name-only "refs/tags/$tag" -- "$c" \
      | grep -E '\.bicep$' | grep -v '/configurations/' || true)
    if [ -n "$changed" ]; then
      error "$c/metadata.json" "$version is already released (tag $tag), but $(echo "$changed" | tr '\n' ' ')changed since. Bump the version."
    fi
  fi

  if [ "$errors" -eq "$before" ]; then
    ok "$c $version"
    summary "| \`$c\` | $version | ${released:--} | ok |"
  else
    summary "| \`$c\` | $version | ${released:--} | **error** |"
  fi
done

# Solution folders: the tier decides the order in an environment and how a solution is deployed
for dir in $(cd "$ROOT" && find solutions -mindepth 1 -maxdepth 1 -type d | sort); do
  if ! basename "$dir" | grep -qE "$SOLUTION_RE"; then
    error "$dir" "solution folders are named <tier>-<NNN>-<name>: 00-init, 01-core or 02-workloads, three digits, lowercase words joined by -"
  fi
done

# Configurations: a target in platform.json, the right scope, the right source
deploy_yml="$ROOT/.github/workflows/deploy.yml"
for param in $(config_files); do
  solution=${param%%/configurations/*}
  name=${solution#solutions/}
  env=$(basename "$param" .bicepparam)
  if ! context=$(stack_context "$name/$env" 2>&1); then
    error "$param" "$context"
  else
    stack_context "$name/$env" # again, outside the subshell, for SCOPE
    scope=$(sed -nE "s/^targetScope = '([^']*)'.*/\1/p" "$ROOT/$solution/main.bicep" | head -1)
    case "$SCOPE:${scope:-resourceGroup}" in
      sub:subscription|mg:managementGroup) ;;
      *) error "$solution/main.bicep" "targetScope is '${scope:-resourceGroup}', but platform.json deploys $name/$env at a $([ "$SCOPE" = sub ] && echo subscription || echo management group)" ;;
    esac
  fi

  using=$(sed -nE "s/^using '([^']*)'.*/\1/p" "$ROOT/$param" | head -1)
  listed=false
  if [ -f "$deploy_yml" ] && grep -qE "^[[:space:]]*- $name/$env$" "$deploy_yml"; then listed=true; fi
  case "$name" in
    00-init-*)
      if [ "$using" != "../main.bicep" ]; then
        error "$param" "an init solution is deployed once from source: start with using '../main.bicep'"
      fi
      for f in $(repo_files "$solution/*.bicep"); do
        if [ -n "$(registry_refs "$ROOT/$f")" ]; then
          error "$f" "an init solution runs before the registry exists: no br/$ALIAS references"
        fi
      done
      if [ "$listed" = true ]; then
        error "$param" "$name/$env is deployed by hand (it runs before the pipeline can): remove it from .github/workflows/deploy.yml"
      fi
      continue
      ;;
  esac
  case "$using" in
    "br/$ALIAS:$solution:v"*)
      pinned=${using##*:v}
      current=$(version_of "$solution")
      if [ "$pinned" != "$current" ] && ! tag_exists "$(tag_of "$solution" "$pinned")"; then
        error "$param" "deploys v$pinned, which is neither released nor the version on this branch ($current)"
      elif [ "$pinned" != "$current" ]; then
        if in_actions; then echo "::notice file=$param::deploys v$pinned; the branch has v$current"; fi
        echo "      $param deploys v$pinned (branch: v$current)"
      fi
      ;;
    *) error "$param" "must start with: using 'br/$ALIAS:$solution:v<version>'" ;;
  esac
  if [ -f "$deploy_yml" ] && [ "$listed" = false ]; then
    error "$param" "$name/$env is missing from the config choices in .github/workflows/deploy.yml"
  fi
done

# platform.json: names that exist, values Azure accepts, the registry bicepconfig.json uses
for name in $(jq -r '.solutions | keys[]' "$ROOT/platform.json"); do
  if [ ! -d "$ROOT/solutions/$name" ]; then
    error platform.json "solutions.$name: there's no folder solutions/$name"
  fi
done
while IFS= read -r problem; do error platform.json "$problem"; done < <(jq -r '.solutions | to_entries[]
  | (select(.value.actionOnUnmanage and (.value.actionOnUnmanage | IN("deleteAll", "deleteResources", "detachAll") | not))
      | "solutions.\(.key).actionOnUnmanage is \(.value.actionOnUnmanage | tojson): use deleteAll, deleteResources or detachAll"),
    (select(.value.denySettingsMode and (.value.denySettingsMode | IN("none", "denyDelete", "denyWriteAndDelete") | not))
      | "solutions.\(.key).denySettingsMode is \(.value.denySettingsMode | tojson): use none, denyDelete or denyWriteAndDelete")' \
  "$ROOT/platform.json")
registry=$(jq -r '.registry.name' "$ROOT/platform.json")
resolved=$(jq -r --arg a "$ALIAS" '.moduleAliases.br[$a].registry // empty' "$ROOT/bicepconfig.json")
if [ "$resolved" != "$registry.azurecr.io" ]; then
  error bicepconfig.json "br/$ALIAS resolves to '$resolved', but platform.json's registry is $registry.azurecr.io"
fi
registry_config=$(jq -r '.registry.config' "$ROOT/platform.json")
if [ ! -f "$ROOT/solutions/${registry_config%%/*}/configurations/${registry_config#*/}.bicepparam" ]; then
  error platform.json "registry.config is '$registry_config', but there's no such configuration"
fi

# Local paths may stay inside their component; everything else comes from the registry
for f in $(bicep_files); do
  component=$(dirname "$f")
  case "$component" in */configurations) component=$(dirname "$component") ;; esac
  for ref in $(grep -E "^[[:space:]]*(module|using)[[:space:]]|[[:space:]]from[[:space:]]" "$ROOT/$f" | grep -oE "'[^']+\.bicep'" | tr -d "'" || true); do
    case "$ref" in br/*|br:*|ts/*|ts:*) continue ;; esac
    target=$(cd "$ROOT/$(dirname "$f")" && cd "$(dirname "$ref")" 2>/dev/null && pwd -P || true)
    case "$target/" in
      "$ROOT/$component/"*) ;;
      *) error "$f" "'$ref' leaves the component. Reference other components as br/$ALIAS:<path>:v<version>" ;;
    esac
  done
done

finish
