#!/usr/bin/env bash
# The pull request gates on a copy of the working tree: each one passes on a clean repo and fails
# with the right message when someone breaks the rule it guards. Needs git, jq and bicep.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=assert.sh
. "$here/assert.sh"

src=$(git -C "$here" rev-parse --show-toplevel)
repo=$(mktemp -d)
git clone -q "$src" "$repo" # the history and the release tags
(cd "$src" && git ls-files -co --exclude-standard | tar -cf - -T -) | tar -xf - -C "$repo" # plus what isn't committed
(cd "$src" && git ls-files --deleted) | while IFS= read -r f; do rm -f "$repo/$f"; done
cd "$repo" || exit 1
git config user.email test@example.com
git config user.name test
git add -A && git commit -qm "the working tree" --allow-empty

edit() { # <file> <sed expression>: change a file in place, the same way on macOS and Linux
  sed -i.bak "$2" "$1" && rm "$1.bak"
}

bump() { # <component> <version>: what the bump-version skill does
  jq --arg v "$2" '.version = $v' "$1/metadata.json" > "$1/m.json" && mv "$1/m.json" "$1/metadata.json"
  edit "$1/main.bicep" "s/^metadata version = '.*'/metadata version = '$2'/"
  printf '# Changelog\n\n## %s - 2026-10-20\n\n- Test.\n%s\n' "$2" "$(tail -n +2 "$1/CHANGELOG.md")" > "$1/CHANGELOG.md"
}

echo "-- a clean repo passes"
check "versions agree" scripts/check-versions.sh
check "every reference converts" scripts/convert-registry-refs.sh --state "$repo/.state"
check "prod's older pin is unpacked from its release tag" \
  test -f .refcache/solutions/02-workloads-000-sample-app/v1.0.0/solutions/02-workloads-000-sample-app/main.bicep
scripts/convert-registry-refs.sh --restore "$repo/.state"
check "restore leaves no change behind" git diff --exit-code
check "READMEs are current" scripts/update-readme.sh --check
check "snapshots are current" scripts/check-snapshots.sh
check "release tags are created" scripts/publish-components.sh --tags
# shellcheck disable=SC2016 # expands in the inner shell
check "every component's version is tagged" bash -c '. scripts/lib.sh; for c in $(components); do tag_exists "$(tag_of "$c" "$(version_of "$c")")" || { echo "no tag for $c"; exit 1; }; done'

echo "-- a released version can't change"
echo "// a change" >> modules/network/nsg/main.bicep
check_fails "a change without a bump fails" "already released" scripts/check-versions.sh
bump modules/network/nsg 1.0.1
check "with the bump it passes" scripts/check-versions.sh

echo "-- older pins build from their release tag"
check "the consumer of nsg v1.0.0 converts" scripts/convert-registry-refs.sh --state "$repo/.state"
check "nsg v1.0.0 is unpacked from its tag" test -f .refcache/modules/network/nsg/v1.0.0/modules/network/nsg/main.bicep
check "the consumer compiles" bicep build modules/network/app-network/main.bicep --stdout
scripts/convert-registry-refs.sh --restore "$repo/.state"
git checkout -q -- . && git clean -qfdx

echo "-- each rule fails with its message"
edit modules/network/app-network/main.bicep "s|modules/network/nsg:v1.0.0|modules/network/nsg:v1.0.2|"
check_fails "a version that doesn't exist" "nor a released tag" scripts/convert-registry-refs.sh
git checkout -q -- .

edit modules/network/vnet/main.bicep "s|'br/platform:types:v1.0.0'|'../../../types/main.bicep'|"
check_fails "a committed path into another component" "leaves the component" scripts/check-versions.sh
git checkout -q -- .

edit modules/network/vnet/main.bicep "s/^metadata version = '1.0.0'/metadata version = '1.0.9'/"
check_fails "template and metadata.json disagree" "metadata.json says 1.0.0" scripts/check-versions.sh
git checkout -q -- .

edit modules/network/app-network/main.bicep "s/'Address range of the subnet\.'/'Address range of the new subnet.'/"
check_fails "a changed description outdates the README" "out of date" scripts/update-readme.sh --check modules/network/app-network
git checkout -q -- .

edit modules/network/app-network/main.bicep "s|'Security rules for the subnet\.'|'![Optional](https://img.shields.io/badge/parameter-optional-green) Security rules.'|"
check_fails "a hand-written badge" "badge" scripts/update-readme.sh --check modules/network/app-network
git checkout -q -- .

edit modules/network/app-network/main.bicep "s|'Address range of the subnet\.'|'Address range of the subnet. Example: 10.20.16.0/26'|"
check_fails "an example in a description" "use @metadata({ example: … })" scripts/update-readme.sh --check modules/network/app-network
git checkout -q -- .

edit modules/network/app-network/main.bicep "s/param pServiceEndpoints/param serviceEndpoints/; s/: pServiceEndpoints$/: serviceEndpoints/"
check_fails "a parameter without its prefix" "parameter serviceEndpoints needs the prefix p" scripts/update-readme.sh --check modules/network/app-network
git checkout -q -- .

mkdir solutions/2-workloads-demo
check_fails "a solution folder outside the tiers" "solution folders are named <tier>-<NNN>-<name>" scripts/check-versions.sh
rmdir solutions/2-workloads-demo

jq 'del(.solutions["02-workloads-000-sample-app"].targets.prod)' platform.json > p.json && mv p.json platform.json
check_fails "a configuration without a target" "platform.json has no target for 02-workloads-000-sample-app in prod" scripts/check-versions.sh
git checkout -q -- .

jq '.solutions["02-workloads-000-sample-app"].targets.dev = {managementGroup: "contoso-canary-landingzones-corp"}' platform.json > p.json && mv p.json platform.json
check_fails "a target that doesn't match targetScope" "targetScope is 'subscription', but platform.json deploys 02-workloads-000-sample-app/dev at a management group" scripts/check-versions.sh
git checkout -q -- .

jq '.solutions["01-core-010-platform"].actionOnUnmanage = "deleteNothing"' platform.json > p.json && mv p.json platform.json
check_fails "an actionOnUnmanage Azure doesn't know" "solutions.01-core-010-platform.actionOnUnmanage is \"deleteNothing\"" scripts/check-versions.sh
git checkout -q -- .

edit solutions/00-init-010-module-registry/main.bicep "s|^targetScope = 'subscription'$|targetScope = 'subscription'\\
import { contextType } from 'br/platform:types:v1.0.0'|"
check_fails "a registry reference in an init solution" "an init solution runs before the registry exists" scripts/check-versions.sh
git checkout -q -- .

edit .github/workflows/deploy.yml "s|^          - 01-core-000-management-groups/dev$|          - 00-init-010-module-registry/prod\\
          - 01-core-000-management-groups/dev|"
check_fails "an init solution in the deploy workflow" "is deployed by hand" scripts/check-versions.sh
git checkout -q -- .

edit .github/workflows/deploy.yml "/^          - 01-core-010-platform\/prod$/d"
check_fails "a configuration missing from the deploy workflow" "01-core-010-platform/prod is missing from the config choices" scripts/check-versions.sh
git checkout -q -- .

app=solutions/02-workloads-000-sample-app/configurations/dev.bicepparam
edit "$app" "s|'10.20.16.0/24'|'10.20.17.0/24'|"
check_fails "a config change outdates its snapshot" "out of date" scripts/check-snapshots.sh "$app"

echo "-- a deployment compares with the last one"
git commit -qam "change the dev address space"
check_output "the change since the previous commit is reported" "10.20.17.0/26" \
  scripts/check-snapshots.sh --against HEAD~1 "$app"

rm -rf "$repo"
done_testing
