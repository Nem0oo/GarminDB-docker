#!/usr/bin/env bash
# Records the start time (used by healthcheck.sh), writes the crontab from
# SYNC_SCHEDULE and hands over to supercronic.
set -euo pipefail

STARTED_AT_FILE=${STARTED_AT_FILE:-/tmp/started_at}
CRONTAB_FILE=${CRONTAB_FILE:-/tmp/crontab}
SYNC_SCHEDULE=${SYNC_SCHEDULE:-0 4 * * *}

date +%s >"$STARTED_AT_FILE"
echo "$SYNC_SCHEDULE /usr/local/bin/sync.sh" >"$CRONTAB_FILE"
exec "${SUPERCRONIC:-supercronic}" "$CRONTAB_FILE"
