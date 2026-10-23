#!/usr/bin/env bash
# tests/helpers/uiawnd-start.sh - launch the UIA control fixture (find/act target) and print its info.
set -uo pipefail
. "$(dirname "$0")/../../lib/common.sh"
TITLE="${1:-wa-uia}"
mkdir -p "$APP_ROOT/tmp"
WIN="${WINADMIN_APP_ROOT:-/mnt/c/Users/Public/win-admin}"
cp "$(dirname "$0")/uiawnd.ps1" "$WIN/tmp/wa-uiawnd.ps1"
rm -f "$WIN/tmp/uiawnd.json" "$WIN/tmp/uiawnd-events.txt"
winps -t 30 "Start-Process -FilePath powershell.exe -ArgumentList '-NoProfile','-STA','-WindowStyle','Normal','-ExecutionPolicy','Bypass','-File','$(wa_winpath "$WIN/tmp/wa-uiawnd.ps1")','-Title','$TITLE' -PassThru | Select-Object -ExpandProperty Id" | tail -1 > "$STATE_DIR/uiawnd.pid" 2>/dev/null
for i in $(seq 1 80); do
  [ -s "$WIN/tmp/uiawnd.json" ] && jq -e . "$WIN/tmp/uiawnd.json" >/dev/null 2>&1 && break
  sleep 0.25
done
[ -s "$WIN/tmp/uiawnd.json" ] || { echo '{"ok":false,"code":"EXEC_UIAWND_TIMEOUT"}'; exit 5; }
jq -c '. + {ok:true}' "$WIN/tmp/uiawnd.json"
