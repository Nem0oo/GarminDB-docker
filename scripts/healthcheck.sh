#!/usr/bin/env bash
# Healthy (exit 0) when the last successful sync is recent enough.
# Without any successful sync yet, healthy only during the first MAX_AGE_HOURS after start.
HEALTHDATA_DIR=${HEALTHDATA_DIR:-/root/HealthData}
STARTED_AT_FILE=${STARTED_AT_FILE:-/tmp/started_at}
MAX_AGE_HOURS=${MAX_AGE_HOURS:-36}

now=$(date +%s)
max_age=$((MAX_AGE_HOURS * 3600))
success_file="$HEALTHDATA_DIR/last_success"

if [ -f "$success_file" ]; then
  content=$(cat "$success_file")
  # `date -d ""` means "today 00:00", so an empty file must be rejected explicitly.
  if [ -z "$content" ] || ! last=$(date -d "$content" +%s 2>/dev/null); then
    echo "unhealthy: unreadable last_success: '$content'"; exit 1
  fi
  age=$((now - last))
  if [ "$age" -le "$max_age" ]; then
    echo "healthy: last success $((age / 3600))h ago"; exit 0
  fi
  echo "unhealthy: last success $((age / 3600))h ago (max ${MAX_AGE_HOURS}h)"; exit 1
fi

started=$(cat "$STARTED_AT_FILE" 2>/dev/null)
if [[ $started =~ ^[0-9]+$ ]] && [ $((now - started)) -le "$max_age" ]; then
  echo "healthy: no successful sync yet, started $(((now - started) / 3600))h ago"; exit 0
fi
echo "unhealthy: no successful sync within ${MAX_AGE_HOURS}h of start"; exit 1
