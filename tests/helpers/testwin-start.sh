#!/usr/bin/env bash
# tests/helpers/testwin-start.sh - launch the repo's own test window (never the user's Notepad) and print its info JSON.
# usage: testwin-start.sh [TITLE]
set -uo pipefail
. "$(dirname "$0")/../../lib/common.sh"
# K58: stop fixture windows leaked by an interrupted or overlapping earlier run;
# a stale window at the same coordinates silently steals clicks from this one.
bash "$(dirname "$0")/kill-fixtures.sh" >/dev/null 2>&1 || true
TITLE="${1:-wa-testwin}"
mkdir -p "$APP_ROOT/tmp"
WIN="${WINADMIN_APP_ROOT:-/mnt/c/Users/Public/win-admin}"
cp "$(dirname "$0")/testwin.ps1" "$WIN/tmp/wa-testwin.ps1"
rm -f "$WIN/tmp/testwin.json"
winps -t 30 "Start-Process -FilePath powershell.exe -ArgumentList '-NoProfile','-STA','-WindowStyle','Normal','-ExecutionPolicy','Bypass','-File','$(wa_winpath "$WIN/tmp/wa-testwin.ps1")','-Title','$TITLE' -PassThru | Select-Object -ExpandProperty Id" | tail -1 > "$STATE_DIR/testwin.pid" 2>/dev/null
for i in $(seq 1 80); do
  [ -s "$WIN/tmp/testwin.json" ] && jq -e . "$WIN/tmp/testwin.json" >/dev/null 2>&1 && break
  sleep 0.25
done
[ -s "$WIN/tmp/testwin.json" ] || { echo '{"ok":false,"code":"EXEC_TESTWIN_TIMEOUT"}'; exit 5; }
# K61: record the pid that really owns the window (winps -PassThru returns the
# launcher), so the stop script and the leak sweep agree on what to kill.
jp="$(jq -r '.pid // empty' "$WIN/tmp/testwin.json" 2>/dev/null)"
[ -n "$jp" ] && printf '%s\n' "$jp" > "$STATE_DIR/testwin.pid"
jq -c '. + {ok:true}' "$WIN/tmp/testwin.json"
