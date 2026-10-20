#!/usr/bin/env bash
# lib/audit.sh - append-only action ledger (S5, D22). Source after lib/common.sh.
# One JSON line per audited invocation; a failed write on a successful action fails closed (exit 5).

WA_AUDIT_DIR="${WA_AUDIT_DIR:-$STATE_DIR/audit}"

# wa_audit_begin TOOL [args...] -> records start time and the raw argv
wa_audit_begin() {
  WA_AUDIT_TOOL="$1"; shift
  WA_AUDIT_T0="$(date +%s%3N)"
  if [ "$#" -gt 0 ]; then
    WA_AUDIT_ARGS="$(printf '%s\n' "$@" | jq -R . | jq -cs .)"
  else
    WA_AUDIT_ARGS="[]"
  fi
  WA_AUDIT_RESULT="unknown"
}

# wa_audit_set RESULT -> classify the outcome (ok / dryrun / GUARD_* / ENV_* / ARG_*)
wa_audit_set() { WA_AUDIT_RESULT="$1"; }

# wa_audit_flush RC [RESULT] -> append one line, then exit RC (fail closed on write error)
wa_audit_flush() {
  local rc="$1" res="${2:-${WA_AUDIT_RESULT:-unknown}}"
  local now dur f line gexp gnote
  trap - EXIT
  now="$(date +%s%3N)"
  dur=$(( now - ${WA_AUDIT_T0:-$now} ))
  f="$WA_AUDIT_DIR/$(date -d "@$(( now / 1000 ))" +%F).jsonl"
  mkdir -p "$WA_AUDIT_DIR" 2>/dev/null
  gexp=""; gnote=""
  if [ -f "$STATE_DIR/grant.json" ]; then
    gexp="$(jq -r '.expires // ""' "$STATE_DIR/grant.json" 2>/dev/null || true)"
    gnote="$(jq -r '.note // ""' "$STATE_DIR/grant.json" 2>/dev/null || true)"
  fi
  line="$(jq -nc --arg ts "$(date -d "@$(( now / 1000 ))" -Iseconds)" --argjson tsm "$now" \
    --arg tool "${WA_AUDIT_TOOL:-unknown}" --argjson args "${WA_AUDIT_ARGS:-[]}" \
    --arg result "$res" --argjson exit "$rc" --argjson dur "$dur" \
    --arg gexp "$gexp" --arg gnote "$gnote" --arg pid "$$" --arg ver "$VERSION" \
    '{ts:$ts,ts_epoch_ms:$tsm,tool:$tool,args:$args,result:$result,exit:$exit,duration_ms:$dur,grant:{expires:$gexp,note:$gnote},pid:$pid,version:$ver}')"
  if ! printf '%s\n' "$line" >> "$f" 2>/dev/null; then
    echo '{"ok":false,"code":"EXEC_AUDIT_FAILED","msg":"cannot write audit log"}' >&2
    if [ "$rc" -eq 0 ]; then rc=5; fi
  fi
  exit "$rc"
}

# wa_audit_init TOOL [args...] -> begin + install the EXIT trap
wa_audit_init() {
  wa_audit_begin "$@"
  trap 'rc=$?; wa_audit_flush "$rc"' EXIT
}
