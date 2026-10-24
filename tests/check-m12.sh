#!/usr/bin/env bash
# tests/check-m12.sh - M12 acceptance: wshot --hwnd / --grid / sha256 (T9) + --box/--clip/rect contract (T15, v1.2)
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


# --- T15 (v1.2): --box / --clip / rect contract ---------------------------
# N30 --box converts a left-top/right-bottom pair to X,Y,W,H
JB="$(bin/wshot --box 100,100,500,400 --out "$TMP/m12-box.png" 2>/dev/null)"
if [ "$(printf %s "$JB" | jq -r '.ok')" = "true" ] && [ "$(printf %s "$JB" | jq -r '.x')" = "100" ] \
   && [ "$(printf %s "$JB" | jq -r '.y')" = "100" ] && [ "$(printf %s "$JB" | jq -r '.w')" = "400" ] \
   && [ "$(printf %s "$JB" | jq -r '.h')" = "300" ]; then
  ok "N30 --box 100,100,500,400 -> x100 y100 400x300"
else
  bad "N30 --box conversion" "$(printf %s "$JB" | jq -c '{x,y,w,h,code,msg}')"
fi
# N31 the new JSON fields agree with each other and with the PNG
if [ "$(printf %s "$JB" | jq -r '.rect.w')" = "400" ] && [ "$(printf %s "$JB" | jq -r '.rect.h')" = "300" ] \
   && [ "$(printf %s "$JB" | jq -r '.image.w')" = "400" ] && [ "$(printf %s "$JB" | jq -r '.image.h')" = "300" ] \
   && [ "$(printf %s "$JB" | jq -r '.clipped')" = "false" ]; then
  ok "N31 json rect/image agree and clipped=false"
else
  bad "N31 json fields" "$(printf %s "$JB" | jq -c '{rect,image,clipped}')"
fi
# N32 scale is dpi/96 (the number a caller must divide preview coordinates by)
SC="$(printf %s "$JB" | jq -r '.scale')"
if [ "$(awk -v s="$SC" 'BEGIN{print (s>1.0 && s<3.0)?1:0}')" = "1" ]; then ok "N32 scale reported ($SC)"; else bad "N32 scale" "$SC"; fi
# N33 off-screen without --clip: rc=2 and the message teaches both ways out
OUT33="$(bin/wshot --rect 2400,1500,400,300 --out "$TMP/m12-oob.png" 2>&1)"; RC=$?
case "$OUT33" in *ARG_OUT_OF_SCREEN*--clip*--box*) M33=1 ;; *) M33=0 ;; esac
if [ "$RC" = "2" ] && [ "$M33" = "1" ]; then ok "N33 off-screen rc=2 with --clip/--box hint"; else bad "N33 off-screen msg" "rc=$RC $OUT33"; fi
# N34 --clip trims to the screen edge and says so
JC="$(bin/wshot --rect 2400,1500,400,300 --clip --out "$TMP/m12-clip.png" 2>/dev/null)"
if [ "$(printf %s "$JC" | jq -r '.ok')" = "true" ] && [ "$(printf %s "$JC" | jq -r '.w')" = "160" ] \
   && [ "$(printf %s "$JC" | jq -r '.h')" = "100" ] && [ "$(printf %s "$JC" | jq -r '.clipped')" = "true" ] \
   && [ "$(printf %s "$JC" | jq -r '.requested.w')" = "400" ]; then
  ok "N34 --clip trims 400x300 at 2400,1500 to 160x100, requested echoed"
else
  bad "N34 --clip trim" "$(printf %s "$JC" | jq -c '{x,y,w,h,clipped,requested,code}')"
fi
# N35 --clip with no intersection at all still fails
bin/wshot --rect 3000,2000,100,100 --clip >/dev/null 2>&1; RC=$?
if [ "$RC" = "2" ]; then ok "N35 --clip fully off-screen rc=2"; else bad "N35 clip no-intersection" "rc=$RC"; fi
# N36 space-separated coordinates: ARG_BAD_RECT, not a bare "unknown arg"
OUT36="$(bin/wshot --rect 800 460 1900 140 2>&1)"; RC=$?
case "$OUT36" in *ARG_BAD_RECT*comma-separated*) M36=1 ;; *) M36=0 ;; esac
if [ "$RC" = "2" ] && [ "$M36" = "1" ]; then ok "N36 space-separated --rect rc=2 ARG_BAD_RECT"; else bad "N36 space-separated" "rc=$RC $OUT36"; fi
# N37 --box needs X2>X1 and Y2>Y1
bin/wshot --box 500,400,100,100 >/dev/null 2>&1; RC=$?
if [ "$RC" = "2" ]; then ok "N37 inverted --box rc=2"; else bad "N37 inverted box" "rc=$RC"; fi
# N38 --rect and --box are mutually exclusive
bin/wshot --rect 0,0,10,10 --box 0,0,10,10 >/dev/null 2>&1; RC=$?
if [ "$RC" = "2" ]; then ok "N38 --rect + --box rejected rc=2"; else bad "N38 rect/box mutex" "rc=$RC"; fi
printf "\n%s passed, %s failed, %s skipped\n" "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" = "0" ] || exit 1
exit 0
