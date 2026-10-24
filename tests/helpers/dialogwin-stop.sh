#!/usr/bin/env bash
# tests/helpers/dialogwin-stop.sh - stop the window-family fixture by pid.
set -uo pipefail
. "$(dirname "$0")/../../lib/common.sh"
PIDF="$STATE_DIR/dialogwin.pid"
[ -s "$PIDF" ] || { echo '{"ok":true,"stopped":false,"reason":"no pid"}'; exit 0; }
PID="$(tr -dc '0-9' < "$PIDF")"
if [ -n "$PID" ]; then
  winps -t 20 "Stop-Process -Id $PID -Force -ErrorAction SilentlyContinue" >/dev/null 2>&1 || true
fi
rm -f "$PIDF"
echo '{"ok":true,"stopped":true}'
