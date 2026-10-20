#!/usr/bin/env bash
# tests/check-m2.sh - M2 acceptance: C4 click, C5 type+readback, C6 drag, C7 wait-for, S1/S2/S7 safety.
# Own test window only (tests/helpers/testwin.ps1); never the user's apps.
set -uo pipefail
cd "$(dirname "$0")/.."
. "$(pwd)/lib/common.sh"

PASS=0; FAIL=0; SKIP=0
pass() { echo "PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
skip() { echo "SKIP  $1"; SKIP=$((SKIP+1)); }

WIN=/mnt/c/Users/Public/win-admin
G="$STATE_DIR/grant.json"
GBK="$STATE_DIR/grant.json.m2-test-bak"
CLICKS="$WIN/tmp/testwin-clicks.txt"
TEXT="$WIN/tmp/testwin-text.txt"

HAD_GRANT=0
cleanup() {
  bash tests/helpers/testwin-stop.sh >/dev/null 2>&1
  if [ "$HAD_GRANT" = "1" ]; then [ -f "$GBK" ] && mv "$GBK" "$G"; else rm -f "$G"; fi
  rm -f "$STATE_DIR/testwin.pid" "$STATE_DIR/testwin.pid.tmp"
}
trap cleanup EXIT

if [ -f "$G" ]; then cp "$G" "$GBK"; HAD_GRANT=1; fi
bash guard/grant.sh issue --minutes 30 --scope input --note "tests/check-m2.sh 本机验收（仓库自带测试窗口）" >/dev/null 2>&1 || true
bash tests/helpers/testwin-stop.sh >/dev/null 2>&1
sleep 0.5
rm -f "$CLICKS" "$TEXT"
TW="$(bash tests/helpers/testwin-start.sh 'wa-m2win')"
if ! printf '%s' "$TW" | jq -e '.ok' >/dev/null 2>&1; then
  echo "FATAL: cannot launch test window: $TW"; exit 1
fi
H="$(printf '%s' "$TW" | jq -r '.hwnd_dec')"
BX="$(printf '%s' "$TW" | jq -r '(.button.x + .button.w/2) | floor')"
BY="$(printf '%s' "$TW" | jq -r '(.button.y + .button.h/2) | floor')"
EX="$(printf '%s' "$TW" | jq -r '(.edit.x + 40) | floor')"
EY="$(printf '%s' "$TW" | jq -r '(.edit.y + 30) | floor')"
echo "# test window hwnd=$H button=$BX,$BY edit=$EX,$EY"

# ---- C4a dry-run plan ----
plan="$(bash bin/winput click "$BX" "$BY" --expect-hwnd "$H")"
if printf '%s' "$plan" | jq -e --argjson bx "$BX" --argjson by "$BY" '.ok == true and .dryRun == true and .injected == false and .point.x == $bx and .point.y == $by' >/dev/null 2>&1; then
  pass "C4a dry-run click plan, no injection ($BX,$BY)"
else
  fail "C4a dry-run click plan: $plan"
fi

# ---- C4b 10 real clicks ----
okc=0
for i in $(seq 1 10); do
  out="$(bash bin/winput click "$BX" "$BY" --expect-hwnd "$H" --focus --yes)"
  printf '%s' "$out" | jq -e '.ok == true and .injected == true' >/dev/null 2>&1 && okc=$((okc+1))
done
sleep 0.6
rec=0
[ -f "$CLICKS" ] && rec="$(grep -c . "$CLICKS")"
if [ "$okc" -eq 10 ] && [ "$rec" -ge 10 ]; then
  pass "C4b 10/10 real clicks landed (commands ok=$okc, app-side counter=$rec)"
  echo "      clicks: $(tr '\n' '|' < "$CLICKS")"
else
  fail "C4b real clicks: commands ok=$okc/10 app-side counter=$rec"
fi

# ---- C5 type + readback ----
bash bin/winput click "$EX" "$EY" --expect-hwnd "$H" --focus --yes >/dev/null 2>&1
SAMPLE='Hello 世界 — 中文输入 ✅ line2'
tout="$(bash bin/winput type --text "$SAMPLE" --expect-hwnd "$H" --yes)"
sleep 0.4
val="$(bash bin/wuia --hwnd "$H" --value | jq -r '.value // ""')"
vlen="$(printf '%s' "$val" | wc -m)"
if [ "$(printf '%s' "$tout" | jq -r '.ok')" = "true" ] && [ "$val" = "$SAMPLE" ]; then
  pass "C5 type+readback exact via UIA ValuePattern ($vlen chars)"
else
  fail "C5 type+readback: ok=$(printf '%s' "$tout" | jq -r '.ok') readback=[$val]"
fi
file="$(cat "$TEXT" 2>/dev/null)"
if [ "$file" = "$SAMPLE" ]; then
  pass "C5b app-side text equals input (independent oracle)"
else
  fail "C5b app-side text mismatch: [$file]"
fi

# ---- C6 drag ----
RB="$(bash bin/wwin info --hwnd "$H" | jq -c '.window.rect')"
X1=$(( $(printf '%s' "$RB" | jq -r '.x') + 250 )); Y1=$(( $(printf '%s' "$RB" | jq -r '.y') + 22 ))
X2=$((X1+300)); Y2=$((Y1+150))
dout="$(bash bin/winput drag "$X1" "$Y1" "$X2" "$Y2" --expect-hwnd "$H" --focus --yes)"
sleep 0.5
RA="$(bash bin/wwin info --hwnd "$H" | jq -c '.window.rect')"
dx=$(( $(printf '%s' "$RA" | jq -r '.x') - $(printf '%s' "$RB" | jq -r '.x') - 300 ))
dy=$(( $(printf '%s' "$RA" | jq -r '.y') - $(printf '%s' "$RB" | jq -r '.y') - 150 ))
ax=$(( dx < 0 ? -dx : dx )); ay=$(( dy < 0 ? -dy : dy ))
if [ "$(printf '%s' "$dout" | jq -r '.ok')" = "true" ] && [ "$ax" -le 3 ] && [ "$ay" -le 3 ]; then
  pass "C6 drag delta=($dx,$dy) px, absolute err <= 3"
else
  fail "C6 drag: ok=$(printf '%s' "$dout" | jq -r '.ok') delta=($dx,$dy) before=$RB after=$RA"
fi

# ---- C7 wait-for ----
bash tests/helpers/testwin-stop.sh >/dev/null 2>&1
rm -f /tmp/wa-m2-wait.json
( bash bin/wwait --title 'wa-m2c7' --timeout 20 --interval 100 > /tmp/wa-m2-wait.json ) &
WPID=$!
sleep 2
bash tests/helpers/testwin-start.sh 'wa-m2c7' >/dev/null
wait $WPID
lat="$(python3 - <<'PY'
import json
try:
    w=json.load(open('/tmp/wa-m2-wait.json'))
    t=json.load(open('/mnt/c/Users/Public/win-admin/tmp/testwin.json'))
    print(abs(w['at_epoch_ms']-t['at_epoch_ms']))
except Exception:
    print(99999)
PY
)"
if [ "$lat" -ge 0 ] && [ "$lat" -le 200 ]; then
  pass "C7 wait-for detected the window within $lat ms of it appearing (<= 200, same-poll clamp)"
else
  fail "C7 wait-for latency: $lat ms"
fi
TOUT="$(bash bin/wwait --title 'no-such-window-m2-xyz' --timeout 1)"
if printf '%s' "$TOUT" | jq -e '.ok == false and .code == "ENV_WAIT_TIMEOUT"' >/dev/null 2>&1; then
  pass "C7b timeout errors (ENV_WAIT_TIMEOUT exit 3), no fake success"
else
  fail "C7b timeout: $TOUT"
fi
bash tests/helpers/testwin-stop.sh >/dev/null 2>&1

# ---- S7 coordinate target check ----
m1="$(bash bin/winput click 100 100 --expect-hwnd 999999 --yes)"; r1=$?
if [ $r1 -eq 3 ] && printf '%s' "$m1" | jq -e '.code == "ENV_NO_WINDOW"' >/dev/null 2>&1; then
  pass "S7a bogus --expect-hwnd refused (exit 3 ENV_NO_WINDOW)"
else
  fail "S7a bogus --expect-hwnd: exit=$r1 $m1"
fi
m2="$(bash bin/winput click 100 100 --yes)"; r2=$?
if [ $r2 -eq 2 ] && printf '%s' "$m2" | jq -e '.code == "ARG_NEED_EXPECT_HWND"' >/dev/null 2>&1; then
  pass "S7b coordinate click without --expect-hwnd refused (exit 2)"
else
  fail "S7b click without target: exit=$r2 $m2"
fi

# ---- S1 no grant ----
mv "$G" "$GBK"
p1="$(bash bin/winput move 200 200 --yes)"; r3=$?
mv "$GBK" "$G"
if [ $r3 -eq 4 ] && printf '%s' "$p1" | jq -e '.code == "GUARD_NO_GRANT"' >/dev/null 2>&1; then
  pass "S1 no grant -> exit 4 GUARD_NO_GRANT, nothing injected"
else
  fail "S1 no grant: exit=$r3 $p1"
fi

# ---- S2 pause ----
bash guard/grant.sh pause >/dev/null
p2="$(bash bin/winput move 200 200 --yes)"; r4=$?
bash guard/grant.sh resume >/dev/null
if [ $r4 -eq 4 ] && printf '%s' "$p2" | jq -e '.code == "GUARD_PAUSED"' >/dev/null 2>&1; then
  pass "S2 pause.flag -> exit 4 GUARD_PAUSED, nothing injected"
else
  fail "S2 pause: exit=$r4 $p2"
fi

echo
echo "SUMMARY pass=$PASS fail=$FAIL skip=$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
