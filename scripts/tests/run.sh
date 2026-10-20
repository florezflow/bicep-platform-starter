#!/usr/bin/env bash
# Run every scripts/tests/*.test.sh and fail if one fails. Usage: scripts/tests/run.sh
set -uo pipefail
cd "$(dirname "$0")" || exit 1
failed=0
for t in *.test.sh; do
  echo "== $t"
  if ! bash "$t"; then failed=$((failed + 1)); fi
done
echo
if [ "$failed" -gt 0 ]; then echo "$failed test file(s) failed"; exit 1; fi
echo "all tests passed"
