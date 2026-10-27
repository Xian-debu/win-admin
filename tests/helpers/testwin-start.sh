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
rm -f "$WIN/tmp/testwin.json" "$WIN/tmp/testwin.err" "$WIN/tmp/testwin.out" "$WIN/tmp/testwin-error.txt"
# K73: fire and forget. winps cannot see EOF while the started process holds its
# stdout pipe, so waiting for it costs the full winps timeout (observed 30s per
# fixture start). The pid that owns the window is read from the fixture JSON below.
( winps -t 25 "Start-Process -FilePath powershell.exe -ArgumentList '-NoLogo','-NoProfile','-STA','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File','$(wa_winpath "$WIN/tmp/wa-testwin.ps1")','-Title','$TITLE' -RedirectStandardError '$(wa_winpath "$WIN/tmp/testwin.err")' -RedirectStandardOutput '$(wa_winpath "$WIN/tmp/testwin.out")' -PassThru | Select-Object -ExpandProperty Id" >/dev/null 2>&1 & )
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
