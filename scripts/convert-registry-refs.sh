#!/usr/bin/env bash
# Point registry references at local files, in the working copy only, so a pull request can build
# component versions that aren't released yet. Nothing this script changes is ever committed.
#
# Each br/platform:<component>:v<version> reference resolves to:
#   1. the source on this branch, if <component>/metadata.json has that version
#   2. the released source, if the git tag <component>/v<version> exists (unpacked into .refcache/)
#   3. an error otherwise: a typo, or a component that changed without a version bump
#
# Usage:
#   scripts/convert-registry-refs.sh [--state FILE] [FILE...]   convert (default: every committed file)
#   scripts/convert-registry-refs.sh --restore FILE             put the references back
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

state=""
restore=""
files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --state) state=$2; shift 2 ;;
    --restore) restore=$2; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) files+=("$1"); shift ;;
  esac
done

replace_in_file() { # <file> <from> <to>: replace one quoted string, literally
  local file=$1 from=$2 to=$3 content
  content=$(cat "$file"; printf x)
  content=${content%x}
  content=${content//"'$from'"/"'$to'"}
  printf '%s' "$content" > "$file"
}

if [ -n "$restore" ]; then
  [ -f "$restore" ] || exit 0
  while IFS=$'\t' read -r file from to; do
    if [ -f "$file" ]; then replace_in_file "$file" "$to" "$from"; fi
  done < "$restore"
  rm -f "$restore"
  exit 0
fi

converted=0
summary "| File | Reference | Built from |"
summary "|---|---|---|"

# materialize <component> <version> <tag>: unpack a released version and convert its references too
materialize() {
  local path=$1 tag=$3 dest="$ROOT/.refcache/$3" f
  [ -f "$dest/.done" ] && return 0
  rm -rf "$dest"
  mkdir -p "$dest"
  git -C "$ROOT" archive "refs/tags/$tag" "$path" | tar -x -C "$dest"
  for f in $(cd "$dest" && find . -name '*.bicep' | sed 's|^\./||'); do
    convert_file "$dest/$f"
  done
  touch "$dest/.done"
}

# resolve <component> <version>: sets RESOLVED (absolute path) and FROM, or returns 1
resolve() {
  local path=$1 version=$2 tag
  if [ -f "$ROOT/$path/metadata.json" ] && [ "$(version_of "$path")" = "$version" ]; then
    RESOLVED="$ROOT/$path/main.bicep"
    FROM="source on this branch"
    return 0
  fi
  tag=$(tag_of "$path" "$version")
  if tag_exists "$tag"; then
    materialize "$path" "$version" "$tag"
    RESOLVED="$ROOT/.refcache/$tag/$path/main.bicep"
    FROM="release tag \`$tag\`"
    return 0
  fi
  return 1
}

convert_file() {
  local file=$1 dir ref path version rel shown
  dir=$(cd "$(dirname "$file")" && pwd -P)
  shown=${file#"$ROOT"/}
  for ref in $(registry_refs "$file"); do
    path=${ref#br/"$ALIAS":}
    version=${path##*:v}
    path=${path%:v*}
    if ! resolve "$path" "$version"; then
      error "$shown" "$ref is neither the version on this branch ($(version_of "$path" || true)) nor a released tag. A typo, or a change without a version bump?"
      continue
    fi
    rel=$(relpath "$dir" "$RESOLVED")
    replace_in_file "$file" "$ref" "$rel"
    case "$shown" in
      .refcache/*) ;;
      *)
        converted=$((converted + 1))
        echo "$shown: $ref -> $rel"
        summary "| \`$shown\` | \`$ref\` | $FROM |"
        if [ -n "$state" ]; then printf '%s\t%s\t%s\n' "$file" "$ref" "$rel" >> "$state"; fi
        ;;
    esac
  done
}

if [ ${#files[@]} -eq 0 ]; then
  for f in $(bicep_files); do files+=("$ROOT/$f"); done
fi
for f in ${files[@]+"${files[@]}"}; do
  case "$f" in /*) ;; *) f="$PWD/$f" ;; esac
  convert_file "$f"
done

echo "$converted reference(s) now point at local files."
finish
