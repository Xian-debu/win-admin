#!/usr/bin/env bash
# tests/helpers/testwin-stop.sh - close the test window we started, by the pid recorded in its info JSON.
set -uo pipefail
. "$(dirname "$0")/../../lib/common.sh"
WIN="${WINADMIN_APP_ROOT:-/mnt/c/Users/Public/win-admin}"
pid="$(jq -r '.pid' "$WIN/tmp/testwin.json" 2>/dev/null || true)"
if [ -z "$pid" ] || [ "$pid" = "null" ]; then echo '{"ok":true,"stopped":false}'; exit 0; fi
winps -t 20 "Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue; 'ok'" | tail -1 >/dev/null
printf '{"ok":true,"stopped":true,"pid":%s}\n' "$pid"
