#!/usr/bin/env bash
# tests/check-m20.sh - M20/T24 acceptance: WSL output paths, read-text (UIA + clipboard fallback),
# the tolerant wwin focus --yes, and "documented flags are implemented flags" (C18, v1.3).
set -uo pipefail
cd "$(dirname "$0")/.."
. "$(pwd)/lib/common.sh"

PASS=0; FAIL=0; SKIP=0
pass() { echo "PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
skip() { echo "SKIP  $1"; SKIP=$((SKIP+1)); }

WIN=/mnt/c/Users/Public/win-admin
G="$STATE_DIR/grant.json"
GBK="$STATE_DIR/grant.json.m20-bak"
JSONF="$WIN/tmp/testwin.json"
UJSONF="$WIN/tmp/uiawnd.json"
OUTT="/tmp/m20-shot-$$.png"
OUTM="$WIN/tmp/m20-mnt-$$.png"

cleanup() {
  bin/winput releaseall --yes >/dev/null 2>&1
  bash tests/helpers/testwin-stop.sh >/dev/null 2>&1
  bash tests/helpers/uiawnd-stop.sh >/dev/null 2>&1
  rm -f "$OUTT" "$OUTM"
  if [ -f "$GBK" ]; then mv -f "$GBK" "$G"; else rm -f "$G"; fi
}
trap cleanup EXIT

[ -f "$G" ] && cp -f "$G" "$GBK"
bash guard/grant.sh issue --minutes 30 --scope shot,uia,input,file:read --note "tests/check-m20.sh 本机验收（路径/read-text）" >/dev/null 2>&1 || true
bash tests/helpers/testwin-stop.sh >/dev/null 2>&1
bash tests/helpers/uiawnd-stop.sh >/dev/null 2>&1
sleep 0.5
TW="$(bash tests/helpers/testwin-start.sh 'wa-m20' 2>/dev/null)"
printf '%s' "$TW" | jq -e '.ok' >/dev/null 2>&1 || { echo "FATAL testwin: $TW"; exit 1; }
T="$(bash tests/helpers/uiawnd-start.sh 2>/dev/null)"
printf '%s' "$T" | jq -e '.ok' >/dev/null 2>&1 || { echo "FATAL uiawnd: $T"; exit 1; }
H="$(jq -r '.hwnd_dec' "$JSONF")"
UH="$(jq -r '.hwnd_dec' "$UJSONF")"
EX="$(jq -r '(.edit.x + .edit.w/2)|floor' "$JSONF")"
EY="$(jq -r '(.edit.y + .edit.h/2)|floor' "$JSONF")"
J() { printf '%s' "$1" | jq -r ".$2" 2>/dev/null; }

focus_edit() {
  bin/wwin focus --hwnd "$H" >/dev/null 2>&1
  bin/winput click "$EX" "$EY" --expect-hwnd "$H" --focus --yes >/dev/null 2>&1
  sleep 0.2
}

# N1 (C18-1) wshot --out to a WSL-only path lands the file and says where
rm -f "$OUTT"
S1="$(bin/wshot --out "$OUTT" --rect 100,100,300,200 2>/dev/null)"; RC1=$?
SHA_WANT="$(sha256sum "$OUTT" 2>/dev/null | awk '{print $1}')"
if [ "$RC1" -eq 0 ] && [ -f "$OUTT" ] && [ "$(J "$S1" mapped)" = "true" ] \
   && [ "$(J "$S1" wsl_path)" = "$OUTT" ] && [ "$(J "$S1" sha256)" = "$SHA_WANT" ] \
   && case "$(J "$S1" path)" in C:/*) true ;; *) false ;; esac; then
  echo "PASS  N1 wshot --out $OUTT -> mapped:true, sha256 matches, path=$(J "$S1" path)"; PASS=$((PASS+1))
else
  echo "FAIL  N1 wshot --out: rc=$RC1 sha_want=$SHA_WANT json=$S1"; FAIL=$((FAIL+1))
fi

# N2 a /mnt/c path needs no mapping: the Windows destination IS the WSL path
rm -f "$OUTM"
S2="$(bin/wshot --out "$OUTM" --rect 100,100,200,120 2>/dev/null)"; RC2=$?
if [ "$RC2" -eq 0 ] && [ -f "$OUTM" ] && [ "$(J "$S2" wsl_path)" = "$OUTM" ] && [ "$(J "$S2" mapped)" = "null" ]; then
  echo "PASS  N2 wshot --out /mnt/c/... -> no remap, file on disk"; PASS=$((PASS+1))
else
  echo "FAIL  N2 wshot --out mnt: rc=$RC2 json=$S2"; FAIL=$((FAIL+1))
fi

# N3 (C18-2) read-text reaches a page body: the fixture's TextPattern is the readable source
R3="$(bin/wuia --hwnd "$UH" --read-text 2>/dev/null)"; RC3=$?
if [ "$RC3" -eq 0 ] && [ "$(J "$R3" ok)" = "true" ] && [ "$(J "$R3" mode)" = "readtext" ] \
   && [ "$(J "$R3" chars)" -gt 0 ] 2>/dev/null; then
  echo "PASS  N3 wuia --read-text -> mode:readtext, chars=$(J "$R3" chars)"; PASS=$((PASS+1))
else
  echo "FAIL  N3 wuia --read-text: rc=$RC3 json=$(printf '%s' "$R3" | head -c 200)"; FAIL=$((FAIL+1))
fi

# N4 ops/read-text prefers UIA (no injection, no grant needed)
R4="$(ops/read-text --hwnd "$UH" 2>/dev/null)"; RC4=$?
if [ "$RC4" -eq 0 ] && [ "$(J "$R4" source)" = "uia" ] && [ "$(J "$R4" chars)" -gt 0 ] 2>/dev/null; then
  echo "PASS  N4 ops/read-text -> source:uia, chars=$(J "$R4" chars)"; PASS=$((PASS+1))
else
  echo "FAIL  N4 ops/read-text uia: rc=$RC4 json=$(printf '%s' "$R4" | head -c 240)"; FAIL=$((FAIL+1))
fi

# N5 --no-fallback refuses to inject when the UIA text is empty
focus_edit
bin/wuia --hwnd "$H" --find-type Edit --set-value "" >/dev/null 2>&1
R5="$(ops/read-text --hwnd "$H" --no-fallback 2>/dev/null)"; RC5=$?
# hwnd is echoed as the caller spelled it (decimal here, 0x... from -N6), so just require one.
if [ "$RC5" -eq 3 ] && [ "$(J "$R5" code)" = "ENV_NO_TEXT" ] && [ -n "$(J "$R5" hwnd)" ]; then
  echo "PASS  N5 --no-fallback on an empty field -> rc=3 ENV_NO_TEXT"; PASS=$((PASS+1))
else
  echo "FAIL  N5 --no-fallback: rc=$RC5 json=$(printf '%s' "$R5" | head -c 240)"; FAIL=$((FAIL+1))
fi

# N6 (C18-2b) forced clipboard fallback copies a field's text and restores the clipboard
focus_edit
bin/wuia --hwnd "$H" --find-type Edit --set-value "" >/dev/null 2>&1
bin/winput type --text 'm20 clip marker 中文' --expect-hwnd "$H" --focus --yes >/dev/null 2>&1
bin/wclip set --text 'sentinel-m20-XY' >/dev/null 2>&1
R6="$(ops/read-text --hwnd "$H" --force-clip 2>/dev/null)"; RC6=$?
CLIP_AFTER="$(bin/wclip get 2>/dev/null | jq -r '.text // ""')"
if [ "$RC6" -eq 0 ] && [ "$(J "$R6" source)" = "clip" ] && [ "$(J "$R6" text)" = "m20 clip marker 中文" ] \
   && [ "$(J "$R6" clipRestored)" = "true" ] && [ "$CLIP_AFTER" = "sentinel-m20-XY" ]; then
  echo "PASS  N6 --force-clip -> source:clip, text copied, clipboard restored"; PASS=$((PASS+1))
else
  echo "FAIL  N6 force-clip: rc=$RC6 clip='$CLIP_AFTER' json=$(printf '%s' "$R6" | head -c 240)"; FAIL=$((FAIL+1))
fi

# N7 (C18-3) wwin focus tolerates the --yes habit and says it ignored it
W7="$(bin/wwin focus --hwnd "$UH" --yes 2>/dev/null)"; RC7=$?
if [ "$RC7" -eq 0 ] && [ "$(J "$W7" ok)" = "true" ] && [ "$(J "$W7" ignoredFlags[0])" = "--yes" ]; then
  echo "PASS  N7 wwin focus --yes -> ok:true, ignoredFlags:[--yes]"; PASS=$((PASS+1))
else
  echo "FAIL  N7 focus --yes: rc=$RC7 json=$(printf '%s' "$W7" | head -c 200)"; FAIL=$((FAIL+1))
fi

# N8 ...but only focus does: other subcommands still reject the flag (rc=2)
bin/wwin info --hwnd "$UH" --yes >/dev/null 2>&1; RC8=$?
if [ "$RC8" -eq 2 ]; then
  echo "PASS  N8 wwin info --yes -> rc=2 (the tolerance is focus-only)"; PASS=$((PASS+1))
else
  echo "FAIL  N8 info --yes: rc=$RC8 (want 2)"; FAIL=$((FAIL+1))
fi

# N9 the clipboard fallback is injection: no grant -> rc=4; the UIA path stays open
cp -f "$G" "$GBK" 2>/dev/null || true
rm -f "$G"
ops/read-text --hwnd "$H" --force-clip >/dev/null 2>&1; N9A=$?
ops/read-text --hwnd "$UH" >/dev/null 2>&1; N9B=$?
mv -f "$GBK" "$G"
if [ "$N9A" -eq 4 ] && [ "$N9B" -eq 0 ]; then
  echo "PASS  N9 no grant -> force-clip rc=4, UIA read rc=0"; PASS=$((PASS+1))
else
  echo "FAIL  N9 guard split: clip rc=$N9A uia rc=$N9B (want 4/0)"; FAIL=$((FAIL+1))
fi

# N10 (C18-4) the new flags are advertised by --help, not just in the changelog
MISS=""
bin/wshot --help 2>&1 | grep -q -- '--out' || MISS="$MISS wshot:--out"
bin/wwin  --help 2>&1 | grep -q -- 'focus --hwnd 0x1234 \[--yes\]' || MISS="$MISS wwin:focus--yes"
bin/wuia --help 2>&1 | grep -q -- '--read-text' || MISS="$MISS wuia:--read-text"
ops/read-text --help 2>&1 | grep -q -- '--force-clip' || MISS="$MISS read-text:--force-clip"
if [ -z "$MISS" ]; then
  echo "PASS  N10 every new flag appears in its own --help"; PASS=$((PASS+1))
else
  echo "FAIL  N10 missing from --help:$MISS"; FAIL=$((FAIL+1))
fi

# N11 live (optional): the user's Edge, if it is open, must yield a long body text
EH="$(bin/wwin list 2>/dev/null | jq -r '.windows[] | select(.title|test("Edge")) | .hwnd' | head -1)"
if [ -n "$EH" ]; then
  R11="$(bin/wuia --hwnd "$EH" --read-text 2>/dev/null)"
  if [ "$(J "$R11" ok)" = "true" ] && [ "$(J "$R11" chars)" -gt 50 ] 2>/dev/null; then
    echo "PASS  N11 live Edge $EH -> readtext chars=$(J "$R11" chars)"; PASS=$((PASS+1))
  else
    echo "FAIL  N11 live Edge: $(printf '%s' "$R11" | head -c 200)"; FAIL=$((FAIL+1))
  fi
else
  echo "SKIP  N11 live Edge (no Edge window)"; SKIP=$((SKIP+1))
fi

echo
echo "$PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
