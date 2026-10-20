#!/usr/bin/env bash
# Tiny assertions for the test scripts. Source it; call `done_testing` at the end.
failures=0
out=$(mktemp)

check() { # <description> <command...>: passes when the command succeeds
  local what=$1; shift
  if "$@" > "$out" 2>&1; then echo "  ok    $what"; else echo "  FAIL  $what"; sed 's/^/        /' "$out" | tail -15; failures=$((failures + 1)); fi
}

check_fails() { # <description> <expected output> <command...>: passes when it fails and prints the text
  local what=$1 expected=$2; shift 2
  if "$@" > "$out" 2>&1; then
    echo "  FAIL  $what (succeeded)"; failures=$((failures + 1))
  elif grep -qF -- "$expected" "$out"; then
    echo "  ok    $what"
  else
    echo "  FAIL  $what (no \"$expected\")"; sed 's/^/        /' "$out" | tail -15; failures=$((failures + 1))
  fi
}

check_output() { # <description> <expected output> <command...>: passes when it succeeds and prints the text
  local what=$1 expected=$2; shift 2
  if ! "$@" > "$out" 2>&1; then
    echo "  FAIL  $what (failed)"; sed 's/^/        /' "$out" | tail -15; failures=$((failures + 1))
  elif grep -qF -- "$expected" "$out"; then
    echo "  ok    $what"
  else
    echo "  FAIL  $what (no \"$expected\")"; sed 's/^/        /' "$out" | tail -15; failures=$((failures + 1))
  fi
}

equals() { # <description> <actual> <expected>
  if [ "$2" = "$3" ]; then echo "  ok    $1"; else echo "  FAIL  $1: expected '$3', got '$2'"; failures=$((failures + 1)); fi
}

done_testing() { [ "$failures" -eq 0 ]; }
