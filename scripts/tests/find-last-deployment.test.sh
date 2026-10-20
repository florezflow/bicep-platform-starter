#!/usr/bin/env bash
# find-last-deployment.sh against fake GitHub deployment records
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=assert.sh
. "$here/assert.sh"

# A repo with two commits, so the script can check that a recorded commit is in the history
repo=$(mktemp -d)
mkdir "$repo/scripts"
cp "$here/../lib.sh" "$here/../find-last-deployment.sh" "$repo/scripts/"
git -C "$repo" init -q -b main
git -C "$repo" -c user.email=test@example.com -c user.name=test commit -q --allow-empty -m one
old=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" -c user.email=test@example.com -c user.name=test commit -q --allow-empty -m two
new=$(git -C "$repo" rev-parse HEAD)
gone=0000000000000000000000000000000000000abc   # not in the history: force-pushed away
find="$repo/scripts/find-last-deployment.sh"

FIXTURES=$(mktemp -d)
export FIXTURES

record() { # <id> <sha> <action> <states...>: a deployment record and its statuses
  local id=$1 sha=$2 action=$3; shift 3
  jq -n --argjson id "$id" --arg sha "$sha" --arg a "$action" \
    '{id: $id, sha: $sha, environment: "dev", task: "stack:02-workloads-000-sample-app-dev", payload: {action: $a}}' >> "$FIXTURES/list"
  printf '%s\n' "$@" | jq -R '{state: .}' | jq -s . > "$FIXTURES/statuses-$id.json"
}
use() { jq -s . "$FIXTURES/list" > "$FIXTURES/deployments.json"; rm -f "$FIXTURES/list"; }

record 4 "$new" deploy failure
record 3 "$gone" deploy success
record 2 "$old" deploy inactive success
record 1 "$old" deploy success
use
equals "skips failures and history it can't see; inactive after success still counts" \
  "$("$find" dev 02-workloads-000-sample-app-dev 2>/dev/null)" "$old deploy"

record 2 "$new" retire success
record 1 "$old" deploy success
use
equals "reports a retirement as the last action" "$("$find" dev 02-workloads-000-sample-app-dev)" "$new retire"

record 1 "$old" deploy failure
use
equals "nothing when no deployment succeeded" "$("$find" dev 02-workloads-000-sample-app-dev)" ""

equals "nothing for another environment" "$("$find" prod 02-workloads-000-sample-app-dev)" ""

rm -rf "$FIXTURES" "$repo"
done_testing
