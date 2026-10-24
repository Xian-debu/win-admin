#!/usr/bin/env bash
# tests/check-m14.sh - M14 acceptance: input closure (T14, v1.2)
# Covers: N1 --text-file accepts a WSL path and lands byte-identically; N2 --verify exact;
#         N3 --verify contains; N4 verify on a non-editable focus fails rc=3 ENV_TEXT_NOT_ENTERED;
#         N5 missing file is ARG_TEXT_FILE_NOT_FOUND (distinct from empty); N6 empty file is
#         ARG_EMPTY_TEXT; N7 bad --verify mode; N8 --verify on a non-type action; N9 wclip
#         --native-path writes a backslash path; N10 a Windows path is still accepted;
#         N11 --native-path cannot be mixed with --text/--text-file.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 5
. "$(pwd)/lib/common.sh"
PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL %s  [%s]\n' "$1" "$2"; }
TMP="/mnt/c/Users/Public/win-admin/tmp"
WTMP="C:/Users/Public/win-admin/tmp"
EV="$TMP/uiawnd-events.txt"
G="$STATE_DIR/grant.json"; GBK="$G.m14-bak"
cleanup() {
  bash tests/helpers/uiawnd-stop.sh >/dev/null 2>&1
  rm -f /tmp/m14-*.txt "$TMP/m14-win.txt" "$TMP/m14-empty.txt"
  if [ -f "$GBK" ]; then mv -f "$GBK" "$G"; else rm -f "$G"; fi
}
trap cleanup EXIT
if [ -f "$G" ]; then cp "$G" "$GBK"; fi
bash guard/grant.sh issue --minutes 30 --scope shot,uia,input,file:read --note 'tests/check-m14.sh 本机验收（输入闭环）' >/dev/null 2>&1 || true
mkdir -p "$TMP"
bash tests/helpers/uiawnd-start.sh >/dev/null 2>&1 || { echo 'fixture failed'; exit 5; }
W="$(jq -r .hwnd_dec /mnt/c/Users/Public/win-admin/tmp/uiawnd.json)"
[ -n "$W" ] && [ "$W" != null ] || { echo 'no fixture hwnd'; exit 5; }

TXT="m14 WSL \\ 路径 'q' \"dq\" 100% ;|&"
printf '%s' "$TXT" > /tmp/m14-wsl.txt

# N1: WSL path + --verify exact lands the text
ops/click-element --hwnd "$W" --aid wa-edit --yes >/dev/null 2>&1
J="$(bin/winput type --text-file /tmp/m14-wsl.txt --verify exact --yes 2>&1)"; RC=$?
LAST="$(tail -1 "$EV" 2>/dev/null)"
if [ "$RC" -eq 0 ] && [ "$(printf %s "$J" | jq -r .ok)" = true ] && [ "$LAST" = "value $TXT" ]; then
  ok 'N1 --text-file accepts a WSL path and lands the exact text'
else
  bad 'N1 wsl text-file' "rc=$RC json=$(printf %s "$J" | jq -c '{ok,code,chars}' 2>/dev/null) last=$LAST"
fi
if [ "$(printf %s "$J" | jq -r '.verify.via')" = value ] && [ "$(printf %s "$J" | jq -r '.verify.matched')" = true ]; then
  ok 'N2 --verify exact reads the focused element back (via value)'
else
  bad 'N2 verify exact' "$(printf %s "$J" | jq -c '.verify' 2>/dev/null)"
fi

CJ="$(bin/winput type --text-file /tmp/m14-wsl.txt --verify contains --yes 2>&1)"
if [ "$(printf %s "$CJ" | jq -r .ok)" = true ] && [ "$(printf %s "$CJ" | jq -r '.verify.mode')" = contains ] && [ "$(printf %s "$CJ" | jq -r '.verify.matched')" = true ]; then
  ok 'N3 --verify contains accepts a matching readback'
else
  bad 'N3 verify contains' "$(printf %s "$CJ" | jq -c '.verify' 2>/dev/null)"
fi

# N4: verify against a focus that cannot receive text (a button)
ops/click-element --hwnd "$W" --name '^BTN-COUNT$' --strategy click --yes >/dev/null 2>&1
MJ="$(bin/winput type --text 'm14-not-landed' --verify exact --yes 2>&1)"; MRC=$?
if [ "$MRC" -eq 3 ] && [ "$(printf %s "$MJ" | jq -r .code)" = ENV_TEXT_NOT_ENTERED ] && [ "$(printf %s "$MJ" | jq -r '.verify.available')" = true ]; then
  ok 'N4 verify mismatch is rc=3 ENV_TEXT_NOT_ENTERED with a readback attached'
else
  bad 'N4 verify mismatch' "rc=$MRC $(printf %s "$MJ" | jq -c '{ok,code,verify}' 2>/dev/null)"
fi

# N5/N6: missing vs empty are different codes
NJ="$(bin/winput type --text-file /tmp/m14-does-not-exist.txt --yes 2>&1)"; NRC=$?
if [ "$NRC" -eq 2 ] && printf %s "$NJ" | grep -q ARG_TEXT_FILE_NOT_FOUND; then
  ok 'N5 missing text file is rc=2 ARG_TEXT_FILE_NOT_FOUND'
else
  bad 'N5 missing text file' "rc=$NRC $NJ"
fi
: > /tmp/m14-empty.txt
EJ="$(bin/winput type --text-file /tmp/m14-empty.txt --yes 2>&1)"; ERC=$?
if [ "$ERC" -eq 2 ] && printf %s "$EJ" | grep -q ARG_EMPTY_TEXT; then
  ok 'N6 empty text file is rc=2 ARG_EMPTY_TEXT (distinct from missing)'
else
  bad 'N6 empty text file' "rc=$ERC $EJ"
fi

bin/winput type --text x --verify bogus --yes >/dev/null 2>&1; RC7=$?
bin/winput click 10 10 --expect-hwnd "$W" --verify exact --dry-run >/dev/null 2>&1; RC8=$?
if [ "$RC7" -eq 2 ] && [ "$RC8" -eq 2 ]; then
  ok 'N7/N8 bad --verify mode and --verify on a non-type action are rc=2'
else
  bad 'N7/N8 verify contract' "mode=$RC7 action=$RC8"
fi

# N9/N10/N11: wclip native path
bin/wclip set --native-path /mnt/c/Users/Public/win-admin/tmp/m14.srt >/dev/null 2>&1
NT="$(bin/wclip get 2>/dev/null | jq -r .text)"
if [ "$NT" = 'C:\Users\Public\win-admin\tmp\m14.srt' ]; then
  ok 'N9 wclip --native-path converts /mnt/c + forward slashes to a native path'
else
  bad 'N9 native path' "got=$NT"
fi
printf '%s' 'm14 windows path' > "$TMP/m14-win.txt"
WJ="$(bin/winput type --text-file "$WTMP/m14-win.txt" --yes 2>&1)"
if [ "$(printf %s "$WJ" | jq -r .ok)" = true ]; then
  ok 'N10 a Windows-style --text-file path still works'
else
  bad 'N10 windows text-file' "$(printf %s "$WJ" | jq -c '{ok,code}' 2>/dev/null)"
fi
bin/wclip set --text x --native-path y >/dev/null 2>&1; RC11=$?
if [ "$RC11" -eq 2 ]; then
  ok 'N11 --native-path cannot be mixed with --text/--text-file (rc=2)'
else
  bad 'N11 native mutex' "rc=$RC11"
fi

printf '\n%s passed, %s failed, %s skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" = 0 ] || exit 1
exit 0