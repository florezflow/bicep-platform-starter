#!/usr/bin/env bash
# Generate every component's README.md from its compiled template, so the docs can't drift from
# the code. A missing @description fails, and so does a hand-written badge: required or optional
# comes from the compiler, not from the author.
#
# Usage:
#   scripts/update-readme.sh [COMPONENT...]           write the READMEs
#   scripts/update-readme.sh --check [COMPONENT...]   fail if a committed README is out of date (CI)
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

check=false
list=()
while [ $# -gt 0 ]; do
  case "$1" in
    --check) check=true; shift ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) list+=("${1%/}"); shift ;;
  esac
done
if [ ${#list[@]} -eq 0 ]; then
  for c in $(components); do list+=("$c"); done
fi

# Build against local files; the trap puts the registry references back
work=$(mktemp -d)
state="$work/refs.tsv"
trap '"$ROOT/scripts/convert-registry-refs.sh" --restore "$state"; rm -rf "$work"' EXIT
if ! GITHUB_STEP_SUMMARY="" "$ROOT/scripts/convert-registry-refs.sh" --state "$state" > "$work/convert.log"; then
  cat "$work/convert.log"
  exit 1
fi

for c in "${list[@]}"; do
  rm -f "$work/arm.json"   # never render the previous component's template after a failed build
  if ! bicep build "$ROOT/$c/main.bicep" --outfile "$work/arm.json" 2> "$work/build.log"; then
    error "$c/main.bicep" "bicep build failed: $(grep -m3 -i error "$work/build.log" | tr '\n' ' ')"
    continue
  fi

  problems=$(jq -r -f "$ROOT/scripts/describe-lint.jq" "$work/arm.json")
  if [ -n "$problems" ]; then
    while IFS= read -r problem; do error "$c/main.bicep" "$problem"; done <<< "$problems"
    continue
  fi

  jq -r --arg path "$c" --arg alias "$ALIAS" -f "$ROOT/scripts/readme.jq" "$work/arm.json" > "$work/README.md"

  if $check; then
    if cmp -s "$work/README.md" "$ROOT/$c/README.md"; then
      ok "$c/README.md"
    else
      error "$c/README.md" "out of date. Run scripts/update-readme.sh and commit the result."
      diff -u "$ROOT/$c/README.md" "$work/README.md" 2>/dev/null | head -20 || true
    fi
  elif cmp -s "$work/README.md" "$ROOT/$c/README.md"; then
    ok "$c/README.md unchanged"
  else
    cp "$work/README.md" "$ROOT/$c/README.md"
    echo "wrote $c/README.md"
  fi
done

finish
