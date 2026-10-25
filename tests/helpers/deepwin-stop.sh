#!/usr/bin/env bash
# tests/helpers/deepwin-stop.sh - stop the deep-tree fixture by its recorded pid.
set -uo pipefail
. "$(dirname "$0")/../../lib/common.sh"
P="$STATE_DIR/deepwin.pid"
[ -s "$P" ] || exit 0
PID="$(tr -d "[:space:]" < "$P")"
if [ -n "$PID" ]; then
  winps -t 20 "Stop-Process -Id $PID -Force -ErrorAction SilentlyContinue" >/dev/null 2>&1 || true
fi
rm -f "$P"
