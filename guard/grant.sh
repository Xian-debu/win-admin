#!/usr/bin/env bash
# guard/grant.sh - issue / inspect / revoke the session-scoped grant, and pause/resume (D6, D7).
# The agent may only call 'issue' right after the user explicitly agreed; the user's words go into note.
set -uo pipefail
. "$(dirname "$0")/../lib/common.sh"

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
G="$STATE_DIR/grant.json"

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
    printf '{"ok":true,"revoked":true}\n'; exit 0 ;;
  pause)
    : > "$STATE_DIR/pause.flag"; printf '{"ok":true,"paused":true}\n'; exit 0 ;;
  resume)
    rm -f "$STATE_DIR/pause.flag"; printf '{"ok":true,"paused":false}\n'; exit 0 ;;
  *) echo "unknown command: $cmd" >&2; usage >&2; exit 2 ;;
esac
