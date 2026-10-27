#!/usr/bin/env bash
# tests/check-m22.sh - M22/T28 acceptance: scroll container + scroll state (F19-1..4, v1.4).
#   F19-1 find-aid opt-28  -> via:'scroll-pattern', container wa-sv, numeric percentY
#   F19-1 point probe      -> same container found from a point on a visible option
#   F19-2 title label      -> scrollable:false, container:null, rc=0 (not an error)
#   F19-3 point off-window -> rc=3 ENV_NO_HIT (a foreign app is not an answer)
#   F19-4 clipped text     -> via:'rect', the clipping GroupBox, scroll:null (no fake percentages)
# Plus code guards: ARG_NEED_FIND (rc2), ENV_NO_MATCH (rc3).
set -uo pipefail
cd "$(dirname "$0")/.."
. "$(pwd)/lib/common.sh"

PASS=0; FAIL=0
pass() { echo "PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
num() { printf '%s' "$1" | jq -r ".$2" 2>/dev/null; }

WIN=/mnt/c/Users/Public/win-admin
G="$STATE_DIR/grant.json"
GBK="$STATE_DIR/grant.json.m22-bak"
JSONF="$WIN/tmp/scrollwin.json"

cleanup() {
  bash tests/helpers/scrollwin-stop.sh >/dev/null 2>&1
  if [ -f "$GBK" ]; then mv -f "$GBK" "$G"; else rm -f "$G"; fi
}
trap cleanup EXIT

[ -f "$G" ] && cp -f "$G" "$GBK"
bash guard/grant.sh issue --minutes 30 --scope shot,uia,input,file:read --note "tests/check-m22.sh 本机验收（scroll-info）" >/dev/null 2>&1 || true
bash tests/helpers/scrollwin-stop.sh >/dev/null 2>&1
sleep 0.5
S="$(bash tests/helpers/scrollwin-start.sh 2>/dev/null)"
if ! printf '%s' "$S" | jq -e '.ok' >/dev/null 2>&1; then echo "FATAL: $S"; exit 1; fi
H="$(jq -r '.hwnd_dec' "$JSONF")"
echo "INFO  fixture: hwnd=$H pid=$(jq -r '.pid' "$JSONF")"

# F19-1 via find: the last option is far below the viewport, the container is still wa-sv.
A="$(bin/wuia --hwnd "$H" --find-aid '^opt-28$' --scroll-info 2>/dev/null)"; RC=$?
if [ "$RC" -eq 0 ] &&
   [ "$(num "$A" ok)" = "true" ] &&
   [ "$(num "$A" via)" = "scroll-pattern" ] &&
   [ "$(num "$A" scrollable)" = "true" ] &&
   [ "$(num "$A" container.aid)" = "wa-sv" ] &&
   [ "$(num "$A" container.scroll.verticallyScrollable)" = "true" ] &&
   [ "$(num "$A" container.scroll.percentY | grep -cE '^[0-9]+(\.[0-9]+)?$')" = "1" ]; then
  echo "PASS  F19-1 find: via=$(num "$A" via) container=$(num "$A" container.aid) percentY=$(num "$A" container.scroll.percentY) viewHeight=$(num "$A" container.scroll.viewHeight)"; PASS=$((PASS+1))
else
  echo "FAIL  F19-1 find: rc=$RC $(printf '%s' "$A" | head -c 300)"; FAIL=$((FAIL+1))
fi

# F19-1 via point: centre of the first (visible) option.
OX="$(jq -r '.rects.opt01.x' "$JSONF")"; OY="$(jq -r '.rects.opt01.y' "$JSONF")"
OW="$(jq -r '.rects.opt01.w' "$JSONF")"; OH="$(jq -r '.rects.opt01.h' "$JSONF")"
PX=$(( OX + OW / 2 )); PY=$(( OY + OH / 2 ))
bin/wwin focus --hwnd "$H" >/dev/null 2>&1
B="$(bin/wuia --hwnd "$H" --point "$PX,$PY" --scroll-info 2>/dev/null)"; RC=$?
if [ "$RC" -eq 0 ] &&
   [ "$(num "$B" ok)" = "true" ] &&
   [ "$(num "$B" via)" = "scroll-pattern" ] &&
   [ "$(num "$B" container.aid)" = "wa-sv" ] &&
   [ "$(num "$B" point.x)" = "$PX" ]; then
  echo "PASS  F19-1 point $PX,$PY: element=$(num "$B" element.name) container=$(num "$B" container.aid)"; PASS=$((PASS+1))
else
  echo "FAIL  F19-1 point $PX,$PY: rc=$RC $(printf '%s' "$B" | head -c 300)"; FAIL=$((FAIL+1))
fi

# F19-2 a plain label outside any scroll container is a valid negative answer.
C="$(bin/wuia --hwnd "$H" --find-name '^SCROLL-TITLE$' --scroll-info 2>/dev/null)"; RC=$?
if [ "$RC" -eq 0 ] && [ "$(num "$C" ok)" = "true" ] && [ "$(num "$C" scrollable)" = "false" ] && [ "$(num "$C" container)" = "null" ] && [ "$(num "$C" via)" = "none" ]; then
  echo "PASS  F19-2 label: scrollable=false container=null via=none rc=0"; PASS=$((PASS+1))
else
  echo "FAIL  F19-2 label: rc=$RC $(printf '%s' "$C" | head -c 300)"; FAIL=$((FAIL+1))
fi

# F19-3 a point outside the target window must not resolve to another app's element.
D="$(bin/wuia --hwnd "$H" --point 5,5 --scroll-info 2>/dev/null)"; RC=$?
if [ "$RC" -eq 3 ] && [ "$(num "$D" code)" = "ENV_NO_HIT" ]; then
  echo "PASS  F19-3 off-window point: rc=3 ENV_NO_HIT"; PASS=$((PASS+1))
else
  echo "FAIL  F19-3 off-window point: rc=$RC $(printf '%s' "$D" | head -c 300)"; FAIL=$((FAIL+1))
fi

# F19-4 the clipping ancestor has no ScrollPattern: say so, hand out its rect, no percentages.
E="$(bin/wuia --hwnd "$H" --find-name '^CLIPPED-TEXT$' --scroll-info 2>/dev/null)"; RC=$?
if [ "$RC" -eq 0 ] &&
   [ "$(num "$E" ok)" = "true" ] &&
   [ "$(num "$E" via)" = "rect" ] &&
   [ "$(num "$E" scrollable)" = "false" ] &&
   [ "$(num "$E" container.aid)" = "wa-clip" ] &&
   [ "$(num "$E" container.scroll)" = "null" ]; then
  echo "PASS  F19-4 clipped: via=rect container=$(num "$E" container.aid) scroll=null"; PASS=$((PASS+1))
else
  echo "FAIL  F19-4 clipped: rc=$RC $(printf '%s' "$E" | head -c 300)"; FAIL=$((FAIL+1))
fi

# Guard: neither point nor find is an argument error, not an empty scan.
F="$(bin/wuia --hwnd "$H" --scroll-info 2>/dev/null)"; RC=$?
if [ "$RC" -eq 2 ] && [ "$(num "$F" code)" = "ARG_NEED_FIND" ]; then
  echo "PASS  guard ARG_NEED_FIND rc=2"; PASS=$((PASS+1))
else
  echo "FAIL  guard ARG_NEED_FIND: rc=$RC $(printf '%s' "$F" | head -c 200)"; FAIL=$((FAIL+1))
fi

# Guard: an unmatched find is ENV_NO_MATCH, not ok:true with an empty chain.
Hh="$(bin/wuia --hwnd "$H" --find-aid '^no-such-element$' --scroll-info 2>/dev/null)"; RC=$?
if [ "$RC" -eq 3 ] && [ "$(num "$Hh" code)" = "ENV_NO_MATCH" ]; then
  echo "PASS  guard ENV_NO_MATCH rc=3"; PASS=$((PASS+1))
else
  echo "FAIL  guard ENV_NO_MATCH: rc=$RC $(printf '%s' "$Hh" | head -c 200)"; FAIL=$((FAIL+1))
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
