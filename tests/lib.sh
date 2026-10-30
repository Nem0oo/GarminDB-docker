# Shared helpers for shell tests. Sourced by tests/test_*.sh.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$REPO_ROOT/scripts"
FAILURES=0

fail() { echo "  FAIL: $*"; FAILURES=$((FAILURES + 1)); }

assert_eq() { # expected actual msg
  [ "$1" = "$2" ] || fail "$3 (expected '$1', got '$2')"
}

assert_file() { [ -f "$1" ] || fail "expected file $1"; }
assert_no_file() { [ ! -e "$1" ] || fail "unexpected file $1"; }

# make_stub_cli <dir> <exit_code> [sleep_seconds] [stdout_message] [log_message]
# Writes <dir>/garmindb_cli.py: appends its args to <dir>/cli_args and its working dir to
# <dir>/cli_pwd, prints stdout_message, writes log_message to ./garmindb.log (as GarminDB
# does), sleeps, exits.
make_stub_cli() {
  local dir=$1 code=$2 nap=${3:-0} msg=${4:-} logmsg=${5:-}
  cat >"$dir/garmindb_cli.py" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$dir/cli_args"
pwd >"$dir/cli_pwd"
[ -n "$msg" ] && echo "$msg"
[ -n "$logmsg" ] && echo "$logmsg" >garmindb.log
sleep $nap
exit $code
EOF
  chmod +x "$dir/garmindb_cli.py"
}

# Runs each function named test_* in the calling file, in a fresh temp dir ($T).
run_tests() {
  local t
  for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
    T=$(mktemp -d)
    # Each test runs in a subshell; its assertion failures become its exit status.
    if ( FAILURES=0; cd "$T" && "$t"; [ "$FAILURES" -eq 0 ] ); then
      echo "ok   $t"
    else
      echo "FAIL $t"; FAILURES=$((FAILURES + 1))
    fi
    rm -rf "$T"
  done
  [ "$FAILURES" -eq 0 ]
}
