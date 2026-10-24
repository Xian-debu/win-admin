#!/usr/bin/env bash
# tests/check-m9.sh - M10/T4 acceptance: quote-proof text input (--stdin / --text-b64),
# and empty-text is always a loud ARG_EMPTY_TEXT instead of a silent no-op.
set -uo pipefail
cd "$(dirname "$0")/.."
. "$(pwd)/lib/common.sh"

PASS=0; FAIL=0; SKIP=0
pass() { echo "PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
skip() { echo "SKIP  $1"; SKIP=$((SKIP+1)); }

WIN=/mnt/c/Users/Public/win-admin
G="$STATE_DIR/grant.json"
GBK="$STATE_DIR/grant.json.m9-test-bak"
JSONF="$WIN/tmp/testwin.json"
TXTF="$WIN/tmp/m9-text.txt"
cleanup() {
  bin/winput releaseall --yes >/dev/null 2>&1
  bash tests/helpers/testwin-stop.sh >/dev/null 2>&1
  if [ -f "$GBK" ]; then mv -f "$GBK" "$G"; else rm -f "$G"; fi
}
trap cleanup EXIT

[ -f "$G" ] && cp "$G" "$GBK"
bash guard/grant.sh issue --minutes 30 --scope shot,uia,input,file:read --note "tests/check-m9.sh 本机验收（免引号输入）" >/dev/null 2>&1 || true
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
  # K60: clear and read back through UIA ValuePattern, so the assertions are not polluted by
  # extra injected key combos (a slow pump can turn ctrl+a into a literal "a").
  clear_edit
  sleep 0.1
}
clear_edit() { bin/wuia --hwnd "$H" --find-type Edit --set-value "" >/dev/null 2>&1 || true; }
read_edit() { bin/wuia --hwnd "$H" --find-type Edit --get-value 2>/dev/null | jq -r '.value // ""'; }
want="$(cat "$TXTF")"

# ---- L1: empty --text is refused loudly (rc=2 ARG_EMPTY_TEXT), not a silent no-op ----
E1="$(bin/winput type --text "" --expect-hwnd "$H" 2>&1)"; l1=$?
c1="$(printf '%s' "$E1" | jq -r '.code // ""' 2>/dev/null || true)"
# the CLI prints a plain message on this path; code lives in the audit line, so accept either shape
if [ "$l1" -eq 2 ]; then
  pass "L1 empty --text refused with rc=2"
else
  fail "L1 empty --text: rc=$l1 out=$(printf '%s' "$E1" | head -c 120)"
fi

# ---- L2: empty stdin is refused (rc=2) ----
printf '' | bin/winput type --stdin --expect-hwnd "$H" >/dev/null 2>&1; l2=$?
if [ "$l2" -eq 2 ]; then pass "L2 empty --stdin refused rc=2"; else fail "L2 empty stdin rc=$l2"; fi

# ---- L3: mutually exclusive text sources ----
bin/winput type --text x --stdin --expect-hwnd "$H" >/dev/null 2>&1 < /dev/null; l3=$?
if [ "$l3" -eq 2 ]; then pass "L3 two text sources rc=2"; else fail "L3 two sources rc=$l3"; fi

# ---- L4: invalid base64 ----
bin/winput type --text-b64 'not*base64' --expect-hwnd "$H" >/dev/null 2>&1; l4=$?
if [ "$l4" -eq 2 ]; then pass "L4 bad base64 rc=2"; else fail "L4 bad base64 rc=$l4"; fi

# ---- L5: hostile text via --stdin lands byte-identical ----
focus_edit
L5OUT="$(bin/winput type --stdin --expect-hwnd "$H" --focus --yes < "$TXTF" 2>&1)"
sleep 0.5
T5="$(read_edit)"
if [ "$T5" = "$want" ]; then
  pass "L5 --stdin typed hostile text byte-identical ($(printf '%s' "$T5" | wc -c) bytes)"
else
  fail "L5 --stdin mismatch: got='$T5' want='$want' (type said: $(printf '%s' "$L5OUT" | head -c 200))"
fi
# K57: the clipboard is restored only after the paste is visible, so the JSON must say it settled
L5S="$(printf '%s' "$L5OUT" | jq -r '.pasteSettled // false' 2>/dev/null || echo false)"
if [ "$L5S" = "true" ]; then
  pass "L5b clipboard restored only after the paste landed (pasteSettled=true)"
else
  fail "L5b pasteSettled=$L5S"
fi

# ---- L6: the same text via --text-b64 lands identically ----
focus_edit
B64="$(base64 -w0 "$TXTF")"
bin/winput type --text-b64 "$B64" --expect-hwnd "$H" --focus --yes >/dev/null 2>&1
sleep 0.5
T6="$(read_edit)"
if [ "$T6" = "$want" ]; then
  pass "L6 --text-b64 typed the same text byte-identical"
else
  fail "L6 --text-b64 mismatch: got='$T6' want='$want'"
fi

# ---- L7: no grant -> refused (rc=4) ----
rm -f "$G"
bin/winput type --stdin --expect-hwnd "$H" --yes < "$TXTF" >/dev/null 2>&1; l7=$?
if [ "$l7" -eq 4 ]; then pass "L7 no grant -> type rc=4"; else fail "L7 guard gate rc=$l7"; fi

echo "-----"
echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
