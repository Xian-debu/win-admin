#!/usr/bin/env bash
# scripts/ps-doctor.sh - PowerShell invocation hygiene for the win-admin WSL->Windows bridge.
#
# Why (v1.4, K72): a fixture started with Start-Process -WindowStyle Normal left a visible
# PowerShell console on top of the test window with a PointToScreen exception in it, and a -NoExit
# probe left another. Those are launch-discipline bugs, not fixture bugs. Every powershell.exe we
# spawn must be: -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden, stderr/stdout redirected to
# a log file, and never -NoExit.
#
#   bash scripts/ps-doctor.sh          report (JSON)
#   bash scripts/ps-doctor.sh --reap   kill leaked win-admin powershell.exe (only processes whose
#                                      command line names this project, never a user's own shell)
set -uo pipefail
cd "$(dirname "$0")/.."
. "$(pwd)/lib/common.sh"

REAP=0
for a in "$@"; do
  case "$a" in
    --reap) REAP=1 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) printf '{"ok":false,"code":"ARG_UNKNOWN","arg":"%s"}\n' "$a"; exit 2 ;;
  esac
done

PROCS="$(winps -r - <<'PS'
$rows = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object {
  $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine -match 'win-admin'
} | ForEach-Object {
  [pscustomobject]@{
    pid     = [int]$_.ProcessId
    noExit  = [bool]($_.CommandLine -match '-NoExit')
    fixture = [bool]($_.CommandLine -match 'win-admin\\tmp\\wa-[a-z]+\.ps1')
    cmd     = [string]$_.CommandLine
  }
}
@($rows) | ConvertTo-Json -Compress -Depth 3
PS
)" || PROCS='[]'
[ -n "$PROCS" ] || PROCS='[]'
printf '%s' "$PROCS" | jq -e . >/dev/null 2>&1 || PROCS='[]'

# A live fixture owns its pid file; same 30-minute rule kill-fixtures.sh uses.
keep=""
for f in "$STATE_DIR"/*.pid; do
  [ -f "$f" ] || continue
  [ -n "$(find "$f" -mmin -30 2>/dev/null)" ] || continue
  p="$(tr -dc '0-9' < "$f" 2>/dev/null || true)"
  [ -n "$p" ] && keep="$keep $p"
done
keep="$(printf '%s' "$keep" | sed 's/^ *//')"

LEAK="$(printf '%s' "$PROCS" | jq -c --arg keep "$keep" '
  ($keep | split(" ") | map(select(length > 0)) | map(tonumber)) as $kept
  | [ .[]?
      | select((.noExit == true) or ((.fixture == true) and (($kept | index(.pid)) == null)))
      | { pid, noExit, fixture } ]' 2>/dev/null)"
[ -n "$LEAK" ] || LEAK='[]'
TOTAL="$(printf '%s' "$PROCS" | jq 'length' 2>/dev/null || echo 0)"
LEAKN="$(printf '%s' "$LEAK" | jq 'length' 2>/dev/null || echo 0)"
[ -n "$TOTAL" ] || TOTAL=0
[ -n "$LEAKN" ] || LEAKN=0

KILLED=0
if [ "$REAP" = 1 ] && [ "$LEAKN" != "0" ]; then
  IDS="$(printf '%s' "$LEAK" | jq -r '[.[].pid] | join(",")')"
  winps -r "Get-Process -Id @($IDS) -ErrorAction SilentlyContinue | Stop-Process -Force" >/dev/null 2>&1 || true
  KILLED="$LEAKN"
fi
jq -nc --argjson total "$TOTAL" --argjson leaked "$LEAKN" --argjson killed "$KILLED" --arg keep "$keep" --argjson leaks "$LEAK" \
  '{ok:true, powershell:$total, leaked:$leaked, killed:$killed, kept:$keep, leaks:$leaks}'
