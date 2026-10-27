#!/usr/bin/env bash
# tests/helpers/selectwin-start.sh - launch the v1.4 select-control fixture and print its info.
set -uo pipefail
. "$(dirname "$0")/../../lib/common.sh"
# K58: stop fixture windows leaked by an interrupted or overlapping earlier run;
# a stale window at the same coordinates silently steals clicks from this one.
bash "$(dirname "$0")/kill-fixtures.sh" >/dev/null 2>&1 || true
TITLE="${1:-wa-select}"
mkdir -p "$APP_ROOT/tmp"
WIN="${WINADMIN_APP_ROOT:-/mnt/c/Users/Public/win-admin}"
cp "$(dirname "$0")/selectwin.ps1" "$WIN/tmp/wa-selectwin.ps1"
rm -f "$WIN/tmp/selectwin.json" "$WIN/tmp/selectwin.err" "$WIN/tmp/selectwin.out" "$WIN/tmp/selectwin-error.txt" "$WIN/tmp/selectwin-events.txt"
# K73: fire and forget. winps cannot see EOF while the started process holds its
# stdout pipe, so waiting for it costs the full winps timeout (observed 30s per
# fixture start). The pid that owns the window is read from the fixture JSON below.
( winps -t 25 "Start-Process -FilePath powershell.exe -ArgumentList '-NoLogo','-NoProfile','-STA','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File','$(wa_winpath "$WIN/tmp/wa-selectwin.ps1")','-Title','$TITLE' -RedirectStandardError '$(wa_winpath "$WIN/tmp/selectwin.err")' -RedirectStandardOutput '$(wa_winpath "$WIN/tmp/selectwin.out")' -PassThru | Select-Object -ExpandProperty Id" >/dev/null 2>&1 & )
for i in $(seq 1 80); do
  [ -s "$WIN/tmp/selectwin.json" ] && jq -e . "$WIN/tmp/selectwin.json" >/dev/null 2>&1 && break
  sleep 0.25
done
[ -s "$WIN/tmp/selectwin.json" ] || { echo '{"ok":false,"code":"EXEC_SELECTWIN_TIMEOUT"}'; exit 5; }
jp="$(jq -r '.pid // empty' "$WIN/tmp/selectwin.json" 2>/dev/null)"
[ -n "$jp" ] && printf '%s\n' "$jp" > "$STATE_DIR/selectwin.pid"
jq -c '. + {ok:true}' "$WIN/tmp/selectwin.json"
