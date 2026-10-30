#!/usr/bin/env bash
# Runs one GarminDB sync. Records the time of the last successful run in
# $HEALTHDATA_DIR/last_success. A run started while another is in progress is skipped.
set -euo pipefail

HEALTHDATA_DIR=${HEALTHDATA_DIR:-/root/HealthData}
LOCK_FILE=${LOCK_FILE:-/tmp/sync.lock}
GARMINDB_CLI=${GARMINDB_CLI:-garmindb_cli.py}

log() { echo "[$(date -Iseconds)] $*"; }

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "sync already running, skipping"
  exit 0
fi

log "sync started"
mkdir -p "$HEALTHDATA_DIR"
# GarminDB writes garmindb.log in the working directory: keep it on the data volume.
cd "$HEALTHDATA_DIR"
output=$(mktemp)
trap 'rm -f "$output"' EXIT

set +e
"$GARMINDB_CLI" --all --download --import --analyze --latest 2>&1 | tee "$output"
code=${PIPESTATUS[0]}
set -e

# GarminDB exits 0 on these errors (bare sys.exit()), so detect them from its output.
if [ "$code" -eq 0 ] && grep -qE 'Failed to login!|Missing config:' "$output"; then
  code=1
fi

if [ "$code" -ne 0 ]; then
  log "sync failed (exit $code), end of garmindb.log:"
  tail -n 50 garmindb.log 2>/dev/null || true
  exit "$code"
fi

date -Iseconds >"$HEALTHDATA_DIR/last_success.tmp"
mv "$HEALTHDATA_DIR/last_success.tmp" "$HEALTHDATA_DIR/last_success"
log "sync succeeded"
