#!/usr/bin/env bash
# Runs every tests/test_*.sh; exits non-zero if any file fails.
cd "$(dirname "$0")" || exit 1
status=0
for f in test_*.sh; do
  echo "== $f"
  bash "$f" || status=1
done
exit $status
