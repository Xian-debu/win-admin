#!/usr/bin/env bash
# tests/helpers/deepwin-start.sh - launch the v1.3 deep-tree fixture (22 nested controls) and print its info.
set -uo pipefail
. "$(dirname "$0")/../../lib/common.sh"
# K58: stop fixture windows leaked by an interrupted or overlapping earlier run.
bash "$(dirname "$0")/kill-fixtures.sh" >/dev/null 2>&1 || true
TITLE="${1:-wa-deep}"
LAZY="${2:-}"
LAZYMS="${3:-600}"
mkdir -p "$APP_ROOT/tmp"
WIN="${WINADMIN_APP_ROOT:-/mnt/c/Users/Public/win-admin}"
cp "$(dirname "$0")/deepwin.ps1" "$WIN/tmp/wa-deepwin.ps1"
rm -f "$WIN/tmp/deepwin.json" "$WIN/tmp/deepwin.events.txt"
xtra=""
# -Lazy must live INSIDE the -ArgumentList array; appended outside it becomes a Start-Process parameter.
[ -n "$LAZY" ] && xtra=",'-Lazy','-LazyMs','$LAZYMS'"
winps -t 30 "Start-Process -FilePath powershell.exe -ArgumentList '-NoProfile','-STA','-WindowStyle','Normal','-ExecutionPolicy','Bypass','-File','$(wa_winpath "$WIN/tmp/wa-deepwin.ps1")','-Title','$TITLE','-Out','$(wa_winpath "$WIN/tmp/deepwin.json")'$xtra -PassThru | Select-Object -ExpandProperty Id" | tail -1 > "$STATE_DIR/deepwin.pid" 2>/dev/null
for i in $(seq 1 80); do
  [ -s "$WIN/tmp/deepwin.json" ] && jq -e . "$WIN/tmp/deepwin.json" >/dev/null 2>&1 && break
  sleep 0.25
done
[ -s "$WIN/tmp/deepwin.json" ] || { echo '{"ok":false,"code":"EXEC_DEEPWIN_TIMEOUT"}'; exit 5; }
jp="$(jq -r '.pid // empty' "$WIN/tmp/deepwin.json" 2>/dev/null)"
[ -n "$jp" ] && printf '%s\n' "$jp" > "$STATE_DIR/deepwin.pid"
jq -c '. + {ok:true}' "$WIN/tmp/deepwin.json"
