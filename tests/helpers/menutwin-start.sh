#!/usr/bin/env bash
# tests/helpers/menutwin-start.sh - launch the hover-menu fixture (MENU-ROOT -> SUB-ONE/SUB-TWO,
# a scrollable list and an initially off-screen DEEP-TARGET) and print its info JSON.
set -uo pipefail
. "$(dirname "$0")/../../lib/common.sh"
TITLE="${1:-wa-menutwin}"
mkdir -p "$APP_ROOT/tmp"
WIN="${WINADMIN_APP_ROOT:-/mnt/c/Users/Public/win-admin}"
cp "$(dirname "$0")/menutwin.ps1" "$WIN/tmp/wa-menutwin.ps1"
rm -f "$WIN/tmp/menutwin.json" "$WIN/tmp/menutwin-menu.txt" "$WIN/tmp/menutwin-scroll.txt"
winps -t 30 "Start-Process -FilePath powershell.exe -ArgumentList '-NoProfile','-STA','-WindowStyle','Normal','-ExecutionPolicy','Bypass','-File','$(wa_winpath "$WIN/tmp/wa-menutwin.ps1")','-Title','$TITLE' -PassThru | Select-Object -ExpandProperty Id" | tail -1 > "$STATE_DIR/menutwin.pid" 2>/dev/null
for i in $(seq 1 80); do
  [ -s "$WIN/tmp/menutwin.json" ] && jq -e . "$WIN/tmp/menutwin.json" >/dev/null 2>&1 && break
  sleep 0.25
done
[ -s "$WIN/tmp/menutwin.json" ] || { echo '{"ok":false,"code":"EXEC_MENUTWIN_TIMEOUT"}'; exit 5; }
jq -c '. + {ok:true}' "$WIN/tmp/menutwin.json"
