#!/usr/bin/env bash
# tests/check-m13.sh - M13 acceptance: focus/state safety (T12) + window family (T13), v1.2
# Covers: N1 focus keeps a maximized window maximized; N2 focus does not move/resize it;
#         N3 focus restores a minimized window to its pre-minimized state; N4/N5 ops keep state;
#         N6 focusing another window leaves that window normal and unchanged;
#         N7 point in an owned child dialog is refused by default; N8 --allow-related reports
#         matched:related; N9 the related click really lands (fixture event written);
#         N10 an unrelated window is still refused; N11 related foreground accepted;
#         N12 ops/click-element accepts --allow-related.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 5
. "$(pwd)/lib/common.sh"
PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL %s  [%s]\n' "$1" "$2"; }
skip() { SKIP=$((SKIP+1)); printf 'SKIP %s  [%s]\n' "$1" "$2"; }
TMP="/mnt/c/Users/Public/win-admin/tmp"
mkdir -p "$TMP"
G="$STATE_DIR/grant.json"; GBK="$G.m13-bak"
cleanup() {
  bash tests/helpers/uiawnd-stop.sh >/dev/null 2>&1
  bash tests/helpers/dialogwin-stop.sh >/dev/null 2>&1
  if [ -f "$GBK" ]; then mv -f "$GBK" "$G"; fi
}
trap cleanup EXIT
bash guard/grant.sh issue --minutes 30 --scope shot,uia,input,file:read --note 'tests/check-m13.sh 本机验收（焦点状态 + 窗口族）' >/dev/null 2>&1 || true

# state_sig H -> compact JSON of the fields T12 promises not to touch
state_sig() { bin/wwin state --hwnd "$1" | jq -c '{state:(.window.state//null),rn:(.window.rectNormal//null),top:(.window.topmost//null)}'; }

bash tests/helpers/uiawnd-start.sh >/dev/null 2>&1 || { echo 'fixture uiawnd failed'; exit 5; }
W="$(jq -r .hwnd_dec /mnt/c/Users/Public/win-admin/tmp/uiawnd.json)"
[ -n "$W" ] && [ "$W" != null ] || { echo 'no uiawnd hwnd'; exit 5; }
bash tests/helpers/dialogwin-start.sh >/dev/null 2>&1 || { echo 'fixture dialogwin failed'; exit 5; }
DW="/mnt/c/Users/Public/win-admin/tmp/dialogwin.json"
MAIN="$(jq -r .hwnd_dec "$DW")"; CHILD="$(jq -r .child_hwnd_dec "$DW")"; OTHER="$(jq -r .other_hwnd_dec "$DW")"
EV="$TMP/dialogwin-events.txt"

# ---- T12: focus must not change window state -------------------------------------
bin/wwin set --hwnd "$W" --state max --yes >/dev/null 2>&1
S0="$(state_sig "$W")"
FJ="$(bin/wwin focus --hwnd "$W" 2>/dev/null)"
S1="$(state_sig "$W")"
if [ "$(printf %s "$S1" | jq -r .state)" = maximized ] && [ "$(printf %s "$FJ" | jq -r .ok)" = true ]; then
  ok 'N1 focus keeps a maximized window maximized'
else
  bad 'N1 focus keeps maximized' "S1=$S1 focus=$(printf %s "$FJ" | jq -c '{ok,code}')"
fi
if [ "$(printf %s "$S0" | jq -c .rn)" = "$(printf %s "$S1" | jq -c .rn)" ]; then
  ok 'N2 focus does not move or resize the normal rect'
else
  bad 'N2 focus geometry' "before=$(printf %s "$S0" | jq -c .rn) after=$(printf %s "$S1" | jq -c .rn)"
fi

bin/wwin set --hwnd "$W" --state min --yes >/dev/null 2>&1
FJ2="$(bin/wwin focus --hwnd "$W" 2>/dev/null)"
S2="$(state_sig "$W")"
if [ "$(printf %s "$FJ2" | jq -r .ok)" = true ] && [ "$(printf %s "$S2" | jq -r .state)" = maximized ]; then
  ok 'N3 focus restores a minimized window to its pre-minimized state (maximized)'
else
  bad 'N3 restore to pre-minimized state' "S2=$S2 focus=$(printf %s "$FJ2" | jq -c '{ok,code}')"
fi

bin/wwin set --hwnd "$W" --state max --yes >/dev/null 2>&1
CJ="$(ops/click-element --hwnd "$W" --name '^BTN-COUNT$' --timeout 3000 --yes 2>/dev/null)"
S3="$(state_sig "$W")"
if [ "$(printf %s "$CJ" | jq -r .ok)" = true ] && [ "$(printf %s "$CJ" | jq -r .statePreserved)" = true ] && [ "$(printf %s "$S3" | jq -r .state)" = maximized ]; then
  ok 'N4 ops/click-element keeps the window state (statePreserved)'
else
  bad 'N4 click-element state' "click=$(printf %s "$CJ" | jq -c '{ok,code,statePreserved}')"
fi

RT="$(bin/wwin info --hwnd "$W" | jq -c .window.rect)"
RX="$(printf %s "$RT" | jq -r .x)"; RY="$(printf %s "$RT" | jq -r .y)"
HJ="$(ops/hover-menu --hwnd "$W" --at "$((RX+240)),$((RY+240))" --pick '^CHK-A$' --dwell 400 --timeout 3000 --yes 2>/dev/null)"
S4="$(state_sig "$W")"
if [ "$(printf %s "$HJ" | jq -r .ok)" = true ] && [ "$(printf %s "$S4" | jq -r .state)" = maximized ]; then
  ok 'N5 ops/hover-menu keeps the window state'
else
  bad 'N5 hover-menu state' "hover=$(printf %s "$HJ" | jq -c '{ok,code,statePreserved}')"
fi

O0="$(state_sig "$OTHER")"
bin/wwin focus --hwnd "$OTHER" >/dev/null 2>&1
O1="$(state_sig "$OTHER")"
if [ "$(printf %s "$O1" | jq -r .state)" = normal ] && [ "$(printf %s "$O0" | jq -c .rn)" = "$(printf %s "$O1" | jq -c .rn)" ]; then
  ok 'N6 focusing a normal window leaves it normal and unmoved'
else
  bad 'N6 normal window' "O0=$O0 O1=$O1"
fi

# ---- T13: window family -----------------------------------------------------------
CR="$(bash bin/wuia --hwnd "$CHILD" --find-name '^CHILD-BTN$' --depth 12 2>/dev/null | jq -c '.nodes[0].rect')"
PX="$(( $(printf %s "$CR" | jq -r .x) + $(printf %s "$CR" | jq -r '.w/2|floor') ))"
PY="$(( $(printf %s "$CR" | jq -r .y) + $(printf %s "$CR" | jq -r '.h/2|floor') ))"
bin/wwin focus --hwnd "$MAIN" >/dev/null 2>&1

NJ="$(bin/winput click "$PX" "$PY" --expect-hwnd "$MAIN" --dry-run 2>/dev/null)"; NRC=$?
if [ "$NRC" -eq 3 ] && [ "$(printf %s "$NJ" | jq -r .code)" = ENV_WINDOW_MISMATCH ]; then
  ok 'N7 point in an owned child dialog is refused by default (rc=3 ENV_WINDOW_MISMATCH)'
else
  bad 'N7 default family refusal' "rc=$NRC $(printf %s "$NJ" | jq -c '{ok,code}')"
fi
if printf %s "$NJ" | jq -r .msg | grep -q 'allow-related'; then
  ok 'N7b mismatch message names the escape hatch (--allow-related)'
else
  bad 'N7b mismatch hint' "$(printf %s "$NJ" | jq -r .msg)"
fi

RJ="$(bin/winput click "$PX" "$PY" --expect-hwnd "$MAIN" --allow-related --dry-run 2>/dev/null)"
if [ "$(printf %s "$RJ" | jq -r .ok)" = true ] && [ "$(printf %s "$RJ" | jq -r .matched)" = related ]; then
  ok 'N8 --allow-related accepts the owner/child dialog and reports matched:related'
else
  bad 'N8 related dry-run' "$(printf %s "$RJ" | jq -c '{ok,code,matched}')"
fi

N0=0; [ -f "$EV" ] && N0="$(grep -c 'child clicked' "$EV" 2>/dev/null || true)"
AJ="$(bin/winput click "$PX" "$PY" --expect-hwnd "$MAIN" --allow-related --yes 2>/dev/null)"
N1C=0; [ -f "$EV" ] && N1C="$(grep -c 'child clicked' "$EV" 2>/dev/null || true)"
if [ "$(printf %s "$AJ" | jq -r .ok)" = true ] && [ "$(printf %s "$AJ" | jq -r .matched)" = related ] && [ "$N1C" -gt "$N0" ]; then
  ok 'N9 the related click really lands (fixture logged the click)'
else
  bad 'N9 related real click' "ok=$(printf %s "$AJ" | jq -c '{ok,code,matched}')" events=$N0->$N1C
fi

UJ="$(bin/winput click "$PX" "$PY" --expect-hwnd "$OTHER" --allow-related --dry-run 2>/dev/null)"; URC=$?
if [ "$URC" -eq 3 ] && [ "$(printf %s "$UJ" | jq -r .code)" = ENV_WINDOW_MISMATCH ]; then
  ok 'N10 an unrelated window is still refused with --allow-related (rc=3)'
else
  bad 'N10 unrelated refusal' "rc=$URC $(printf %s "$UJ" | jq -c '{ok,code}')"
fi

bin/wwin focus --hwnd "$CHILD" >/dev/null 2>&1
FJ3="$(bin/winput click "$PX" "$PY" --expect-hwnd "$MAIN" --allow-related --yes 2>/dev/null)"
if [ "$(printf %s "$FJ3" | jq -r .ok)" = true ] && [ "$(printf %s "$FJ3" | jq -r .matched)" = related ]; then
  ok 'N11 related foreground (child active, expected parent) is accepted'
else
  bad 'N11 related foreground' "$(printf %s "$FJ3" | jq -c '{ok,code,matched}')"
fi

bin/wwin focus --hwnd "$MAIN" >/dev/null 2>&1
DJ="$(ops/click-element --hwnd "$MAIN" --name '^MAIN-BTN$' --allow-related 2>/dev/null)"
if [ "$(printf %s "$DJ" | jq -r .ok)" = true ] && [ "$(printf %s "$DJ" | jq -r .dry_run)" = true ]; then
  ok 'N12 ops/click-element accepts --allow-related (dry-run)'
else
  bad 'N12 ops flag' "$(printf %s "$DJ" | jq -c '{ok,code,dry_run}')"
fi

printf '\n%s passed, %s failed, %s skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" = 0 ] || exit 1
exit 0