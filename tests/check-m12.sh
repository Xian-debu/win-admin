#!/usr/bin/env bash
# tests/check-m12.sh - M12 acceptance: wshot --hwnd / --grid / sha256 (T9, v1.1)
# Covers: N24 grid overlay keeps geometry, changes pixels, leaves cell centres alone;
#         N25 --hwnd shoots exactly the window rect; N26 --hwnd/--rect mutex;
#         N27 --grid argument contract; N28 sha256 matches the file; N29 bad hwnd.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 5
PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL %s  [%s]\n' "$1" "$2"; }
skip() { SKIP=$((SKIP+1)); printf 'SKIP %s  [%s]\n' "$1" "$2"; }
TMP="/mnt/c/Users/Public/win-admin/tmp"
mkdir -p "$TMP"
WTMP="C:/Users/Public/win-admin/tmp"
cleanup() { bash tests/helpers/uiawnd-stop.sh >/dev/null 2>&1; }
trap cleanup EXIT

# --- fixture -------------------------------------------------------------
bash tests/helpers/uiawnd-start.sh >/dev/null 2>&1 || { echo "fixture failed to start"; exit 5; }
W="$(jq -r .hwnd_dec /mnt/c/Users/Public/win-admin/tmp/uiawnd.json)"
[ -n "$W" ] && [ "$W" != "null" ] || { echo "no fixture hwnd"; exit 5; }

# git the window rect from wwin (independent source) 
RECT="$(bin/wwin info --hwnd "$W" | jq -c .window.rect)"
WX="$(printf %s "$RECT" | jq -r .x)"; WY="$(printf %s "$RECT" | jq -r .y)"
WW="$(printf %s "$RECT" | jq -r .w)"; WH="$(printf %s "$RECT" | jq -r .h)"

# N25 --hwnd shoots exactly the window rect
J="$(bin/wshot --hwnd "$W" --out "$TMP/m12-hwnd.png" 2>/dev/null)"
if [ "$(printf %s "$J" | jq -r .ok)" = "true" ] \
   && [ "$(printf %s "$J" | jq -r .w)" = "$WW" ] && [ "$(printf %s "$J" | jq -r .h)" = "$WH" ] \
   && [ "$(printf %s "$J" | jq -r .x)" = "$WX" ] && [ "$(printf %s "$J" | jq -r .y)" = "$WY" ]; then
  ok "N25 --hwnd geometry matches window rect ${WW}x${WH}"
else
  bad "N25 --hwnd geometry" "$(printf %s "$J" | jq -c "{x,y,w,h}") expected $RECT"
fi
if [ "$(printf %s "$J" | jq -r .hwnd)" = "$(printf "0x%x" "$W")" ]; then ok "N25b json hwnd hex echoed"; else bad "N25b json hwnd" "$(printf %s "$J" | jq -r .hwnd)"; fi

# N28 sha256 field == real file hash
J2="$(bin/wshot --rect 0,0,320,240 --out "$TMP/m12-sha.png" 2>/dev/null)"
SHA_FIELD="$(printf %s "$J2" | jq -r .sha256)"
SHA_FILE="$(sha256sum "$TMP/m12-sha.png" | cut -d" " -f1)"
if [ "$SHA_FIELD" = "$SHA_FILE" ] && [ -n "$SHA_FIELD" ]; then ok "N28 sha256 matches file"; else bad "N28 sha256" "$SHA_FIELD != $SHA_FILE"; fi

# N24 grid: same geometry, different pixels, cell centre untouched
bin/wshot --rect 50,50,400,300 --out "$TMP/m12-plain.png" >/dev/null 2>&1
bin/wshot --rect 50,50,400,300 --grid 100 --out "$TMP/m12-grid.png" >/dev/null 2>&1
CMP="$(winps -r -t 60 -f /root/win-admin/tests/helpers/imgcmp.ps1 -A "$WTMP/m12-plain.png" -B "$WTMP/m12-grid.png" -Pixels "100,100;50,200" | tail -1)"
if [ "$(printf %s "$CMP" | jq -r .same_size)" = "true" ]; then ok "N24a grid keeps geometry 400x300"; else bad "N24a grid geometry" "$(printf %s "$CMP" | jq -c .size_a,.size_b)"; fi
DR="$(printf %s "$CMP" | jq -r .diff_ratio)"
if [ "$(awk -v d="$DR" "BEGIN{print (d>0.01 && d<0.30)?1:0}")" = "1" ]; then ok "N24b grid paints some but not all pixels (diff_ratio=$DR)"; else bad "N24b grid diff_ratio" "$DR"; fi
if [ "$(printf %s "$CMP" | jq -r ".samples[0].eq")" = "true" ]; then ok "N24c grid leaves cell centre pixel untouched"; else bad "N24c cell centre" "$(printf %s "$CMP" | jq -c ".samples[0]")"; fi
if [ "$(printf %s "$CMP" | jq -r ".samples[1].eq")" = "false" ]; then ok "N24d grid line pixel differs"; else bad "N24d grid line" "$(printf %s "$CMP" | jq -c ".samples[1]")"; fi

# N26 --hwnd and --rect are mutually exclusive (rc=2, no file written)
bin/wshot --hwnd "$W" --rect 0,0,10,10 >/dev/null 2>&1; RC=$?
if [ "$RC" = "2" ]; then ok "N26 --hwnd + --rect rejected rc=2"; else bad "N26 mutex" "rc=$RC"; fi

# N27 --grid contract
bin/wshot --rect 0,0,10,10 --grid abc >/dev/null 2>&1; RC=$?
if [ "$RC" = "2" ]; then ok "N27a --grid abc rejected rc=2"; else bad "N27a --grid abc" "rc=$RC"; fi
bin/wshot --rect 0,0,10,10 --grid -5 >/dev/null 2>&1; RC=$?
if [ "$RC" = "2" ]; then ok "N27b --grid -5 rejected rc=2"; else bad "N27b --grid -5" "rc=$RC"; fi

# N29 invalid hwnd
J3="$(bin/wshot --hwnd 123456 --out "$TMP/m12-bad.png" 2>/dev/null)"; RC=$?
if [ "$RC" = "3" ] && [ "$(printf %s "$J3" | jq -r .code)" = "ENV_NO_WINDOW" ]; then ok "N29 bad hwnd rc=3 ENV_NO_WINDOW"; else bad "N29 bad hwnd" "rc=$RC $(printf %s "$J3" | jq -c .code)"; fi

printf "\n%s passed, %s failed, %s skipped\n" "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" = "0" ] || exit 1
exit 0
