#!/usr/bin/env bash
# tests/check-m8.sh - M9/T3 acceptance: key --hold, keydown/keyup pairs, releaseall safety net.
# Verifies by reading the resulting text back out of the fixture's edit box (clipboard round trip),
# and by inspecting the held-keys state file that keydown/keyup maintain.
set -uo pipefail
cd "$(dirname "$0")/.."
. "$(pwd)/lib/common.sh"

PASS=0; FAIL=0; SKIP=0
pass() { echo "PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
skip() { echo "SKIP  $1"; SKIP=$((SKIP+1)); }

WIN=/mnt/c/Users/Public/win-admin
G="$STATE_DIR/grant.json"
GBK="$STATE_DIR/grant.json.m8-test-bak"
JSONF="$WIN/tmp/testwin.json"
HELD="$WIN/tmp/held.json"
cleanup() {
  bin/winput releaseall --yes >/dev/null 2>&1
  bash tests/helpers/testwin-stop.sh >/dev/null 2>&1
  if [ -f "$GBK" ]; then mv -f "$GBK" "$G"; else rm -f "$G"; fi
  rm -f "$HELD"
}
trap cleanup EXIT

[ -f "$G" ] && cp "$G" "$GBK"
bash guard/grant.sh issue --minutes 30 --scope shot,uia,input,file:read --note "tests/check-m8.sh 本机验收（键盘长按/成对按下）" >/dev/null 2>&1 || true
bash tests/helpers/testwin-stop.sh >/dev/null 2>&1
sleep 0.5
TW="$(bash tests/helpers/testwin-start.sh 'wa-probe')"
printf '%s' "$TW" | jq -e '.ok' >/dev/null 2>&1 || { echo "FATAL: $TW"; exit 1; }
H="$(jq -r '.hwnd_dec' "$JSONF")"
EX="$(jq -r '(.edit.x + .edit.w/2)|floor' "$JSONF")"
EY="$(jq -r '(.edit.y + .edit.h/2)|floor' "$JSONF")"

focus_edit() {
  bin/wwin focus --hwnd "$H" >/dev/null 2>&1
  bin/winput click "$EX" "$EY" --expect-hwnd "$H" --focus --yes >/dev/null 2>&1
  sleep 0.2
  bin/winput key ctrl+a --expect-hwnd "$H" --yes >/dev/null 2>&1
  bin/winput key delete --expect-hwnd "$H" --yes >/dev/null 2>&1
  sleep 0.15
}
read_edit() {
  bin/winput key ctrl+a --expect-hwnd "$H" --yes >/dev/null 2>&1
  bin/winput key ctrl+c --expect-hwnd "$H" --yes >/dev/null 2>&1
  sleep 0.25
  bin/wclip get 2>/dev/null | jq -r '.text // ""'
}

# ---- K1: keydown + keyup of one character types it exactly once ----
focus_edit
D1="$(bin/winput keydown a --expect-hwnd "$H" --yes)"
U1="$(bin/winput keyup a --yes)"
sleep 0.3
T1="$(read_edit)"
if printf '%s' "$D1" | jq -e '.ok == true and .vk == 65' >/dev/null 2>&1 && [ "$T1" = "a" ]; then
  pass "K1 keydown a -> keyup a typed exactly 'a'"
else
  fail "K1 keydown/keyup: text='$T1' down=$(printf '%s' "$D1" | head -c 120)"
fi

# ---- K2: key --hold keeps the combo down for the requested time (still one 'a') ----
focus_edit
H2="$(bin/winput key a --hold 300 --expect-hwnd "$H" --yes)"
sleep 0.3
T2="$(read_edit)"
if printf '%s' "$H2" | jq -e '.ok == true and .hold == 300' >/dev/null 2>&1 && [ "$T2" = "a" ]; then
  pass "K2 key --hold 300: one 'a' typed, hold reported"
else
  fail "K2 key --hold: text='$T2' out=$(printf '%s' "$H2" | head -c 160)"
fi

# ---- K3: keydown records the held key; keyup clears it ----
focus_edit
bin/winput keydown shift --expect-hwnd "$H" --yes >/dev/null
S1="$(jq -c . "$HELD" 2>/dev/null)"
bin/winput keyup shift --yes >/dev/null
if [ "$S1" = "[16]" ] && [ ! -f "$HELD" ]; then
  pass "K3 held state: [16] while down, cleared on keyup"
else
  fail "K3 held state: down=$S1 after=$(cat "$HELD" 2>/dev/null || echo none)"
fi

# ---- K4: releaseall frees everything left down and leaves typing usable ----
focus_edit
bin/winput keydown ctrl --expect-hwnd "$H" --yes >/dev/null
bin/winput keydown shift --expect-hwnd "$H" --yes >/dev/null
RA="$(bin/winput releaseall --yes)"
sleep 0.2
printf 'ok' > "$WIN/tmp/m8-typed.txt"
bin/winput type --text-file "$WIN/tmp/m8-typed.txt" --expect-hwnd "$H" --focus --yes >/dev/null 2>&1
sleep 0.4
T4="$(read_edit)"
if printf '%s' "$RA" | jq -e '.ok == true and (.released | length) == 2' >/dev/null 2>&1 \
   && [ ! -f "$HELD" ] && [ "$T4" = "ok" ]; then
  pass "K4 releaseall released 2 keys; typing still works (text='$T4')"
else
  fail "K4 releaseall: $(printf '%s' "$RA" | head -c 120) text='$T4' held=$(cat "$HELD" 2>/dev/null || echo none)"
fi

# ---- K5: argument contracts ----
bin/winput key a --hold -1 --expect-hwnd "$H" >/dev/null 2>&1; k5a=$?
bin/winput keydown 'ctrl+a' >/dev/null 2>&1; k5b=$?
bin/winput keydown nosuchkey --expect-hwnd "$H" >/dev/null 2>&1; k5c=$?
bin/winput releaseall extra >/dev/null 2>&1; k5d=$?
if [ "$k5a" -eq 2 ] && [ "$k5b" -eq 2 ] && [ "$k5c" -eq 2 ] && [ "$k5d" -eq 2 ]; then
  pass "K5 arg contracts: hold<0 / combo to keydown / unknown key / releaseall extra all rc=2"
else
  fail "K5 arg contracts: $k5a/$k5b/$k5c/$k5d (want 2/2/2/2)"
fi

# ---- K6: dry-run of keydown presses nothing but reports the plan ----
focus_edit
DR="$(bin/winput keydown shift --expect-hwnd "$H")"
sleep 0.2
if printf '%s' "$DR" | jq -e '.ok == true and .dryRun == true and .vk == 16' >/dev/null 2>&1 && [ ! -f "$HELD" ]; then
  pass "K6 keydown dry-run: plan only, nothing held"
else
  fail "K6 keydown dry-run: $(printf '%s' "$DR" | head -c 160) held=$(cat "$HELD" 2>/dev/null || echo none)"
fi

# ---- K7: no grant -> keydown/keyup/releaseall refused (rc=4) ----
rm -f "$G"
bin/winput keydown a --expect-hwnd "$H" --yes >/dev/null 2>&1; k7a=$?
bin/winput keyup a --yes >/dev/null 2>&1; k7b=$?
bin/winput key a --expect-hwnd "$H" --yes >/dev/null 2>&1; k7c=$?
if [ "$k7a" -eq 4 ] && [ "$k7b" -eq 4 ] && [ "$k7c" -eq 4 ]; then
  pass "K7 no grant -> keydown/keyup/key all rc=4"
else
  fail "K7 guard gate: $k7a/$k7b/$k7c (want 4/4/4)"
fi

echo "-----"
echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
