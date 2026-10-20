#!/usr/bin/env bash
# guard/check.sh - single choke point for every primitive (D6).
# M1 scope: read-only operations are always allowed; anything that injects input is denied
# until M3 ships grant/pause handling (S1 requires exit 4 with zero pixel change).
set -uo pipefail
. "$(dirname "$0")/../lib/common.sh"

mode="${1:-read}"

if [ "$mode" = "read" ]; then
  exit 0
fi

if [ -f "$STATE_DIR/pause.flag" ]; then
  wa_err_json GUARD_PAUSED "pause.flag present; input operations are paused"
  exit 4
fi

case "$mode" in
  input|write)
    wa_err_json GUARD_NO_GRANT "input operations require a valid grant.json (M3); read-only for now"
    exit 4
    ;;
  *)
    wa_err_json ARG_BAD_MODE "unknown mode: $mode"
    exit 2
    ;;
esac
