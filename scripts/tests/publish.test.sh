#!/usr/bin/env bash
# publish-components.sh --registry against a fake az and bicep: a fresh registry gets every version
# on the branch and every released one older pins still need, each from its own source and locked;
# a second run publishes nothing. Needs git and jq.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=assert.sh
. "$here/assert.sh"

src=$(git -C "$here" rev-parse --show-toplevel)
repo=$(mktemp -d)
git clone -q "$src" "$repo" # the history and the release tags
(cd "$src" && git ls-files -co --exclude-standard | tar -cf - -T -) | tar -xf - -C "$repo" # plus what isn't committed
cd "$repo" || exit 1
repo=$(pwd -P) # what the scripts see (on macOS /var is /private/var)
git -c user.email=test@example.com -c user.name=test commit -qam "the working tree" --allow-empty

fake=$(mktemp -d)
export AZ_LOG="$fake/calls.log" REGISTRY="$fake/registry.txt"
touch "$REGISTRY"
cat > "$fake/az" <<'FAKE'
#!/usr/bin/env bash
echo "az $*" >> "$AZ_LOG"
image=$(printf '%s\n' "$@" | grep -A1 -x -- --image | tail -1)
case "$*" in
  "acr show"*) echo registry.example.azurecr.io ;;
  "acr repository show"*) grep -qxF "$image" "$REGISTRY" ;;
esac
FAKE
# bicep publish: records the source and the target, and refuses a source that still points at the registry
cat > "$fake/bicep" <<'FAKE'
#!/usr/bin/env bash
echo "bicep $*" >> "$AZ_LOG"
if grep -l "'br/platform:" "$(dirname "$2")"/*.bicep 2>/dev/null; then echo "registry reference left in $2" >&2; exit 1; fi
echo "${4#br:registry.example.azurecr.io/}" >> "$REGISTRY"
FAKE
chmod +x "$fake/az" "$fake/bicep"
export PATH="$fake:$PATH"

# What a fresh registry should get: each component's version on the branch and its released ones
all_versions() {
  # shellcheck source=../lib.sh
  . scripts/lib.sh
  for c in $(components); do
    case "$c" in solutions/00-init-*) continue ;; esac
    { version_of "$c"; git tag --list "$c/v*" | sed "s|^$c/v||"; } | sort -u | sed "s|^|bicep/$c:v|"
  done | sort
}
expected=$(all_versions)

echo "-- a fresh registry"
check "publishes" scripts/publish-components.sh --registry
equals "every version on the branch and every released one" "$(sort "$REGISTRY")" "$expected"
check "the older pins are among them" bash -c "grep -qx 'bicep/modules/storage/account:v1.0.0' '$REGISTRY' && grep -qx 'bicep/solutions/02-workloads-000-sample-app:v1.0.0' '$REGISTRY'"
check "a released version is published from its tag" \
  grep -q "bicep publish $repo/.refcache/publish/modules/storage/account/v1.0.0/modules/storage/account/main.bicep" "$AZ_LOG"
check "the version on the branch from the branch" \
  grep -q "bicep publish $repo/modules/storage/account/main.bicep --target br:registry.example.azurecr.io/bicep/modules/storage/account:v$(jq -r .version modules/storage/account/metadata.json)" "$AZ_LOG"
check "init solutions are never published" bash -c "! grep -q 00-init '$REGISTRY'"
equals "each one is locked" "$(grep -c 'acr repository update .*--write-enabled false --delete-enabled false' "$AZ_LOG")" "$(wc -l < "$REGISTRY" | tr -d ' ')"
check "the working tree is restored" git diff --exit-code

echo "-- a second run"
rm -f "$AZ_LOG"
check_output "publishes nothing" "0 new version(s)" scripts/publish-components.sh --registry
check "calls bicep not once" bash -c "! grep -q '^bicep' '$AZ_LOG'"

rm -rf "$fake" "$repo"
done_testing
