#!/usr/bin/env bash
# tests/check-m18.sh - M18 acceptance: click closed loop (T22, v1.3)
# Covers: N1 click --expect-change title proves the change; N2 a click with no visible effect is
#         ENV_NO_EFFECT after waiting the full deadline; N3 every click reports hit, null + reason
#         when nothing is under the point; N4 hover reports the warm-tree element; N5 click-element
#         falls back to coords for a node without Invoke; N6 that coord click refuses when another
#         window covers the point (ENV_HIT_MISMATCH); N7/N8 argument contracts; N9 the input gate
#         still guards injection; N10 dry-run plans the same assertion without injecting.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 5
. "$(pwd)/lib/common.sh"
PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL %s  [%s]\n' "$1" "$2"; }
skip() { SKIP=$((SKIP+1)); printf 'SKIP %s  [%s]\n' "$1" "$2"; }
G="$STATE_DIR/grant.json"
GBK="$STATE_DIR/grant.json.m18-bak"
cleanup() {
  bash tests/helpers/deepwin-stop.sh >/dev/null 2>&1
  bash tests/helpers/uiawnd-stop.sh >/dev/null 2>&1
  if [ -f "$GBK" ]; then mv -f "$GBK" "$G"; fi
}
trap cleanup EXIT

num() { printf '%s' "$1" | jq -r ".$2 // empty"; }
diag() { printf '%s' "$1" | jq -c '{ok,code,changed,elapsedMs,strategy,hit:(.hit|{name,type,hwnd,actionable}),hitReason}'; }
# does rect at jq path $2 contain the point $3,$4?
contains() {
  printf '%s' "$1" | jq -e --argjson x "$3" --argjson y "$4" "($2) as \$r | (\$r.w > 0 and \$r.h > 0 and \$x >= \$r.x and \$x < (\$r.x + \$r.w) and \$y >= \$r.y and \$y < (\$r.y + \$r.h))" >/dev/null 2>&1
}

bash guard/grant.sh issue --minutes 30 --scope shot,uia,input,file:read --note "tests/check-m18.sh 本机验收（点击闭环）" >/dev/null 2>&1 || true
bash tests/helpers/deepwin-stop.sh >/dev/null 2>&1
bash tests/helpers/uiawnd-stop.sh >/dev/null 2>&1
sleep 0.5
OUT="$(bash tests/helpers/deepwin-start.sh 2>/dev/null)"
if [ "$(printf %s "$OUT" | jq -r .ok 2>/dev/null)" != "true" ]; then
  echo "deepwin failed to start: $OUT"; exit 5
fi
H="$(printf %s "$OUT" | jq -r .hwnd_dec)"
UOUT="$(bash tests/helpers/uiawnd-start.sh 2>/dev/null)"
if [ "$(printf %s "$UOUT" | jq -r .ok 2>/dev/null)" != "true" ]; then
  echo "uiawnd failed to start: $UOUT"; exit 5
fi
UH="$(printf %s "$UOUT" | jq -r .hwnd_dec)"
# park the second fixture where it cannot cover the first, and give the keyboard/mouse target back
bash bin/wwin set --hwnd "$UH" --x 2000 --y 300 --yes >/dev/null 2>&1
bash bin/wwin focus --hwnd "$H" >/dev/null 2>&1
sleep 0.4

WRECT="$(bash bin/wwin info --hwnd "$H" 2>/dev/null | jq -c '.window.rect')"
WRX="$(printf '%s' "$WRECT" | jq -r .x)"; WRY="$(printf '%s' "$WRECT" | jq -r .y)"
WRW="$(printf '%s' "$WRECT" | jq -r .w)"; WRH="$(printf '%s' "$WRECT" | jq -r .h)"
DEJ="$(bash bin/wuia --hwnd "$H" --find-aid deep-btn 2>/dev/null)"
NX="$(printf '%s' "$DEJ" | jq -r '.nodes[0].rect.x')"; NY="$(printf '%s' "$DEJ" | jq -r '.nodes[0].rect.y')"
NW="$(printf '%s' "$DEJ" | jq -r '.nodes[0].rect.w')"; NH="$(printf '%s' "$DEJ" | jq -r '.nodes[0].rect.h')"
DCX=$(( NX + NW / 2 )); DCY=$(( NY + NH / 2 ))

# N1 (E18-1) the click that changes the title proves it: ok, changed, before/after differ, hit says actionable
J="$(bash bin/winput click "$DCX" "$DCY" --expect-hwnd "$H" --expect-change title --timeout 3000 --yes 2>/dev/null)"; RC=$?
B="$(num "$J" before.title)"; A="$(num "$J" after.title)"
ACT="$(printf '%s' "$J" | jq -r '.hit.actionable // false')"
if [ "$RC" -eq 0 ] && [ "$(num "$J" ok)" = "true" ] && [ "$(num "$J" changed)" = "true" ] && [ -n "$B" ] && [ "$B" != "$A" ] && [ "$ACT" = "true" ]; then
  ok "N1 click --expect-change title -> changed '$B' -> '$A' in $(num "$J" elapsedMs) ms, hit actionable"
else
  bad "N1 expect-change success" "rc=$RC $(diag "$J")"
fi

# N2 (E18-2) a click on empty space inside the window is an honest ENV_NO_EFFECT after the deadline
BX=$(( WRX + WRW - 40 )); BY=$(( WRY + WRH - 40 ))
J2="$(bash bin/winput click "$BX" "$BY" --expect-hwnd "$H" --expect-change title --timeout 1000 --yes 2>/dev/null)"; RC2=$?
EL="$(num "$J2" elapsedMs)"
HAS_HIT="$(printf '%s' "$J2" | jq -r 'has("hit")')"
HAS_OBS="$(printf '%s' "$J2" | jq -r '(.observed != null)')"
if [ "$RC2" -eq 3 ] && [ "$(num "$J2" code)" = "ENV_NO_EFFECT" ] && [ -n "$EL" ] && [ "$EL" -ge 500 ] && [ "$HAS_HIT" = "true" ] && [ "$HAS_OBS" = "true" ]; then
  ok "N2 empty click -> rc=3 ENV_NO_EFFECT after $EL ms, hit present, observed present"
else
  bad "N2 expect-change failure" "rc=$RC2 $(diag "$J2")"
fi

# N3 (E18-3) every click reports what it hit: an object when something is there, null + reason when not
J3="$(bash bin/winput click "$DCX" "$DCY" --expect-hwnd "$H" --yes 2>/dev/null)"; RC3=$?
HN="$(num "$J3" hit.name)"
J4="$(bash bin/winput click "$BX" "$BY" --expect-hwnd "$H" --yes 2>/dev/null)"; RC4=$?
H4="$(printf '%s' "$J4" | jq -r '.hit')"
HR4="$(num "$J4" hitReason)"
if [ "$RC3" -eq 0 ] && [ -n "$HN" ] && [ "$RC4" -eq 0 ] && [ "$H4" = "null" ] && [ -n "$HR4" ]; then
  ok "N3 hit='$HN' on the button, hit=null + hitReason='$HR4' on empty space"
else
  bad "N3 hit reporting" "rc=$RC3/$RC4 $(diag "$J3") $(diag "$J4")"
fi

# N4 (E18-5) hover reports the warm-tree element under the cursor, not the window shell
J5="$(bash bin/winput hover "$DCX" "$DCY" --expect-hwnd "$H" --yes 2>/dev/null)"; RC5=$?
UT="$(num "$J5" underNode.type)"; UN="$(num "$J5" underNode.name)"
HAS_NODE="$(printf '%s' "$J5" | jq -r 'has("underNode")')"
HAS_COMPAT="$(printf '%s' "$J5" | jq -r '(.under.window != null and .under.element != null)')"
if [ "$RC5" -eq 0 ] && [ -n "$UN" ] && contains "$J5" '.underNode.rect' "$DCX" "$DCY" && [ "$UT" != "ControlType.Window" ] && [ "$UT" != "ControlType.Document" ] && [ "$HAS_NODE" = "true" ] && [ "$HAS_COMPAT" = "true" ]; then
  ok "N4 hover underNode='$UN' ($UT) contains the point; v1.2 under{window,element} kept"
else
  bad "N4 hover underNode" "rc=$RC5 node=$UN/$UT compat=$HAS_COMPAT $(diag "$J5")"
fi

# N5 (E18-4a) a node without Invoke (a TextBlock) is clicked by coordinates and says so
J6="$(bash ops/click-element --hwnd "$UH" --name '^LBL-TITLE$' --yes 2>/dev/null)"; RC6=$?
S6="$(num "$J6" strategy)"
H6="$(printf '%s' "$J6" | jq -r '.hit != null')"
if [ "$RC6" -eq 0 ] && [ "$S6" = "coords" ] && [ "$H6" = "true" ]; then
  ok "N5 click-element on TextBlock -> strategy=coords, hit=$(num "$J6" hit.name)"
else
  bad "N5 coords strategy" "rc=$RC6 $(diag "$J6")"
fi

# N6 (E18-4b) when another window covers the point, the coordinate click is refused, not fired
bash bin/wwin set --hwnd "$UH" --x $(( DCX - 260 )) --y $(( DCY - 310 )) --yes >/dev/null 2>&1
bash bin/wwin focus --hwnd "$UH" >/dev/null 2>&1
sleep 0.4
PU="$(bash bin/wuia --point "$DCX,$DCY" 2>/dev/null)"
PUH="$(num "$PU" under.hwnd)"
J7="$(bash ops/click-element --hwnd "$H" --aid deep-btn --strategy coords --yes 2>/dev/null)"; RC7=$?
if [ "$RC7" -eq 3 ] && [ "$(num "$J7" code)" = "ENV_HIT_MISMATCH" ] && [ -n "$PUH" ] && [ "$PUH" != "$(printf '0x%x' "$H")" ]; then
  ok "N6 covered point -> rc=3 ENV_HIT_MISMATCH (hit owner $PUH, target $(printf '0x%x' "$H"))"
else
  bad "N6 hit mismatch" "rc=$RC7 under.hwnd=$PUH $(diag "$J7")"
fi

# park the cover window again: N9/N10 assert the gate and the dry-run plan, and an overlapping
# window would trip their targeting checks first (ENV_HIT_MISMATCH / ENV_WINDOW_MISMATCH).
bash bin/wwin set --hwnd "$UH" --x 2000 --y 300 --yes >/dev/null 2>&1
bash bin/wwin focus --hwnd "$H" >/dev/null 2>&1
sleep 0.4

# N7 --strategy contract: bogus is refused, the old "click" spelling is reported as coords
bash ops/click-element --hwnd "$H" --aid deep-btn --strategy bogus >/dev/null 2>&1; N7A=$?
J8="$(bash ops/click-element --hwnd "$H" --aid deep-btn --strategy click 2>/dev/null)"
N7B="$(num "$J8" strategy)"
N7C="$(printf '%s' "$J8" | jq -r '.dry_run // false')"
if [ "$N7A" -eq 2 ] && [ "$N7B" = "coords" ] && [ "$N7C" = "true" ]; then
  ok "N7 --strategy bogus rc=2; --strategy click is coords (dry-run strategy=$N7B)"
else
  bad "N7 strategy contract" "bogus=$N7A strategy=$N7B dry=$N7C"
fi

# N8 --expect-change/--timeout contracts
bash bin/winput click "$DCX" "$DCY" --expect-hwnd "$H" --expect-change color --yes >/dev/null 2>&1; N8A=$?
bash bin/winput click "$DCX" "$DCY" --expect-hwnd "$H" --expect-change title --timeout 50 --yes >/dev/null 2>&1; N8B=$?
bash bin/winput hover "$DCX" "$DCY" --expect-hwnd "$H" --expect-change title --yes >/dev/null 2>&1; N8C=$?
if [ "$N8A" -eq 2 ] && [ "$N8B" -eq 2 ] && [ "$N8C" -eq 2 ]; then
  ok "N8 unknown field rc=2, --timeout 50 rc=2, --expect-change on hover rc=2"
else
  bad "N8 arg contracts" "field=$N8A timeout=$N8B hover=$N8C (want 2/2/2)"
fi

# N9 the input gate still covers the new path (both the click and the coords fallback)
cp -f "$G" "$GBK"
rm -f "$G"
bash bin/winput click "$DCX" "$DCY" --expect-hwnd "$H" --expect-change title --yes >/dev/null 2>&1; N9A=$?
bash ops/click-element --hwnd "$H" --aid deep-btn --strategy coords --yes >/dev/null 2>&1; N9B=$?
mv -f "$GBK" "$G"
if [ "$N9A" -eq 4 ] && [ "$N9B" -eq 4 ]; then
  ok "N9 no grant: click rc=4, click-element coords rc=4"
else
  bad "N9 guard gate" "click=$N9A coords=$N9B (want 4/4)"
fi

# N10 dry-run plans the same assertion without injecting
J9="$(bash bin/winput click "$DCX" "$DCY" --expect-hwnd "$H" --expect-change title 2>/dev/null)"; RC9=$?
D9="$(printf '%s' "$J9" | jq -r '.dryRun // false')"
CH9="$(printf '%s' "$J9" | jq -r 'has("changed")')"
H9="$(printf '%s' "$J9" | jq -r 'has("hit")')"
if [ "$RC9" -eq 0 ] && [ "$D9" = "true" ] && [ "$CH9" = "false" ] && [ "$H9" = "true" ]; then
  ok "N10 dry-run: dry_run=true, no changed field, hit still reported"
else
  bad "N10 dry-run" "rc=$RC9 dry=$D9 changed=$CH9 hit=$H9 code=$(printf '%s' "$J9" | jq -r '.code // "-"')"
fi

printf "\n%s passed, %s failed, %s skipped\n" "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" = "0" ] || exit 1
exit 0
