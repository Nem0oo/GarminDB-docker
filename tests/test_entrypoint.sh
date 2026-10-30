#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

setup() {
  export STARTED_AT_FILE="$T/started_at" CRONTAB_FILE="$T/crontab" SUPERCRONIC="$T/supercronic"
  unset SYNC_SCHEDULE
  printf '#!/usr/bin/env bash\necho "$*" >"%s/supercronic_args"\n' "$T" >"$SUPERCRONIC"
  chmod +x "$SUPERCRONIC"
}
run_entrypoint() { bash "$SCRIPTS/entrypoint.sh" >/dev/null 2>&1; }

test_crontab_default() {
  setup; run_entrypoint
  assert_eq "0 4 * * * /usr/local/bin/sync.sh" "$(cat "$CRONTAB_FILE")" "default crontab"
}

test_crontab_from_schedule() {
  setup; export SYNC_SCHEDULE="30 2 * * 1-5"; run_entrypoint
  assert_eq "30 2 * * 1-5 /usr/local/bin/sync.sh" "$(cat "$CRONTAB_FILE")" "custom crontab"
}

test_started_at_written() {
  setup; run_entrypoint
  local v; v=$(cat "$STARTED_AT_FILE")
  [[ $v =~ ^[0-9]+$ ]] || fail "started_at not an integer: $v"
  [ $(( $(date +%s) - v )) -le 5 ] || fail "started_at not recent: $v"
}

test_execs_supercronic_with_crontab() {
  setup; run_entrypoint
  assert_eq "$CRONTAB_FILE" "$(cat "$T/supercronic_args")" "supercronic args"
}

run_tests
