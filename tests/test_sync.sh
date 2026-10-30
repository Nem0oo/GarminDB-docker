#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

setup() {
  export HEALTHDATA_DIR="$T/data" LOCK_FILE="$T/sync.lock" GARMINDB_CLI="$T/garmindb_cli.py"
  mkdir -p "$HEALTHDATA_DIR"
}

test_success_writes_last_success() {
  setup; make_stub_cli "$T" 0
  bash "$SCRIPTS/sync.sh" >/dev/null 2>&1
  assert_eq 0 $? "exit code"
  assert_file "$HEALTHDATA_DIR/last_success"
  date -d "$(cat "$HEALTHDATA_DIR/last_success")" >/dev/null 2>&1 || fail "last_success not a date"
  assert_eq "--all --download --import --analyze --latest" "$(cat "$T/cli_args")" "cli args"
}

test_failure_keeps_last_success() {
  setup; make_stub_cli "$T" 3
  echo "2026-01-01T00:00:00+00:00" >"$HEALTHDATA_DIR/last_success"
  bash "$SCRIPTS/sync.sh" >/dev/null 2>&1
  assert_eq 3 $? "exit code"
  assert_eq "2026-01-01T00:00:00+00:00" "$(cat "$HEALTHDATA_DIR/last_success")" "last_success unchanged"
}

test_failure_without_previous() {
  setup; make_stub_cli "$T" 1
  bash "$SCRIPTS/sync.sh" >/dev/null 2>&1
  assert_eq 1 $? "exit code"
  assert_no_file "$HEALTHDATA_DIR/last_success"
}

test_concurrent_run_skipped() {
  setup; make_stub_cli "$T" 0 3
  bash "$SCRIPTS/sync.sh" >/dev/null 2>&1 &
  local first=$!
  sleep 0.5
  local start=$SECONDS out
  out=$(bash "$SCRIPTS/sync.sh" 2>&1)
  assert_eq 0 $? "second run exit code"
  [ $((SECONDS - start)) -le 1 ] || fail "second run did not exit immediately"
  [[ $out == *"already running"* ]] || fail "missing 'already running' message: $out"
  wait $first
  assert_eq 1 "$(wc -l <"$T/cli_args")" "cli invoked once"
}

run_tests
