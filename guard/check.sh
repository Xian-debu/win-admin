#!/usr/bin/env bash
# guard/check.sh - single choke point for every primitive (D6).
# read  : always allowed (no injection).
# input : requires pause.flag absent AND a valid, unexpired, unrevoked grant.json whose scope covers input.
# write : same as input (file mutations are input-grade).
set -uo pipefail
. "$(dirname "$0")/../lib/common.sh"

mode="${1:-read}"

if [ "$mode" = "read" ]; then
  exit 0
fi

case "$mode" in
  input|write) ;;
  *) wa_err_json ARG_BAD_MODE "unknown mode: $mode"; exit 2 ;;
esac

if [ -f "$STATE_DIR/pause.flag" ]; then
  wa_err_json GUARD_PAUSED "pause.flag present; input operations are paused"
  exit 4
fi

G="$STATE_DIR/grant.json"
if [ ! -f "$G" ]; then
  wa_err_json GUARD_NO_GRANT "no grant.json; ask the user, then: guard/grant.sh issue --minutes 30 --scope input --note '<user words>'"
  exit 4
fi

revoked="$(jq -r '.revoked // false' "$G" 2>/dev/null || echo true)"
[ "$revoked" = "true" ] && { wa_err_json GUARD_REVOKED "grant revoked"; exit 4; }

expires="$(jq -r '.expires // ""' "$G" 2>/dev/null || true)"
[ -n "$expires" ] || { wa_err_json GUARD_BAD_GRANT "grant.json has no expires"; exit 4; }
now="$(date +%s)"
exp_s="$(date -d "$expires" +%s 2>/dev/null || echo 0)"
if [ "$exp_s" -le "$now" ]; then
  wa_err_json GUARD_EXPIRED "grant expired at $expires"
  exit 4
fi

if ! jq -e '.scope | index("input")' "$G" >/dev/null 2>&1; then
  wa_err_json GUARD_SCOPE "grant scope does not include input"
  exit 4
fi

printf '{"ok":true,"mode":"%s","grant":{"expires":"%s","scope":%s,"note":%s}}\n' \
  "$mode" "$expires" "$(jq -c '.scope' "$G")" "$(jq -c '.note // ""' "$G")"
exit 0
