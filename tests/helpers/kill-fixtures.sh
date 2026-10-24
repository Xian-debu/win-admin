#!/usr/bin/env bash
# tests/helpers/kill-fixtures.sh - stop leaked fixture windows (K58, K61).
#
# Fixture stop scripts only know the pid from their own pid file; when a suite is
# interrupted, or two runs overlap, older instances keep running and a later suite
# then clicks at coordinates owned by a stale window (the m9 L5 flake).
# This sweeps top-level windows titled wa-* EXCEPT the fixtures of the current run,
# which are identified by a recent $STATE_DIR/<name>.pid file (mtime < 30 min):
# starting the second fixture of a suite therefore no longer kills the first one
# (K61: m11/m13 failed exactly that way). Note the pid files hold *Windows* pids,
# so liveness is judged by the pid file age, not by `kill -0` (a WSL pid check).
set -uo pipefail
cd "$(dirname "$0")/../.."
. "$(pwd)/lib/common.sh"

keep=""
for f in "$STATE_DIR"/*.pid; do
  [ -f "$f" ] || continue
  [ -n "$(find "$f" -mmin -30 2>/dev/null)" ] || continue
  p="$(tr -dc "0-9" < "$f" 2>/dev/null || true)"
  [ -n "$p" ] && keep="$keep $p"
done
keep="${keep# }"

list="$(bash bin/wwin list 2>/dev/null || true)"
pids="$(printf %s "$list" | jq -r --arg keep "$keep" '
  ($keep | split(" ") | map(select(length > 0))) as $keepset
  | .windows[]?
  | select(.title | test("^wa-"))
  | select((.pid | tostring) as $p | ($keepset | index($p)) == null)
  | .pid' 2>/dev/null | sort -u | tr "\n" "," | sed "s/,$//")"
if [ -z "$pids" ]; then
  echo "{\"ok\":true,\"killed\":0,\"kept\":\"$keep\",\"note\":\"no leaked fixture windows\"}"
  exit 0
fi
n="$(printf %s "$pids" | awk -F, "{print NF}")"
winps -r "\$ids=@($pids); Get-Process -Id \$ids -ErrorAction SilentlyContinue | Where-Object { \$_.ProcessName -match \"powershell|pwsh\" } | Stop-Process -Force" >/dev/null 2>&1 || true
sleep 0.6
left="$(bash bin/wwin list 2>/dev/null | jq -r '[.windows[]? | select(.title | test("^wa-"))] | length' 2>/dev/null || echo "?")"
echo "{\"ok\":true,\"killed\":$n,\"kept\":\"$keep\",\"left\":$left}"
