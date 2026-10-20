#!/usr/bin/env bash
# guard/grant.sh - issue / inspect / revoke the session-scoped grant, and pause/resume (D6, D7).
# The agent may only call 'issue' right after the user explicitly agreed; the user's words go into note.
set -uo pipefail
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/audit.sh"

usage() {
  cat <<'EOF'
usage:
  grant.sh issue --minutes N --scope input[,read] --note "<user words>"   (agent, after consent)
  grant.sh status        -> {present,valid,paused,expires,scope,note}
  grant.sh revoke        -> marks revoked (input then fails with GUARD_REVOKED)
  grant.sh pause         -> touch pause.flag (soft stop, honoured by every input primitive)
  grant.sh resume        -> remove pause.flag
exit 0 ok | 2 arg | 4 guard
EOF
}

cmd="${1:-status}"; shift || true
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR" 2>/dev/null || true
G="$STATE_DIR/grant.json"
KEY="$STATE_DIR/.grantkey"

# S6: the grant is signed so accidental/hand edits are detected (same-user isolation is impossible; documented).
ensure_key() {
  [ -s "$KEY" ] || { umask 077; openssl rand -hex 32 > "$KEY" 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$KEY"; }
  chmod 600 "$KEY" 2>/dev/null || true
}

sign_grant() {
  ensure_key
  local k p
  k="$(cat "$KEY")"
  p="$(jq -cS '{issued,expires,scope,note,revoked}' "$G")"
  printf '%s' "$k$p" | sha256sum | cut -d' ' -f1
}

# audit only the mutating subcommands
case "$cmd" in issue|revoke|pause|resume) wa_audit_init grant "$cmd" "$@" ;; esac

case "$cmd" in
  -h|--help) usage; exit 0 ;;
  issue)
    minutes=""; scope="input"; note=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --minutes) minutes="$2"; shift 2 ;;
        --scope) scope="$2"; shift 2 ;;
        --note) note="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
      esac
    done
    [ -n "$minutes" ] || { echo "issue needs --minutes" >&2; exit 2; }
    [ -n "$note" ] || { echo "issue needs --note (user words; 调研 != 授权)" >&2; exit 2; }
    now="$(date +%s)"; exp=$(( now + minutes * 60 ))
    issued="$(date -d "@$now" -Iseconds)"
    expires="$(date -d "@$exp" -Iseconds)"
    scope_json="$(printf '%s' "$scope" | tr ',' '\n' | jq -R . | jq -cs .)"
    jq -n --arg i "$issued" --arg e "$expires" --arg n "$note" --argjson s "$scope_json" \
      '{issued:$i,expires:$e,scope:$s,note:$n,revoked:false,confirm_by:"lead-agent"}' > "$G"
    sig="$(sign_grant)"
    jq --arg s "$sig" '. + {sig:$s}' "$G" > "$G.tmp" && mv "$G.tmp" "$G"
    chmod 600 "$G" 2>/dev/null || true
    WA_AUDIT_RESULT=issued
    printf '{"ok":true,"grant":%s}\n' "$(jq -c . "$G")"
    exit 0 ;;
  status)
    paused=false; [ -f "$STATE_DIR/pause.flag" ] && paused=true
    if [ -f "$G" ]; then
      valid=false
      exp_s="$(date -d "$(jq -r '.expires // ""' "$G")" +%s 2>/dev/null || echo 0)"
      [ "$exp_s" -gt "$(date +%s)" ] && [ "$(jq -r '.revoked // false' "$G")" != "true" ] && valid=true
      jq -c --argjson p "$paused" --argjson v "$valid" '. + {present:true,valid:$v,paused:$p}' "$G"
    else
      printf '{"present":false,"paused":%s}\n' "$paused"
    fi
    exit 0 ;;
  revoke)
    [ -f "$G" ] || { echo "no grant" >&2; exit 2; }
    jq '.revoked = true' "$G" > "$G.tmp" && mv "$G.tmp" "$G"
    sig="$(sign_grant)"
    jq --arg s "$sig" '.sig = $s' "$G" > "$G.tmp" && mv "$G.tmp" "$G"
    WA_AUDIT_RESULT=revoked
    printf '{"ok":true,"revoked":true}\n'; exit 0 ;;
  pause)
    : > "$STATE_DIR/pause.flag"; WA_AUDIT_RESULT=paused; printf '{"ok":true,"paused":true}\n'; exit 0 ;;
  resume)
    rm -f "$STATE_DIR/pause.flag"; WA_AUDIT_RESULT=resumed; printf '{"ok":true,"paused":false}\n'; exit 0 ;;
  *) echo "unknown command: $cmd" >&2; usage >&2; exit 2 ;;
esac
