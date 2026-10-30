#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

setup() {
  export HEALTHDATA_DIR="$T/data" STARTED_AT_FILE="$T/started_at"
  unset MAX_AGE_HOURS
  mkdir -p "$HEALTHDATA_DIR"
}
ago_iso() { date -Iseconds -d "@$(( $(date +%s) - $1 ))"; }   # seconds ago → ISO
ago_epoch() { echo $(( $(date +%s) - $1 )); }
check() { bash "$SCRIPTS/healthcheck.sh" >/dev/null 2>&1; echo $?; }

test_recent_success_healthy() {
  setup; ago_iso 3600 >"$HEALTHDATA_DIR/last_success"; ago_epoch 7200 >"$STARTED_AT_FILE"
  assert_eq 0 "$(check)" "recent success"
}

test_stale_success_unhealthy_even_after_restart() {
  setup; ago_iso $((40 * 3600)) >"$HEALTHDATA_DIR/last_success"; ago_epoch 60 >"$STARTED_AT_FILE"
  assert_eq 1 "$(check)" "stale success after restart"
}

test_missing_success_grace_period() {
  setup; ago_epoch 3600 >"$STARTED_AT_FILE"
  assert_eq 0 "$(check)" "grace period"
}

test_missing_success_after_grace() {
  setup; ago_epoch $((37 * 3600)) >"$STARTED_AT_FILE"
  assert_eq 1 "$(check)" "grace expired"
}

test_missing_both_unhealthy() {
  setup
  assert_eq 1 "$(check)" "no started_at, no last_success"
}

test_corrupt_last_success_unhealthy() {
  setup; ago_epoch 60 >"$STARTED_AT_FILE"
  : >"$HEALTHDATA_DIR/last_success"
  assert_eq 1 "$(check)" "empty last_success"
  echo "not-a-date" >"$HEALTHDATA_DIR/last_success"
  assert_eq 1 "$(check)" "garbage last_success"
}

test_max_age_override() {
  setup; export MAX_AGE_HOURS=2
  ago_iso $((3 * 3600)) >"$HEALTHDATA_DIR/last_success"
  assert_eq 1 "$(check)" "MAX_AGE_HOURS=2"
}

run_tests
