#!/usr/bin/env bash
# Build every template and configuration against local files, with the linter rules from
# bicepconfig.json. What the pull request checks, runnable before you push.
#
# Usage: scripts/build.sh
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

work=$(mktemp -d)
trap '"$ROOT/scripts/convert-registry-refs.sh" --restore "$work/refs.tsv"; rm -rf "$work"' EXIT
"$ROOT/scripts/convert-registry-refs.sh" --state "$work/refs.tsv"
echo

# annotate: turn Bicep diagnostics ("<file>(<line>,<col>) : Warning <rule>: <text>") into annotations
annotate() {
  local file line col level text
  while IFS= read -r diagnostic; do
    if [[ ! "$diagnostic" =~ ^(.+)\(([0-9]+),([0-9]+)\)\ :\ (Error|Warning|Info)\ (.*)$ ]]; then
      echo "$diagnostic"
      continue
    fi
    file=${BASH_REMATCH[1]#"$ROOT"/} line=${BASH_REMATCH[2]} col=${BASH_REMATCH[3]}
    level=${BASH_REMATCH[4]} text=${BASH_REMATCH[5]}
    if [ "$level" = Error ]; then errors=$((errors + 1)); fi
    if [ "$level" = Warning ]; then warnings=$((warnings + 1)); fi
    if in_actions && [ "$level" != Info ]; then
      echo "::$(echo "$level" | tr '[:upper:]' '[:lower:]') file=$file,line=$line,col=$col::$text"
    else
      echo "$file:$line:$col $level $text"
    fi
  done
}

for f in $(bicep_files); do
  case "$f" in
    *.bicepparam) build=(build-params "$ROOT/$f" --stdout) ;;
    *) build=(build "$ROOT/$f" --stdout) ;;
  esac
  before=$errors
  status=0
  bicep "${build[@]}" > /dev/null 2> "$work/log" || status=$?
  annotate < "$work/log"
  if [ "$status" -ne 0 ] && [ "$errors" -eq "$before" ]; then
    error "$f" "bicep ${build[0]} failed"
  fi
  if [ "$errors" -eq "$before" ]; then ok "$f"; fi
done

finish
