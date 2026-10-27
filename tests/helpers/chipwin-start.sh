#!/usr/bin/env bash
# tests/helpers/chipwin-start.sh - launch the v1.4 serial-entry fixture and print its info.
#   chipwin-start.sh [TITLE] [none|first|all] [READY_AFTER_MS]
set -uo pipefail
. "$(dirname "$0")/../../lib/common.sh"
# K58: stop fixture windows leaked by an interrupted or overlapping earlier run.
bash "$(dirname "$0")/kill-fixtures.sh" >/dev/null 2>&1 || true
TITLE="${1:-wa-chips}"
MODE="${2:-none}"
READY="${3:-1200}"
mkdir -p "$APP_ROOT/tmp"
WIN="${WINADMIN_APP_ROOT:-/mnt/c/Users/Public/win-admin}"
cp "$(dirname "$0")/chipwin.ps1" "$WIN/tmp/wa-chipwin.ps1"
rm -f "$WIN/tmp/chipwin.json" "$WIN/tmp/chipwin.err" "$WIN/tmp/chipwin.out" "$WIN/tmp/chipwin-error.txt" "$WIN/tmp/chipwin-events.txt"
PSARGS="'-NoLogo','-NoProfile','-STA','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File','$(wa_winpath "$WIN/tmp/wa-chipwin.ps1")','-Title','$TITLE','-ReadyAfterMs','$READY'"
case "$MODE" in
  first) PSARGS="$PSARGS,'-SwallowFirst'" ;;
  all)   PSARGS="$PSARGS,'-SwallowAll'" ;;
  none)  : ;;
  *) echo "bad mode: $MODE (none|first|all)" >&2; exit 2 ;;
esac
# K73: fire and forget. winps cannot see EOF while the started process holds its
# stdout pipe, so waiting for it costs the full winps timeout (observed 30s per
# fixture start). The pid that owns the window is read from the fixture JSON below.
( winps -t 25 "Start-Process -FilePath powershell.exe -ArgumentList $PSARGS -RedirectStandardError '$(wa_winpath "$WIN/tmp/chipwin.err")' -RedirectStandardOutput '$(wa_winpath "$WIN/tmp/chipwin.out")' -PassThru | Select-Object -ExpandProperty Id" >/dev/null 2>&1 & )
for i in $(seq 1 80); do
  [ -s "$WIN/tmp/chipwin.json" ] && jq -e . "$WIN/tmp/chipwin.json" >/dev/null 2>&1 && break
  sleep 0.25
done
[ -s "$WIN/tmp/chipwin.json" ] || { echo '{"ok":false,"code":"EXEC_CHIPWIN_TIMEOUT"}'; exit 5; }
jp="$(jq -r '.pid // empty' "$WIN/tmp/chipwin.json" 2>/dev/null)"
[ -n "$jp" ] && printf '%s\n' "$jp" > "$STATE_DIR/chipwin.pid"
jq -c '. + {ok:true}' "$WIN/tmp/chipwin.json"