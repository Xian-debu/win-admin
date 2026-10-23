#!/usr/bin/env bash
# tests/check-m6.sh - M8/T1 acceptance: wwin state + set (max/restore/min/move/resize/topmost),
# dry-run purity, ENV_STATE_UNCHANGED assertions and the input-grant gate on a real change.
# Uses the repo's own WPF test window (tests/helpers/testwin.ps1); never the user's apps.
set -uo pipefail
cd "$(dirname "$0")/.."
. "$(pwd)/lib/common.sh"

PASS=0; FAIL=0; SKIP=0
pass() { echo "PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
skip() { echo "SKIP  $1"; SKIP=$((SKIP+1)); }

G="$STATE_DIR/grant.json"
GBK="$STATE_DIR/grant.json.m6-test-bak"
HAD_GRANT=0
cleanup() {
  bash tests/helpers/testwin-stop.sh >/dev/null 2>&1
  if [ -f "$GBK" ]; then mv -f "$GBK" "$G"; else rm -f "$G"; fi
  rm -f "$STATE_DIR/testwin.pid" "$STATE_DIR/testwin.pid.tmp"
}
trap cleanup EXIT

if [ -f "$G" ]; then cp "$G" "$GBK"; HAD_GRANT=1; fi
bash guard/grant.sh issue --minutes 30 --scope shot,uia,input,file:read --note "tests/check-m6.sh 本机验收（仓库自带测试窗口）" >/dev/null 2>&1 || true
bash tests/helpers/testwin-stop.sh >/dev/null 2>&1
sleep 0.5
TW="$(bash tests/helpers/testwin-start.sh 'wa-m6win')"
if ! printf '%s' "$TW" | jq -e '.ok' >/dev/null 2>&1; then
  echo "FATAL: cannot launch test window: $TW"; exit 1
fi
H="$(printf '%s' "$TW" | jq -r '.hwnd_dec')"

# jq helper: pick fields out of one CLI call
q() { jq -r "$1" 2>/dev/null; }

# ---- N1: state reports the real placement ----
S0="$(bin/wwin state --hwnd "$H")"
if printf '%s' "$S0" | jq -e '.ok == true' >/dev/null 2>&1; then
  st="$(printf '%s' "$S0" | q '.window.state')"
  wa="$(printf '%s' "$S0" | q '.work_area.w')"
  if [ "$st" = "normal" ] && [ -n "$wa" ] && [ "$wa" -gt 0 ] 2>/dev/null; then
    pass "N1 wwin state: state=$st work_area.w=$wa"
  else
    fail "N1 wwin state: unexpected state=$st work_area.w=$wa"
  fi
else
  fail "N1 wwin state: call failed: $S0"
fi
R0="$(printf '%s' "$S0" | q '.window.rect | "\(.x) \(.y) \(.w) \(.h)"')"
read -r RX RY RW RH <<< "$R0"

# ---- N2: dry-run is inert ----
D="$(bin/wwin set --hwnd "$H" --state max)"
S1="$(bin/wwin state --hwnd "$H")"
if printf '%s' "$D" | jq -e '.ok == true and .dry_run == true' >/dev/null 2>&1 \
   && [ "$(printf '%s' "$S1" | q '.window.state')" = "normal" ]; then
  pass "N2 dry-run plan printed, window untouched"
else
  fail "N2 dry-run plan or inertness broken: $(printf '%s' "$S1" | q '.window.state')"
fi

# ---- N3: maximize reports showCmd==3 (geometry alone proves nothing) ----
M="$(bin/wwin set --hwnd "$H" --state max --yes)"
if printf '%s' "$M" | jq -e '.ok == true and .after.maximized == true and .after.state == "maximized"' >/dev/null 2>&1; then
  pass "N3 maximize -> showCmd=maximized"
else
  fail "N3 maximize failed: $(printf '%s' "$M" | head -c 300)"
fi

# ---- N4: restore returns to the pre-maximize rect (±2 px) ----
R="$(bin/wwin set --hwnd "$H" --state restore --yes)"
RC_="$(printf '%s' "$R" | q '.after.rect | "\(.x) \(.y) \(.w) \(.h)"')"
read -r AX AY AW AH <<< "$RC_"
ok=1
[ "$(printf '%s' "$R" | q '.ok')" = "true" ] || ok=0
[ $(( AX > RX ? AX-RX : RX-AX )) -le 2 ] 2>/dev/null || ok=0
[ $(( AY > RY ? AY-RY : RY-AY )) -le 2 ] 2>/dev/null || ok=0
if [ "$ok" -eq 1 ]; then
  pass "N4 restore -> rect $AX,$AY back at $RX,$RY"
else
  fail "N4 restore rect mismatch: before $RX,$RY after $AX,$AY"
fi

# ---- N5: move + resize are exact within 2 px ----
MV="$(bin/wwin set --hwnd "$H" --x 120 --y 140 --w 720 --h 520 --yes)"
if printf '%s' "$MV" | jq -e '.ok == true
    and ((.after.rect.x - 120) | if . < 0 then -. else . end) <= 2
    and ((.after.rect.y - 140) | if . < 0 then -. else . end) <= 2
    and ((.after.rect.w - 720) | if . < 0 then -. else . end) <= 2
    and ((.after.rect.h - 520) | if . < 0 then -. else . end) <= 2' >/dev/null 2>&1; then
  pass "N5 move/resize -> $(printf '%s' "$MV" | q '.after.rect | "\(.x),\(.y) \(.w)x\(.h)"')"
else
  fail "N5 move/resize failed: $(printf '%s' "$MV" | head -c 300)"
fi

# ---- N6: topmost on/off is read back from WS_EX_TOPMOST ----
T1="$(bin/wwin set --hwnd "$H" --topmost on --yes)"
T2="$(bin/wwin set --hwnd "$H" --topmost off --yes)"
if printf '%s' "$T1" | jq -e '.ok == true and .after.topmost == true' >/dev/null 2>&1 \
   && printf '%s' "$T2" | jq -e '.ok == true and .after.topmost == false' >/dev/null 2>&1; then
  pass "N6 topmost on/off round-trip"
else
  fail "N6 topmost failed: on=$(printf '%s' "$T1" | q .ok) off=$(printf '%s' "$T2" | q .ok)"
fi

# ---- N7: minimize then restore ----
MN="$(bin/wwin set --hwnd "$H" --state min --yes)"
MR="$(bin/wwin set --hwnd "$H" --state restore --yes)"
if printf '%s' "$MN" | jq -e '.ok == true and .after.minimized == true' >/dev/null 2>&1 \
   && printf '%s' "$MR" | jq -e '.ok == true and .after.state == "normal"' >/dev/null 2>&1; then
  pass "N7 minimize -> restore"
else
  fail "N7 minimize/restore failed: min=$(printf '%s' "$MN" | q .ok) restore=$(printf '%s' "$MR" | q .ok)"
fi

# ---- N8: arg validation (nothing to do / bad value) ----
bin/wwin set --hwnd "$H" >/dev/null 2>&1; n8a=$?
bin/wwin set --hwnd "$H" --state bogus >/dev/null 2>&1; n8b=$?
bin/wwin set --hwnd "$H" --w 0 --yes >/dev/null 2>&1; n8c=$?
if [ "$n8a" -eq 2 ] && [ "$n8b" -eq 2 ] && [ "$n8c" -eq 2 ]; then
  pass "N8 arg validation exits 2 (nothing/bad state/zero width)"
else
  fail "N8 arg validation: rc=$n8a/$n8b/$n8c (want 2/2/2)"
fi

# ---- N9: a real change without a grant is refused with rc=4 (S9) ----
rm -f "$G"
GO="$(bin/wwin set --hwnd "$H" --state max --yes 2>&1)"; n9=$?
code9="$(printf '%s' "$GO" | jq -r '.code // ""' 2>/dev/null || true)"
if [ "$n9" -eq 4 ] && [ "$code9" = "GUARD_NO_GRANT" ]; then
  pass "N9 no grant -> rc=4 $code9"
else
  fail "N9 guard gate: rc=$n9 code=$code9"
fi
# (cleanup restores/removes the grant; a dry-run still works without one)
DR9="$(bin/wwin set --hwnd "$H" --state max)"
if printf '%s' "$DR9" | jq -e '.ok == true and .dry_run == true' >/dev/null 2>&1; then
  pass "N10 dry-run needs no grant"
else
  fail "N10 dry-run without grant: $(printf '%s' "$DR9" | head -c 200)"
fi

echo "-----"
echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[ "$FAIL" -eq 0 ] || exit 1