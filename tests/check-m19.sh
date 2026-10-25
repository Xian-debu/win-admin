#!/usr/bin/env bash
# tests/check-m19.sh - M19/T23 acceptance: type focus + landed-effects contract (C17, v1.3).
#   N1 focus on a non-editable control -> rc=3 ENV_NO_FOCUS, nothing injected
#   N2 readable value unchanged after the paste -> rc=3 ENV_NO_EFFECT, pasteSettled:false
#   N3 --force keeps the v1.2 answer (ok:true + forced:true)
#   N4 --force also bypasses the focus gate (the old "type anywhere" behaviour)
#   N5 editable target still types normally and reports pasteSettled:true
#   N6 --verify exact still proves the text landed
#   N7 --verify still fails when nothing landed, even with --force
#   N8 dry-run never runs the focus gate (it injects nothing)
#   N9 the input grant still guards type (rc=4)
#   N10 --no-restore-clip skips the read-back check instead of faking success
set -uo pipefail
cd "$(dirname "$0")/.."
. "$(pwd)/lib/common.sh"

PASS=0; FAIL=0; SKIP=0
pass() { echo "PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
# jq "// empty" swallows false, so read the value raw (missing key -> "null").
num() { printf '%s' "$1" | jq -r ".$2" 2>/dev/null; }

WIN=/mnt/c/Users/Public/win-admin
G="$STATE_DIR/grant.json"
GBK="$STATE_DIR/grant.json.m19-bak"
JSONF="$WIN/tmp/uiawnd.json"

cleanup() {
  bin/winput releaseall --yes >/dev/null 2>&1
  bash tests/helpers/uiawnd-stop.sh >/dev/null 2>&1
  if [ -f "$GBK" ]; then mv -f "$GBK" "$G"; else rm -f "$G"; fi
}
trap cleanup EXIT

[ -f "$G" ] && cp -f "$G" "$GBK"
bash guard/grant.sh issue --minutes 30 --scope shot,uia,input,file:read --note "tests/check-m19.sh 本机验收（type 焦点/落地）" >/dev/null 2>&1 || true
bash tests/helpers/uiawnd-stop.sh >/dev/null 2>&1
sleep 0.5
U="$(bash tests/helpers/uiawnd-start.sh 2>/dev/null)"
printf '%s' "$U" | jq -e '.ok' >/dev/null 2>&1 || { echo "FATAL: $U"; exit 1; }
H="$(jq -r '.hwnd_dec' "$JSONF")"

focus_aid() {
  bin/wwin focus --hwnd "$H" >/dev/null 2>&1
  bin/wuia --hwnd "$H" --find-aid "$1" --focus >/dev/null 2>&1
  sleep 0.2
}
get_val() { bin/wuia --hwnd "$H" --find-aid "$1" --get-value 2>/dev/null | jq -r '.value // ""'; }

# N1 (C17-1) a focused Button cannot receive text: refuse before injecting
focus_aid wa-btn
J1="$(bin/winput type --text x --expect-hwnd "$H" --focus --yes 2>/dev/null)"; RC1=$?
if [ "$RC1" -eq 3 ] && [ "$(num "$J1" code)" = "ENV_NO_FOCUS" ] && [ "$(num "$J1" focused.aid)" = "wa-btn" ] && [ "$(num "$J1" injected)" = "false" ]; then
  okmsg="N1 focused Button -> rc=3 ENV_NO_FOCUS (injected=false, focused=wa-btn)"
  echo "PASS  $okmsg"; PASS=$((PASS+1))
else
  echo "FAIL  N1 focus gate: rc=$RC1 $(printf '%s' "$J1" | head -c 300)"; FAIL=$((FAIL+1))
fi

# N2 (C17-2) a read-only editor is readable but the paste never lands
focus_aid wa-ro
J2="$(bin/winput type --text x --expect-hwnd "$H" --focus --yes 2>/dev/null)"; RC2=$?
if [ "$RC2" -eq 3 ] && [ "$(num "$J2" code)" = "ENV_NO_EFFECT" ] && [ "$(num "$J2" pasteSettled)" = "false" ] && [ "$(num "$J2" before)" = "$(num "$J2" after)" ]; then
  echo "PASS  N2 read-only editor -> rc=3 ENV_NO_EFFECT (pasteSettled=false, value unchanged)"; PASS=$((PASS+1))
else
  echo "FAIL  N2 landed check: rc=$RC2 $(printf '%s' "$J2" | head -c 300)"; FAIL=$((FAIL+1))
fi

# N3 (C17-3) --force reports the v1.2 shape: ok:true, pasteSettled:false, forced:true
J3="$(bin/winput type --text x --expect-hwnd "$H" --focus --yes --force 2>/dev/null)"; RC3=$?
if [ "$RC3" -eq 0 ] && [ "$(num "$J3" ok)" = "true" ] && [ "$(num "$J3" forced)" = "true" ] && [ "$(num "$J3" pasteSettled)" = "false" ]; then
  echo "PASS  N3 --force -> ok:true, forced:true, pasteSettled:false"; PASS=$((PASS+1))
else
  echo "FAIL  N3 --force landed shape: rc=$RC3 $(printf '%s' "$J3" | head -c 300)"; FAIL=$((FAIL+1))
fi

# N4 --force also bypasses the focus gate (focused Button, old behaviour)
focus_aid wa-btn
J4="$(bin/winput type --text x --expect-hwnd "$H" --focus --yes --force 2>/dev/null)"; RC4=$?
if [ "$RC4" -eq 0 ] && [ "$(num "$J4" ok)" = "true" ] && [ "$(num "$J4" forced)" = "true" ]; then
  echo "PASS  N4 --force bypasses the focus gate (ok:true, forced:true)"; PASS=$((PASS+1))
else
  echo "FAIL  N4 --force focus bypass: rc=$RC4 $(printf '%s' "$J4" | head -c 300)"; FAIL=$((FAIL+1))
fi

# N5 an editable target still types normally
focus_aid wa-edit
bin/wuia --hwnd "$H" --find-aid wa-edit --set-value "" >/dev/null 2>&1
J5="$(bin/winput type --text hello --expect-hwnd "$H" --focus --yes 2>/dev/null)"; RC5=$?
V5="$(get_val wa-edit)"
if [ "$RC5" -eq 0 ] && [ "$(num "$J5" ok)" = "true" ] && [ "$(num "$J5" pasteSettled)" = "true" ] && [ "$V5" = "hello" ]; then
  echo "PASS  N5 editable target -> ok:true, pasteSettled:true, value=hello"; PASS=$((PASS+1))
else
  echo "FAIL  N5 normal typing: rc=$RC5 value='$V5' $(printf '%s' "$J5" | head -c 220)"; FAIL=$((FAIL+1))
fi

# N6 --verify exact still proves the text landed
bin/wuia --hwnd "$H" --find-aid wa-edit --set-value "" >/dev/null 2>&1
J6="$(bin/winput type --text abc --expect-hwnd "$H" --focus --yes --verify exact 2>/dev/null)"; RC6=$?
if [ "$RC6" -eq 0 ] && [ "$(num "$J6" verify.matched)" = "true" ]; then
  echo "PASS  N6 --verify exact -> matched:true"; PASS=$((PASS+1))
else
  echo "FAIL  N6 verify: rc=$RC6 $(printf '%s' "$J6" | head -c 300)"; FAIL=$((FAIL+1))
fi

# N7 --verify still fails when nothing landed, even with --force
focus_aid wa-ro
J7="$(bin/winput type --text zz --expect-hwnd "$H" --focus --yes --force --verify exact 2>/dev/null)"; RC7=$?
if [ "$RC7" -eq 3 ] && [ "$(num "$J7" code)" = "ENV_TEXT_NOT_ENTERED" ] && [ "$(num "$J7" verify.matched)" = "false" ]; then
  echo "PASS  N7 --force + --verify still reports ENV_TEXT_NOT_ENTERED"; PASS=$((PASS+1))
else
  echo "FAIL  N7 forced verify: rc=$RC7 $(printf '%s' "$J7" | head -c 300)"; FAIL=$((FAIL+1))
fi

# N8 dry-run plans without running the focus gate (nothing is injected)
focus_aid wa-btn
J8="$(bin/winput type --text x --expect-hwnd "$H" --focus 2>/dev/null)"; RC8=$?
if [ "$RC8" -eq 0 ] && [ "$(num "$J8" dryRun)" = "true" ] && [ "$(num "$J8" ok)" = "true" ]; then
  echo "PASS  N8 dry-run on a Button -> dryRun:true (focus gate is injection-time only)"; PASS=$((PASS+1))
else
  echo "FAIL  N8 dry-run: rc=$RC8 $(printf '%s' "$J8" | head -c 300)"; FAIL=$((FAIL+1))
fi

# N9 the input grant still guards type
cp -f "$G" "$GBK" 2>/dev/null || true
rm -f "$G"
focus_aid wa-edit >/dev/null 2>&1
bin/winput type --text x --expect-hwnd "$H" --yes >/dev/null 2>&1; N9=$?
mv -f "$GBK" "$G"
if [ "$N9" -eq 4 ]; then
  echo "PASS  N9 no grant -> type rc=4"; PASS=$((PASS+1))
else
  echo "FAIL  N9 guard gate: rc=$N9 (want 4)"; FAIL=$((FAIL+1))
fi

# N10 --no-restore-clip skips the read-back effect check (caller owns the clipboard)
focus_aid wa-edit
bin/wuia --hwnd "$H" --find-aid wa-edit --set-value "" >/dev/null 2>&1
J10="$(bin/winput type --text q --expect-hwnd "$H" --focus --yes --no-restore-clip 2>/dev/null)"; RC10=$?
if [ "$RC10" -eq 0 ] && [ "$(num "$J10" ok)" = "true" ] && [ "$(num "$J10" clipRestored)" = "false" ]; then
  echo "PASS  N10 --no-restore-clip -> ok:true, clipRestored:false (no effect check)"; PASS=$((PASS+1))
else
  echo "FAIL  N10 no-restore-clip: rc=$RC10 $(printf '%s' "$J10" | head -c 300)"; FAIL=$((FAIL+1))
fi

echo
echo "$PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
