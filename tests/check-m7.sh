#!/usr/bin/env bash
# tests/check-m7.sh - M8/T2 acceptance: winput hover (glide + dwell + verifiable probe) and
# winput wheel (vertical/horizontal, notch count, under-cursor verification).
# Fixture: tests/helpers/menutwin.ps1 - MENU-ROOT reveals SUB-ONE/SUB-TWO only on mouse enter,
# a 300 px scroll viewport, and an initially off-screen DEEP-TARGET.
set -uo pipefail
cd "$(dirname "$0")/.."
. "$(pwd)/lib/common.sh"

PASS=0; FAIL=0; SKIP=0
pass() { echo "PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
skip() { echo "SKIP  $1"; SKIP=$((SKIP+1)); }

WIN=/mnt/c/Users/Public/win-admin
G="$STATE_DIR/grant.json"
GBK="$STATE_DIR/grant.json.m7-test-bak"
MENU="$WIN/tmp/menutwin-menu.txt"
SCROLLF="$WIN/tmp/menutwin-scroll.txt"
JSONF="$WIN/tmp/menutwin.json"
cleanup() {
  bash tests/helpers/menutwin-stop.sh >/dev/null 2>&1
  if [ -f "$GBK" ]; then mv -f "$GBK" "$G"; else rm -f "$G"; fi
  rm -f "$STATE_DIR/menutwin.pid"
}
trap cleanup EXIT

if [ -f "$G" ]; then cp "$G" "$GBK"; fi
bash guard/grant.sh issue --minutes 30 --scope shot,uia,input,file:read --note "tests/check-m7.sh 本机验收（hover/wheel 夹具窗口）" >/dev/null 2>&1 || true
bash tests/helpers/menutwin-stop.sh >/dev/null 2>&1
sleep 0.5
TW="$(bash tests/helpers/menutwin-start.sh 'wa-m7menu')"
if ! printf '%s' "$TW" | jq -e '.ok' >/dev/null 2>&1; then
  echo "FATAL: cannot launch fixture: $TW"; exit 1
fi
H="$(printf '%s' "$TW" | jq -r '.hwnd_dec')"
MX="$(printf '%s' "$TW" | jq -r '(.menu.root.x + .menu.root.w/2) | floor')"
MY="$(printf '%s' "$TW" | jq -r '(.menu.root.y + .menu.root.h/2) | floor')"
SX="$(printf '%s' "$TW" | jq -r '(.scroll.x + .scroll.w/2) | floor')"
SY="$(printf '%s' "$TW" | jq -r '(.scroll.y + .scroll.h/2) | floor')"

# ---- W0: argument contracts (no injection happens on these paths) ----
bin/winput hover "$MX" "$MY" --dwell 100 >/dev/null 2>&1; w0a=$?
bin/winput wheel "$SX" "$SY" --delta 0 --expect-hwnd "$H" >/dev/null 2>&1; w0b=$?
bin/winput wheel "$SX" "$SY" --expect-hwnd "$H" --times 0 >/dev/null 2>&1; w0c=$?
if [ "$w0a" -eq 2 ] && [ "$w0b" -eq 2 ] && [ "$w0c" -eq 2 ]; then
  pass "W0 hover needs --expect-hwnd; wheel rejects delta 0 / times 0 (all rc=2)"
else
  fail "W0 arg contracts: rc=$w0a/$w0b/$w0c (want 2/2/2)"
fi

# ---- W1: a dry-run hover neither moves the cursor nor opens the menu ----
D="$(bin/winput hover "$MX" "$MY" --expect-hwnd "$H" --dwell 50)"
sleep 0.3
if printf '%s' "$D" | jq -e '.ok == true and .dryRun == true' >/dev/null 2>&1 && [ ! -s "$MENU" ]; then
  pass "W1 dry-run hover: plan printed, menu untouched"
else
  fail "W1 dry-run hover: $(printf '%s' "$D" | head -c 200) | menu=$(wc -c < "$MENU" 2>/dev/null)"
fi

# ---- W2: hover opens the hover-only submenu and reports the element under the cursor ----
V="$(bin/winput hover "$MX" "$MY" --expect-hwnd "$H" --dwell 700 --steps 12 --yes)"
sleep 0.4
vis="$(jq -r '.menu.visible' "$JSONF" 2>/dev/null)"
ename="$(printf '%s' "$V" | jq -r '.under.element.name // ""')"
if printf '%s' "$V" | jq -e '.ok == true and .injected == true' >/dev/null 2>&1 \
   && [ -s "$MENU" ] && [ "$vis" = "true" ] && [ "$ename" = "MENU-ROOT" ]; then
  pass "W2 hover revealed submenu (menu events=$(wc -l < "$MENU")) and reported element '$ename'"
else
  fail "W2 hover: ok=$(printf '%s' "$V" | jq -r .ok) menu=$(wc -c < "$MENU" 2>/dev/null) visible=$vis element=$ename"
fi

# ---- W3: the reported element rect must actually contain the hovered point ----
RCHECK="$(printf '%s' "$V" | jq -r --argjson x "$MX" --argjson y "$MY" '
  (.under.element.rect) as $e | if ($e.x - 2 <= $x and $x <= $e.x + $e.w + 2 and $e.y - 2 <= $y and $y <= $e.y + $e.h + 2) then "in" else "out" end' 2>/dev/null)"
if [ "$RCHECK" = "in" ]; then
  pass "W3 probe rect $(printf '%s' "$V" | jq -c '.under.element.rect') contains the hover point $MX,$MY"
else
  fail "W3 probe rect does not contain the hover point ($RCHECK): $(printf '%s' "$V" | jq -c '.under.element')"
fi

# ---- W4: hover on a point owned by another process is refused (rc=3 ENV_WINDOW_MISMATCH) ----
FX="$(printf '%s' "$TW" | jq -r '.menu.root.x')"; FY="$(printf '%s' "$TW" | jq -r '.menu.root.y')"
OUT="$(bin/winput hover "$((FX + 4000))" "$FY" --expect-hwnd "$H" --dwell 50 --yes 2>&1)"; rc4=$?
# (+4000 is off the 2560-wide screen: ARG_OUT_OF_SCREEN=2 is also a refusal; either is correct)
code4="$(printf '%s' "$OUT" | jq -r '.code // ""' 2>/dev/null || true)"
if [ "$rc4" -eq 2 ] || { [ "$rc4" -eq 3 ] && [ "$code4" = "ENV_WINDOW_MISMATCH" ]; }; then
  pass "W4 hover off-target refused (rc=$rc4 $code4)"
else
  fail "W4 hover off-target: rc=$rc4 $code4"
fi

# ---- W5: wheel scrolls down by the requested notches, then back to the top ----
O0="$(cat "$SCROLLF" 2>/dev/null | awk '{print $1}')"
WD="$(bin/winput wheel "$SX" "$SY" --delta -120 --times 3 --expect-hwnd "$H" --focus --yes)"
sleep 0.5
O1="$(cat "$SCROLLF" 2>/dev/null | awk '{print $1}')"
WU="$(bin/winput wheel "$SX" "$SY" --delta 120 --times 4 --expect-hwnd "$H" --focus --yes)"
sleep 0.5
O2="$(cat "$SCROLLF" 2>/dev/null | awk '{print $1}')"
if printf '%s' "$WD" | jq -e '.ok == true' >/dev/null 2>&1 && [ "${O1:-0}" -gt "${O0:-0}" ] 2>/dev/null \
   && printf '%s' "$WU" | jq -e '.ok == true' >/dev/null 2>&1 && [ "${O2:-1}" -eq 0 ] 2>/dev/null; then
  pass "W5 wheel: offset $O0 -> $O1 -> $O2 (down 3, up 4 notches)"
else
  fail "W5 wheel: offsets $O0/$O1/$O2 ok=$(printf '%s' "$WD" | jq -r .ok)/$(printf '%s' "$WU" | jq -r .ok)"
fi

# ---- W6: wheel reports the element under the cursor (verifiable scroll target) ----
if printf '%s' "$WD" | jq -e '.under.element.name != null and .under.window.title == "wa-m7menu"' >/dev/null 2>&1; then
  pass "W6 wheel under-cursor probe: $(printf '%s' "$WD" | jq -r '.under.element.name')"
else
  fail "W6 wheel probe: $(printf '%s' "$WD" | jq -c '.under')"
fi

# ---- W7: wheel refuses a point that belongs to another window (rc=3) ----
WL="$(bin/wwin list | jq -r '[.windows[] | select(.hwnd != "'"$(printf '0x%x' "$H")"'")] | first | .hwnd // empty')"
if [ -n "$WL" ]; then
  OUT7="$(bin/winput wheel "$SX" "$SY" --delta -120 --expect-hwnd "$((WL))" --yes 2>&1)"; rc7=$?
  code7="$(printf '%s' "$OUT7" | jq -r '.code // ""' 2>/dev/null || true)"
  if [ "$rc7" -eq 3 ] && [ "$code7" = "ENV_WINDOW_MISMATCH" ]; then
    pass "W7 wheel to a foreign hwnd refused (ENV_WINDOW_MISMATCH)"
  else
    fail "W7 wheel foreign target: rc=$rc7 code=$code7"
  fi
else
  skip "W7 no second window to test against"
fi

# ---- W8: no grant -> hover/wheel are refused (rc=4), nothing injected ----
rm -f "$G"
HOUT="$(bin/winput hover "$MX" "$MY" --expect-hwnd "$H" --yes 2>&1)"; rc8a=$?
WOUT="$(bin/winput wheel "$SX" "$SY" --delta -120 --expect-hwnd "$H" --yes 2>&1)"; rc8b=$?
if [ "$rc8a" -eq 4 ] && [ "$rc8b" -eq 4 ]; then
  pass "W8 no grant -> hover rc=4, wheel rc=4"
else
  fail "W8 guard gate: hover=$rc8a wheel=$rc8b (want 4/4)"
fi

echo "-----"
echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[ "$FAIL" -eq 0 ] || exit 1