#!/usr/bin/env bash
# tests/check-m25.sh - M25/T31 acceptance: ops/chip-add, ops/rich-write, ops/wait-ready (F22-1..4, v1.4).
set -uo pipefail
cd "$(dirname "$0")/.."
. "$(pwd)/lib/common.sh"

PASS=0; FAIL=0
num() { printf '%s' "$1" | jq -r ".$2" 2>/dev/null; }
ok() { echo "PASS  $1"; PASS=$((PASS+1)); }
no() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }

WIN=/mnt/c/Users/Public/win-admin
G="$STATE_DIR/grant.json"
GBK="$STATE_DIR/grant.json.m25-bak"
JSONF="$WIN/tmp/chipwin.json"
EV="$WIN/tmp/chipwin-events.txt"
INPUT='^CHIP-INPUT$'
LIST='^chip-list$'

cleanup() {
  bash tests/helpers/chipwin-stop.sh >/dev/null 2>&1
  if [ -f "$GBK" ]; then mv -f "$GBK" "$G"; else rm -f "$G"; fi
}
trap cleanup EXIT

start_fixture() {   # start_fixture MODE READY_MS -> sets H
  local mode="$1" ready="$2" s
  bash tests/helpers/chipwin-stop.sh >/dev/null 2>&1
  sleep 0.4
  s="$(bash tests/helpers/chipwin-start.sh wa-chips "$mode" "$ready" 2>/dev/null)"
  if ! printf '%s' "$s" | jq -e '.ok' >/dev/null 2>&1; then echo "FATAL: $s"; exit 1; fi
  H="$(jq -r '.hwnd_dec' "$JSONF")"
  echo "INFO  fixture: hwnd=$H pid=$(jq -r '.pid' "$JSONF") mode=$mode readyAfterMs=$ready"
  bin/wwin focus --hwnd "$H" >/dev/null 2>&1
}
title() { bin/wwin info --hwnd "$H" 2>/dev/null | jq -r '.window.title'; }
rect_of() { bin/wuia --hwnd "$H" --find-name "$1" --index 0 2>/dev/null | jq -c '.nodes[0].rect // empty'; }

[ -f "$G" ] && cp -f "$G" "$GBK"
bash guard/grant.sh issue --minutes 30 --scope shot,uia,input,file:read --note "tests/check-m25.sh 本机验收（chip-add/rich-write/wait-ready）" >/dev/null 2>&1 || true

# --- F22-4 first: the fixture becomes ready only after 5s, so a correct waiter must poll at
# least twice and then report the real rect it saw.
start_fixture none 5000
W="$(bash ops/wait-ready --hwnd "$H" --require '^READY-MARK$' --timeout 12000 2>/dev/null)"; RC=$?
WR="$(num "$W" matched.rect.w)"
if [ "$RC" -eq 0 ] && [ "$(num "$W" ok)" = "true" ] && [ "$(num "$W" polls)" -ge 2 ] &&
   [ "$(num "$W" matched.name)" = "READY-MARK" ] && [ "$WR" != "null" ] && [ "$WR" -gt 2 ]; then
  ok "F22-4 wait-ready: polls=$(num "$W" polls) elapsedMs=$(num "$W" elapsedMs) matched=READY-MARK rect.w=$WR"
else
  no "F22-4 wait-ready: rc=$RC polls=$(num "$W" polls) matched=$(num "$W" matched.name) rect.w=$WR :: $(printf '%s' "$W" | head -c 300)"
fi

# --- F22-4 timeout: lastCount tells "never appeared" apart from "appeared but not laid out".
WT="$(bash ops/wait-ready --hwnd "$H" --require '^NEVER-THERE$' --timeout 700 2>/dev/null)"; RC=$?
if [ "$RC" -eq 3 ] && [ "$(num "$WT" code)" = "ENV_TIMEOUT" ] &&
   [ "$(num "$WT" polls)" -ge 1 ] && [ "$(num "$WT" lastCount)" = "0" ]; then
  ok "F22-4 timeout: rc=3 ENV_TIMEOUT polls=$(num "$WT" polls) elapsedMs=$(num "$WT" elapsedMs) lastCount=0"
else
  no "F22-4 timeout: rc=$RC code=$(num "$WT" code) polls=$(num "$WT" polls) lastCount=$(num "$WT" lastCount) :: $(printf '%s' "$WT" | head -c 300)"
fi

# --- F22-1 dry-run: a plan only, no click, no keystroke, the title witness stays put.
start_fixture none 800
T0="$(title)"
D="$(bash ops/chip-add --hwnd "$H" --input "$INPUT" --list "$LIST" --value TAG-A1 2>/dev/null)"; RC=$?
T1="$(title)"
if [ "$RC" -eq 0 ] && [ "$(num "$D" dry_run)" = "true" ] && [ "$(num "$D" chipsBefore)" = "2" ] &&
   [ "$(num "$D" 'chips|length')" = "2" ] && [ "$T0" = "$T1" ]; then
  ok "F22-1 dry-run: rc=0 dry_run=true chipsBefore=2 chips=[$(num "$D" chips | tr -d '\n')] title unchanged"
else
  no "F22-1 dry-run: rc=$RC dry_run=$(num "$D" dry_run) chipsBefore=$(num "$D" chipsBefore) title '$T0' -> '$T1' :: $(printf '%s' "$D" | head -c 300)"
fi

# --- F22-1 real: one chip lands, named exactly TAG-A1, and the window title counts 3.
C="$(bash ops/chip-add --hwnd "$H" --input "$INPUT" --list "$LIST" --value TAG-A1 --yes 2>/dev/null)"; RC=$?
CA="$(title)"
if [ "$RC" -eq 0 ] && [ "$(num "$C" chipsBefore)" = "2" ] && [ "$(num "$C" chipsAfter)" = "3" ] &&
   [ "$(num "$C" added)" = "TAG-A1" ] && [ "$(num "$C" retried)" = "0" ] &&
   [ "$(num "$C" 'glued|length')" = "0" ] && [ "$(num "$C" inputCleared)" = "true" ] &&
   case "$CA" in *chips=3*) true ;; *) false ;; esac; then
  ok "F22-1 chip-add: chipsBefore=2 chipsAfter=3 added=TAG-A1 retried=0 inputCleared=true title '$CA'"
else
  no "F22-1 chip-add: rc=$RC before=$(num "$C" chipsBefore) after=$(num "$C" chipsAfter) retried=$(num "$C" retried) glued=$(num "$C" glued | length) cleared=$(num "$C" inputCleared) title '$CA' :: $(printf '%s' "$C" | head -c 400)"
fi

# --- F22-1 the gluing trap: pre-fill the input with a prefix and let chip-add run. ctrl+a must
# replace it - a "TAG-TAG-Z1" chip means the tool typed on top of stale text.
IC="$(rect_of "$INPUT")"
ICX=$(( $(printf '%s' "$IC" | jq -r '.x') + $(printf '%s' "$IC" | jq -r '.w') / 2 ))
ICY=$(( $(printf '%s' "$IC" | jq -r '.y') + $(printf '%s' "$IC" | jq -r '.h') / 2 ))
bin/winput click "$ICX" "$ICY" --expect-hwnd "$H" --yes --focus >/dev/null 2>&1
bin/winput type --text 'TAG-' --expect-hwnd "$H" --yes >/dev/null 2>&1
GL="$(bash ops/chip-add --hwnd "$H" --input "$INPUT" --list "$LIST" --value TAG-Z1 --yes 2>/dev/null)"; RC=$?
GLUED="$(printf '%s' "$GL" | jq -c '.glued // []' 2>/dev/null)"
if [ "$RC" -eq 0 ] && [ "$(num "$GL" chipsAfter)" = "4" ] && [ "$GLUED" = "[]" ] &&
   [ "$(num "$GL" inputCleared)" = "true" ]; then
  ok "F22-1 no glue: pre-filled input 'TAG-' replaced, chipsAfter=4 glued=[]"
else
  no "F22-1 no glue: rc=$RC after=$(num "$GL" chipsAfter) glued=$GLUED chips=[$(printf '%s' "$GL" | jq -c '.chips // []' 2>/dev/null)] :: $(printf '%s' "$GL" | head -c 400)"
fi

# --- F22-2 first Enter swallowed: one retry lands the chip (retried:1), no double chip.
start_fixture first 800
SF="$(bash ops/chip-add --hwnd "$H" --input "$INPUT" --list "$LIST" --value TAG-B1 --yes 2>/dev/null)"; RC=$?
if [ "$RC" -eq 0 ] && [ "$(num "$SF" retried)" = "1" ] && [ "$(num "$SF" chipsAfter)" = "3" ] &&
   [ "$(num "$SF" lastAttempt)" = "enter-again" ] && [ "$(num "$SF" 'chips|length')" = "3" ]; then
  ok "F22-2 swallowed first: retried=1 lastAttempt=enter-again chipsAfter=3 chips=[$(printf '%s' "$SF" | jq -c '.chips')]"
else
  no "F22-2 swallowed first: rc=$RC retried=$(num "$SF" retried) after=$(num "$SF" chipsAfter) last=$(num "$SF" lastAttempt) :: $(printf '%s' "$SF" | head -c 400)"
fi

# --- F22-2 every Enter swallowed: two attempts, then a mismatch that keeps the evidence.
start_fixture all 800
SM="$(bash ops/chip-add --hwnd "$H" --input "$INPUT" --list "$LIST" --value TAG-C1 --timeout 900 --yes 2>/dev/null)"; RC=$?
if [ "$RC" -eq 3 ] && [ "$(num "$SM" code)" = "ENV_CHIP_MISMATCH" ] &&
   [ "$(num "$SM" attempts)" = "2" ] && [ "$(num "$SM" retried)" = "1" ] &&
   [ "$(num "$SM" chipsAfter)" = "$(num "$SM" chipsBefore)" ] &&
   [ "$(num "$SM" 'chips|length')" = "2" ]; then
  ok "F22-2 swallowed all: rc=3 ENV_CHIP_MISMATCH attempts=2 retried=1 chipsAfter=$(num "$SM" chipsAfter) unchanged"
else
  no "F22-2 swallowed all: rc=$RC code=$(num "$SM" code) attempts=$(num "$SM" attempts) retried=$(num "$SM" retried) after=$(num "$SM" chipsAfter) :: $(printf '%s' "$SM" | head -c 400)"
fi

# --- F22-3 rich-write: click the editor, ctrl+a, paste, then PROVE it by reading the document
# back (TextPattern); the editor appends a newline, so the verdict is a prefix match.
printf 'hello line 1\nhello line 2\n' > /tmp/m25-rich.txt
RR="$(rect_of '^RICH-BODY$')"
RX=$(( $(printf '%s' "$RR" | jq -r '.x') + $(printf '%s' "$RR" | jq -r '.w') / 2 ))
RY=$(( $(printf '%s' "$RR" | jq -r '.y') + $(printf '%s' "$RR" | jq -r '.h') / 2 ))
RW="$(bash ops/rich-write --hwnd "$H" --point "$RX,$RY" --text-file /tmp/m25-rich.txt --yes 2>/dev/null)"; RC=$?
GOTC="$(num "$RW" gotChars)"
if [ "$RC" -eq 0 ] && [ "$(num "$RW" matched)" = "true" ] && [ "$(num "$RW" readback.via)" = "element" ] &&
   [ "$(num "$RW" expectedChars)" = "25" ] && [ "$GOTC" != "null" ] && [ "$GOTC" -ge 25 ]; then
  ok "F22-3 rich-write: matched=true via=element expectedChars=25 gotChars=$GOTC point=$RX,$RY"
else
  no "F22-3 rich-write: rc=$RC matched=$(num "$RW" matched) via=$(num "$RW" readback.via) gotChars=$GOTC :: $(printf '%s' "$RW" | head -c 400)"
fi

# --- F22-3 negative: a verify target that cannot hold the text must fail loudly, and it must
# NOT fall back to the window body (that would "match" text that never reached the element).
NR="$(bash ops/rich-write --hwnd "$H" --point "$RX,$RY" --text-file /tmp/m25-rich.txt --verify-aid '^TAG-00$' --timeout 400 --yes 2>/dev/null)"; RC=$?
if [ "$RC" -eq 3 ] && [ "$(num "$NR" code)" = "ENV_TEXT_NOT_ENTERED" ] &&
   [ "$(num "$NR" matched)" = "false" ]; then
  ok "F22-3 negative: rc=3 ENV_TEXT_NOT_ENTERED matched=false (no window-body fallback)"
else
  no "F22-3 negative: rc=$RC code=$(num "$NR" code) matched=$(num "$NR" matched) via=$(num "$NR" readback.via) :: $(printf '%s' "$NR" | head -c 400)"
fi

# --- argument guards: nothing to add / nothing to wait for / a point that is not X,Y / a list
# that does not exist.
bash ops/chip-add --hwnd "$H" --input "$INPUT" --list "$LIST" >/dev/null 2>&1; RC1=$?
bash ops/wait-ready --hwnd "$H" >/dev/null 2>&1; RC2=$?
bash ops/rich-write --hwnd "$H" --point 1280 --text-file /tmp/m25-rich.txt >/dev/null 2>&1; RC3=$?
NL="$(bash ops/chip-add --hwnd "$H" --input "$INPUT" --list '^NO-SUCH-LIST$' --value X1 --yes 2>/dev/null)"; RC4=$?
if [ "$RC1" -eq 2 ] && [ "$RC2" -eq 2 ] && [ "$RC3" -eq 2 ] &&
   [ "$RC4" -eq 3 ] && [ "$(num "$NL" code)" = "ENV_NO_LIST" ]; then
  ok "F22 guards: no value rc=2, no require rc=2, bad point rc=2, unknown list rc=3 ENV_NO_LIST"
else
  no "F22 guards: no-value rc=$RC1 no-require rc=$RC2 bad-point rc=$RC3 unknown-list rc=$RC4 code=$(num "$NL" code)"
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
