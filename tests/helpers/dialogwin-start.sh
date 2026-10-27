#!/usr/bin/env bash
# tests/helpers/dialogwin-start.sh - launch the window-family fixture (main + owned child + other).
set -uo pipefail
. "$(dirname "$0")/../../lib/common.sh"
# K58: stop fixture windows leaked by an interrupted or overlapping earlier run;
# a stale window at the same coordinates silently steals clicks from this one.
bash "$(dirname "$0")/kill-fixtures.sh" >/dev/null 2>&1 || true
mkdir -p "$APP_ROOT/tmp"
WIN="${WINADMIN_APP_ROOT:-/mnt/c/Users/Public/win-admin}"
cp "$(dirname "$0")/dialogwin.ps1" "$WIN/tmp/wa-dialogwin.ps1"
rm -f "$WIN/tmp/dialogwin.json" "$WIN/tmp/dialogwin.err" "$WIN/tmp/dialogwin.out" "$WIN/tmp/dialogwin-error.txt" "$WIN/tmp/dialogwin-events.txt"
CMD="Start-Process -FilePath powershell.exe -ArgumentList '-NoLogo','-NoProfile','-STA','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File','$(wa_winpath "$WIN/tmp/wa-dialogwin.ps1")' -RedirectStandardError '$(wa_winpath "$WIN/tmp/dialogwin.err")' -RedirectStandardOutput '$(wa_winpath "$WIN/tmp/dialogwin.out")' -PassThru | Select-Object -ExpandProperty Id"
winps -t 30 "$CMD" | tail -1 > "$STATE_DIR/dialogwin.pid" 2>/dev/null
for i in $(seq 1 80); do
  [ -s "$WIN/tmp/dialogwin.json" ] && jq -e . "$WIN/tmp/dialogwin.json" >/dev/null 2>&1 && break
  sleep 0.25
done
[ -s "$WIN/tmp/dialogwin.json" ] || { echo '{"ok":false,"code":"EXEC_DIALOGWIN_TIMEOUT"}'; exit 5; }
# K61: record the pid that really owns the window (winps -PassThru returns the
# launcher), so the stop script and the leak sweep agree on what to kill.
jp="$(jq -r '.pid // empty' "$WIN/tmp/dialogwin.json" 2>/dev/null)"
[ -n "$jp" ] && printf '%s\n' "$jp" > "$STATE_DIR/dialogwin.pid"
jq -c '. + {ok:true}' "$WIN/tmp/dialogwin.json"
