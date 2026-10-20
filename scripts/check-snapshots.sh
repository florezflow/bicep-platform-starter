#!/usr/bin/env bash
# Keep a committed snapshot of what every configuration deploys, and show how it changed.
# `bicep snapshot` resolves a .bicepparam into the resources it would create, entirely offline.
# The snapshot sits next to the config as <env>.snapshot.json, so a pull request shows the
# resolved change in its diff, not just the template change.
#
# Usage:
#   scripts/check-snapshots.sh [CONFIG...]                  fail if a snapshot is missing or out of date (CI)
#   scripts/check-snapshots.sh --update [CONFIG...]         write new snapshots, then review and commit them
#   scripts/check-snapshots.sh --against REF [CONFIG...]    report changes since the snapshots at a commit
#                                                           (deploy: REF = the last successful deployment)
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

mode=check
against=""
list=()
while [ $# -gt 0 ]; do
  case "$1" in
    --update) mode=update; shift ;;
    --against) mode=against; against=$2; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) list+=("$1"); shift ;;
  esac
done
if [ ${#list[@]} -eq 0 ]; then
  for p in $(config_files); do list+=("$p"); done
fi

work=$(mktemp -d)
state="$work/refs.tsv"
trap '"$ROOT/scripts/convert-registry-refs.sh" --restore "$state"; rm -rf "$work"' EXIT
if ! GITHUB_STEP_SUMMARY="" "$ROOT/scripts/convert-registry-refs.sh" --state "$state" > "$work/convert.log"; then
  cat "$work/convert.log"
  exit 1
fi

plain() { sed $'s/\x1b\\[[0-9;]*m//g'; }

# snapshot <config> <mode>: run bicep snapshot at the stack's own scope and name, output in $work/out
snapshot() {
  local name
  name=${1#solutions/}
  name=${name%%/*}
  stack_context "$name/$(basename "$1" .bicepparam)" > "$work/out" 2>&1 || return 2
  (cd "$ROOT" && bicep snapshot "$1" --mode "$2" "$SNAPSHOT_FLAG" "$TARGET_ID" --tenant-id "$TENANT_ID" \
    --location "$LOCATION" --deployment-name "$STACK_NAME") > "$work/out" 2>&1
}

report() { # <title> <file>: show a diff in the log and in the job summary
  plain < "$work/out"
  summary "<details><summary>$1</summary>"
  summary ""
  summary '```'
  summary "$(plain < "$work/out")"
  summary '```'
  summary "</details>"
}

for param in "${list[@]}"; do
  param=${param#./}
  snap="${param%.bicepparam}.snapshot.json"

  if [ "$mode" = against ]; then
    if ! git -C "$ROOT" cat-file -e "$against:$snap" 2>/dev/null; then
      echo "$param: no snapshot at $against, so everything is new"
      summary "- \`$param\`: no snapshot at \`$against\`, so everything is new"
      continue
    fi
    if [ -f "$ROOT/$snap" ]; then cp "$ROOT/$snap" "$work/current.json"; fi
    git -C "$ROOT" show "$against:$snap" > "$ROOT/$snap"
    if snapshot "$param" validate; then
      ok "$param: no change since $against"
      summary "- \`$param\`: no change since \`$against\`"
    elif grep -q 'Snapshot validation failed' "$work/out"; then
      echo "$param: changes since $against"
      report "$param: changes since $against" "$work/out"
    else
      error "$param" "bicep snapshot failed: $(plain < "$work/out" | head -5 | tr '\n' ' ')"
    fi
    if [ -f "$work/current.json" ]; then mv "$work/current.json" "$ROOT/$snap"; else rm -f "$ROOT/$snap"; fi
    continue
  fi

  if [ -f "$ROOT/$snap" ] && snapshot "$param" validate; then
    ok "$snap"
    continue
  fi

  if [ -f "$ROOT/$snap" ] && ! grep -q 'Snapshot validation failed' "$work/out"; then
    error "$param" "bicep snapshot failed: $(plain < "$work/out" | head -5 | tr '\n' ' ')"
  elif [ "$mode" = update ]; then
    if snapshot "$param" overwrite; then echo "wrote $snap"; else error "$param" "$(plain < "$work/out" | head -5 | tr '\n' ' ')"; fi
  elif [ -f "$ROOT/$snap" ]; then
    error "$snap" "out of date: this change alters what the config deploys. Run scripts/check-snapshots.sh --update, review the diff and commit it."
    report "$param: deployment changes" "$work/out"
  else
    error "$param" "no snapshot yet. Run scripts/check-snapshots.sh --update and commit $snap."
  fi
done

finish
