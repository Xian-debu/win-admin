#!/usr/bin/env bash
# tests/check-m24.sh - M24/T30 acceptance: ops/select-option (F21-1..5, v1.4).
set -uo pipefail
cd "$(dirname "$0")/.."
. "$(pwd)/lib/common.sh"

PASS=0; FAIL=0
num() { printf '%s' "$1" | jq -r ".$2" 2>/dev/null; }
ok() { echo "PASS  $1"; PASS=$((PASS+1)); }
no() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }

WIN=/mnt/c/Users/Public/win-admin
G="$STATE_DIR/grant.json"
GBK="$STATE_DIR/grant.json.m24-bak"
JSONF="$WIN/tmp/selectwin.json"

cleanup() {
  bash tests/helpers/selectwin-stop.sh >/dev/null 2>&1
  if [ -f "$GBK" ]; then mv -f "$GBK" "$G"; else rm -f "$G"; fi
}
trap cleanup EXIT

[ -f "$G" ] && cp -f "$G" "$GBK"
bash guard/grant.sh issue --minutes 30 --scope shot,uia,input,file:read --note "tests/check-m24.sh 本机验收（select-option）" >/dev/null 2>&1 || true
bash tests/helpers/selectwin-stop.sh >/dev/null 2>&1
sleep 0.5
S="$(bash tests/helpers/selectwin-start.sh 2>/dev/null)"
if ! printf '%s' "$S" | jq -e '.ok' >/dev/null 2>&1; then echo "FATAL: $S"; exit 1; fi
H="$(jq -r '.hwnd_dec' "$JSONF")"
echo "INFO  fixture: hwnd=$H pid=$(jq -r '.pid' "$JSONF")"
bin/wwin focus --hwnd "$H" >/dev/null 2>&1

# --- F21-5 first, while the panel is still scrolled to the top: item 28 is rendered but below the
# viewport, so the tool must reveal before clicking (steps>=1, clicked rect inside the container).
S28="$(bash ops/select-option --hwnd "$H" --trigger '^REGION-TRIGGER$' --option '^REGION-28$' \
        --expect-value 'region:REGION-28' --yes 2>/dev/null)"; RC=$?
CRX="$(num "$S28" container.rect.x)"; CRY="$(num "$S28" container.rect.y)"
CRW="$(num "$S28" container.rect.w)"; CRH="$(num "$S28" container.rect.h)"
EX="$(num "$S28" clicked.rect.x)"; EY="$(num "$S28" clicked.rect.y)"
EW="$(num "$S28" clicked.rect.w)"; EH="$(num "$S28" clicked.rect.h)"
INSIDE=0
if [ "$CRX" != "null" ] && [ "$EX" -ge "$((CRX-2))" ] && [ "$EY" -ge "$((CRY-2))" ] &&
   [ "$((EX+EW))" -le "$((CRX+CRW+2))" ] && [ "$((EY+EH))" -le "$((CRY+CRH+2))" ]; then INSIDE=1; fi
if [ "$RC" -eq 0 ] && [ "$(num "$S28" mode)" = "panel" ] && [ "$(num "$S28" steps)" -ge 1 ] &&
   [ "$(num "$S28" revealed)" = "true" ] && [ "$(num "$S28" matches)" = "true" ] &&
   [ "$(num "$S28" closed)" = "true" ] && [ "$(num "$S28" value.after)" = "region:REGION-28" ] &&
   [ "$INSIDE" -eq 1 ]; then
  ok "F21-5 reveal first: steps=$(num "$S28" steps) via=$(num "$S28" via) clicked y=$(num "$S28" clicked.rect.y) inside container (y $CRY..$((CRY+CRH)))"
else
  no "F21-5 reveal first: rc=$RC steps=$(num "$S28" steps) revealed=$(num "$S28" revealed) matches=$(num "$S28" matches) closed=$(num "$S28" closed) inside=$INSIDE :: $(printf '%s' "$S28" | head -c 400)"
fi

# --- F21-1 panel: plain in-page pick, witness title reads region:REGION-05 afterwards.
P="$(bash ops/select-option --hwnd "$H" --trigger '^REGION-TRIGGER$' --option '^REGION-05$' \
      --expect-value 'region:REGION-05' --yes 2>/dev/null)"; RC=$?
if [ "$RC" -eq 0 ] && [ "$(num "$P" mode)" = "panel" ] && [ "$(num "$P" clicked.name)" = "REGION-05" ] &&
   [ "$(num "$P" matches)" = "true" ] && [ "$(num "$P" closed)" = "true" ] &&
   [ "$(num "$P" value.before)" = "region:REGION-28" ] && [ "$(num "$P" value.after)" = "region:REGION-05" ]; then
  ok "F21-1 panel: mode=panel steps=$(num "$P" steps) value $(num "$P" value.before) -> $(num "$P" value.after) closed=true"
else
  no "F21-1 panel: rc=$RC mode=$(num "$P" mode) matches=$(num "$P" matches) closed=$(num "$P" closed) value=$(num "$P" value.before)->$(num "$P" value.after) :: $(printf '%s' "$P" | head -c 400)"
fi

# --- F21-1 dry-run: no trigger click, no option click; the witness title must stay put.
T0="$(bin/wwin info --hwnd "$H" 2>/dev/null | jq -r '.window.title')"
D="$(bash ops/select-option --hwnd "$H" --trigger '^REGION-TRIGGER$' --option '^REGION-03$' --dry-run 2>/dev/null)"; RC=$?
T1="$(bin/wwin info --hwnd "$H" 2>/dev/null | jq -r '.window.title')"
if [ "$RC" -eq 0 ] && [ "$(num "$D" dry_run)" = "true" ] && [ "$(num "$D" steps)" = "0" ] && [ "$T0" = "$T1" ]; then
  ok "F21-1 dry-run: rc=0 dry_run=true steps=0 title unchanged ($T1)"
else
  no "F21-1 dry-run: rc=$RC dry_run=$(num "$D" dry_run) title $T0 -> $T1 :: $(printf '%s' "$D" | head -c 300)"
fi

# --- F21-3 no such option: a clear miss that names both discovery paths, and Esc closes the list.
N="$(bash ops/select-option --hwnd "$H" --trigger '^REGION-TRIGGER$' --option '^NOPE$' --timeout 700 --yes 2>/dev/null)"; RC=$?
TRIED="$(printf '%s' "$N" | jq -c '.tried // []')"
if [ "$RC" -eq 3 ] && [ "$(num "$N" code)" = "ENV_NO_OPTION" ] && [ "$(num "$N" steps)" = "0" ] &&
   [ "$TRIED" = '["panel","native"]' ] && [ "$(num "$N" closed)" = "true" ]; then
  ok "F21-3 no option: rc=3 ENV_NO_OPTION steps=0 tried=$TRIED closed=true"
else
  no "F21-3 no option: rc=$RC code=$(num "$N" code) steps=$(num "$N" steps) tried=$TRIED closed=$(num "$N" closed) :: $(printf '%s' "$N" | head -c 300)"
fi

# --- F21-4 the pick lands but the witness disagrees: ENV_NO_EFFECT, with the values kept.
E="$(bash ops/select-option --hwnd "$H" --trigger '^REGION-TRIGGER$' --option '^REGION-02$' \
      --expect-value 'region:REGION-99' --yes 2>/dev/null)"; RC=$?
if [ "$RC" -eq 3 ] && [ "$(num "$E" code)" = "ENV_NO_EFFECT" ] &&
   [ "$(num "$E" value.before)" = "region:REGION-05" ] && [ "$(num "$E" value.after)" = "region:REGION-02" ] &&
   [ "$(num "$E" matches)" = "false" ]; then
  ok "F21-4 no effect: rc=3 ENV_NO_EFFECT value $(num "$E" value.before) -> $(num "$E" value.after) (expected region:REGION-99)"
else
  no "F21-4 no effect: rc=$RC code=$(num "$E" code) value=$(num "$E" value.before)->$(num "$E" value.after) :: $(printf '%s' "$E" | head -c 300)"
fi

# --- F21-2 native popup: the ComboBox dropdown is its own top-level HWND owned by the main window.
bin/winput key esc --expect-hwnd "$H" --yes >/dev/null 2>&1
NM="$(bash ops/select-option --hwnd "$H" --trigger-aid '^wa-cbo$' --option '^GREEN$' \
       --expect-value 'cbo:GREEN' --yes 2>/dev/null)"; RC=$?
PH="$(num "$NM" popup.hwnd)"
PH2="${PH:0:2}"
if [ "$RC" -eq 0 ] && [ "$(num "$NM" mode)" = "native" ] && [ "$PH2" = "0x" ] &&
   [ "$(num "$NM" popup.title)" = "" ] && [ "$(num "$NM" matches)" = "true" ] &&
   [ "$(num "$NM" closed)" = "true" ] && [ "$(num "$NM" value.after)" = "cbo:GREEN" ]; then
  ok "F21-2 native: mode=native popup=$PH matches=true value -> cbo:GREEN closed=true"
else
  no "F21-2 native: rc=$RC mode=$(num "$NM" mode) popup=$PH closed=$(num "$NM" closed) value=$(num "$NM" value.after) :: $(printf '%s' "$NM" | head -c 400)"
fi

# --- F21-3 mode guard: denying the panel path must fail loudly instead of clicking blind.
MG="$(bash ops/select-option --hwnd "$H" --trigger '^REGION-TRIGGER$' --option '^REGION-05$' --mode native --timeout 800 --yes 2>/dev/null)"; RC=$?
if [ "$RC" -eq 3 ] && [ "$(num "$MG" code)" = "ENV_NO_OPTION" ] && [ "$(num "$MG" steps)" = "0" ]; then
  ok "F21-3 mode guard: --mode native on an in-page panel -> rc=3 ENV_NO_OPTION"
else
  no "F21-3 mode guard: rc=$RC code=$(num "$MG" code) :: $(printf '%s' "$MG" | head -c 300)"
fi

# --- argument guards: nothing to pick, an unknown mode, no trigger, an unknown trigger.
bash ops/select-option --hwnd "$H" --trigger '^REGION-TRIGGER$' >/dev/null 2>&1; RC1=$?
bash ops/select-option --hwnd "$H" --trigger '^X$' --option '^Y$' --mode weird >/dev/null 2>&1; RC2=$?
bash ops/select-option --hwnd "$H" --option '^Y$' >/dev/null 2>&1; RC3=$?
NG="$(bash ops/select-option --hwnd "$H" --trigger '^MISSING$' --option '^Y$' --yes 2>/dev/null)"; RC4=$?
if [ "$RC1" -eq 2 ] && [ "$RC2" -eq 2 ] && [ "$RC3" -eq 2 ] &&
   [ "$RC4" -eq 3 ] && [ "$(num "$NG" code)" = "ENV_NO_TRIGGER" ]; then
  ok "F21-3 guards: no option rc=2, bad mode rc=2, no trigger arg rc=2, unknown trigger rc=3 ENV_NO_TRIGGER"
else
  no "F21-3 guards: no-option rc=$RC1 bad-mode rc=$RC2 no-trigger rc=$RC3 unknown-trigger rc=$RC4 code=$(num "$NG" code)"
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
