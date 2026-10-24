#!/usr/bin/env bash
# tests/helpers/dialogwin-start.sh - launch the window-family fixture (main + owned child + other).
set -uo pipefail
. "$(dirname "$0")/../../lib/common.sh"
mkdir -p "$APP_ROOT/tmp"
WIN="${WINADMIN_APP_ROOT:-/mnt/c/Users/Public/win-admin}"
cp "$(dirname "$0")/dialogwin.ps1" "$WIN/tmp/wa-dialogwin.ps1"
rm -f "$WIN/tmp/dialogwin.json" "$WIN/tmp/dialogwin-events.txt"
CMD="Start-Process -FilePath powershell.exe -ArgumentList '-NoProfile','-STA','-WindowStyle','Normal','-ExecutionPolicy','Bypass','-File','$(wa_winpath "$WIN/tmp/wa-dialogwin.ps1")' -PassThru | Select-Object -ExpandProperty Id"
winps -t 30 "$CMD" | tail -1 > "$STATE_DIR/dialogwin.pid" 2>/dev/null
for i in $(seq 1 80); do
  [ -s "$WIN/tmp/dialogwin.json" ] && jq -e . "$WIN/tmp/dialogwin.json" >/dev/null 2>&1 && break
  sleep 0.25
done
[ -s "$WIN/tmp/dialogwin.json" ] || { echo '{"ok":false,"code":"EXEC_DIALOGWIN_TIMEOUT"}'; exit 5; }
jq -c '. + {ok:true}' "$WIN/tmp/dialogwin.json"
