#!/usr/bin/env bash
# Release every component version that isn't released yet. Safe to run again: what exists is skipped.
#
#   --tags            tag each new version as <component>/v<version> at HEAD (the offline registry)
#   --push            push the new tags to origin
#   --registry        publish each version missing from the Azure Container Registry in platform.json
#                     and lock it, so a published version can never change underneath the people using it:
#                     the version on this branch and every released one (its git tag), which older pins
#                     still need. Init solutions are tagged, never published: they run before the registry exists.
#
# Run scripts/check-versions.sh first: it fails when a released version changed without a bump,
# which this script would otherwise skip without a word.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

tags=false
push=false
registry=false
while [ $# -gt 0 ]; do
  case "$1" in
    --tags) tags=true; shift ;;
    --push) push=true; shift ;;
    --registry) registry=true; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if $tags; then
  new=()
  for c in $(components); do
    tag=$(tag_of "$c" "$(version_of "$c")")
    if tag_exists "$tag"; then continue; fi
    git -C "$ROOT" tag "$tag" HEAD
    new+=("refs/tags/$tag")
    echo "tagged $tag"
    summary "- tagged \`$tag\`"
  done
  if $push && [ ${#new[@]} -gt 0 ]; then
    git -C "$ROOT" push origin "${new[@]}"
  fi
  echo "${#new[@]} new tag(s)"
fi

if $registry; then
  # The registry's subscription is the target of the init solution that deploys it
  acr=$(jq -r '.registry.name' "$ROOT/platform.json")
  stack_context "$(jq -r '.registry.config' "$ROOT/platform.json")"
  sub=$TARGET_ID
  server=$(az acr show --name "$acr" --subscription "$sub" --query loginServer --output tsv --only-show-errors)
  modulepath=$(jq -r --arg a "$ALIAS" '.moduleAliases.br[$a].modulePath' "$ROOT/bicepconfig.json")

  # Compile against local files, so the order of publishing doesn't matter
  work=$(mktemp -d)
  trap '"$ROOT/scripts/convert-registry-refs.sh" --restore "$work/refs.tsv"; rm -rf "$work"' EXIT
  GITHUB_STEP_SUMMARY="" "$ROOT/scripts/convert-registry-refs.sh" --state "$work/refs.tsv" > /dev/null

  published=0
  for c in $(components); do
    case "$c" in solutions/00-init-*) continue ;; esac
    current=$(version_of "$c")
    for version in $({ echo "$current"; git -C "$ROOT" tag --list "$c/v*" | sed "s|^$c/v||"; } | grep -E "$SEMVER_RE" | sort -u); do
      image="$modulepath/$c:v$version"
      if az acr repository show --name "$acr" --subscription "$sub" --image "$image" --output none --only-show-errors 2>/dev/null; then
        continue
      fi
      if [ "$version" = "$current" ]; then
        file="$ROOT/$c/main.bicep"
      else
        # A released version from its tag, its references converted like any other
        src="$ROOT/.refcache/publish/$(tag_of "$c" "$version")"
        rm -rf "$src"
        mkdir -p "$src"
        git -C "$ROOT" archive "refs/tags/$(tag_of "$c" "$version")" "$c" | tar -x -C "$src"
        # shellcheck disable=SC2046 # one argument per file
        GITHUB_STEP_SUMMARY="" "$ROOT/scripts/convert-registry-refs.sh" $(find "$src" -name '*.bicep') > /dev/null
        file="$src/$c/main.bicep"
      fi
      bicep publish "$file" --target "br:$server/$image"
      az acr repository update --name "$acr" --subscription "$sub" --image "$image" \
        --write-enabled false --delete-enabled false --output none --only-show-errors
      published=$((published + 1))
      echo "published and locked $server/$image"
      summary "- published \`br/$ALIAS:$c:v$version\`"
    done
  done
  echo "$published new version(s) in $server"
fi
