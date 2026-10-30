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
code=0
"$GARMINDB_CLI" --all --download --import --analyze --latest || code=$?

if [ "$code" -ne 0 ]; then
  log "sync failed (exit $code)"
  exit "$code"
fi

mkdir -p "$HEALTHDATA_DIR"
date -Iseconds >"$HEALTHDATA_DIR/last_success.tmp"
mv "$HEALTHDATA_DIR/last_success.tmp" "$HEALTHDATA_DIR/last_success"
log "sync succeeded"
