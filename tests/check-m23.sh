#!/usr/bin/env bash
# tests/check-m23.sh - M23/T29 acceptance: ops/reveal + winput click --reveal (F20-1..7, v1.4).
#   F20-1 pattern down  -> steps>=1, moved:["pattern"], element rect inside container, point hits it
#   F20-2 idempotent    -> steps:0, moved:[], scroll unchanged (already visible = no injection)
#   F20-3 no match      -> rc=3 ENV_NO_MATCH, steps:0
#   F20-4 cannot move   -> rc=3 ENV_SCROLL_NOT_MOVED (via:'rect', no scroll pattern), hoverTried:true
#   F20-5 steps used up -> rc=3 ENV_NOT_REVEALED with steps and history
#   F20-6 dry-run       -> rc=0, dryRun:true, plannedSteps, no "revealed", percent unchanged
#   F20-7 reveal click    -> winput click --reveal scrolls, clicks, title changes, JSON carries reveal
set -uo pipefail
cd "$(dirname "$0")/.."
. "$(pwd)/lib/common.sh"

PASS=0; FAIL=0
num() { printf '%s' "$1" | jq -r ".$2" 2>/dev/null; }
ok() { echo "PASS  $1"; PASS=$((PASS+1)); }
no() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }

WIN=/mnt/c/Users/Public/win-admin
G="$STATE_DIR/grant.json"
GBK="$STATE_DIR/grant.json.m23-bak"
JSONF="$WIN/tmp/scrollwin.json"

cleanup() {
  bash tests/helpers/scrollwin-stop.sh >/dev/null 2>&1
  if [ -f "$GBK" ]; then mv -f "$GBK" "$G"; else rm -f "$G"; fi
}
trap cleanup EXIT

[ -f "$G" ] && cp -f "$G" "$GBK"
bash guard/grant.sh issue --minutes 30 --scope shot,uia,input,file:read --note "tests/check-m23.sh 本机验收（reveal）" >/dev/null 2>&1 || true
bash tests/helpers/scrollwin-stop.sh >/dev/null 2>&1
sleep 0.5
S="$(bash tests/helpers/scrollwin-start.sh 2>/dev/null)"
if ! printf '%s' "$S" | jq -e '.ok' >/dev/null 2>&1; then echo "FATAL: $S"; exit 1; fi
H="$(jq -r '.hwnd_dec' "$JSONF")"
echo "INFO  fixture: hwnd=$H pid=$(jq -r '.pid' "$JSONF")"
bin/wwin focus --hwnd "$H" >/dev/null 2>&1

pct() { bin/wuia --hwnd "$H" --scroll-info --find-aid '^opt-28$' 2>/dev/null | jq -r '.container.scroll.percentY // "null"'; }
P0="$(pct)"
echo "INFO  start percentY=$P0"

# --- F20-6 dry-run first: it must not inject, so the start percentage stays put.
D="$(bash ops/reveal --hwnd "$H" --find-aid '^opt-28$' --dry-run 2>/dev/null)"; RC=$?
P1="$(pct)"
if [ "$RC" -eq 0 ] && [ "$(num "$D" ok)" = "true" ] && [ "$(num "$D" dryRun)" = "true" ] &&
   [ "$(num "$D" plannedSteps)" != "null" ] && [ "$(num "$D" revealed)" = "null" ] &&
   [ "$P0" = "$P1" ]; then
  ok "F20-6 dry-run: rc=0 dryRun=true plannedSteps=$(num "$D" plannedSteps) via=$(num "$D" via) percent $P0 -> $P1"
else
  no "F20-6 dry-run: rc=$RC plannedSteps=$(num "$D" plannedSteps) revealed=$(num "$D" revealed) percent $P0 -> $P1 :: $(printf '%s' "$D" | head -c 300)"
fi

# --- F20-4 a clipped label has a container by geometry but nothing to scroll: the wheel never moves it.
C="$(bash ops/reveal --hwnd "$H" --find-name '^CLIPPED-TEXT$' --strategy wheel --yes 2>/dev/null)"; RC=$?
if [ "$RC" -eq 3 ] && [ "$(num "$C" code)" = "ENV_SCROLL_NOT_MOVED" ] &&
   [ "$(num "$C" hoverTried)" = "true" ] && [ "$(num "$C" history[0].before)" = "null" ]; then
  ok "F20-4 not moved: rc=3 ENV_SCROLL_NOT_MOVED hoverTried=true via=$(num "$C" via)"
else
  no "F20-4 not moved: rc=$RC code=$(num "$C" code) :: $(printf '%s' "$C" | head -c 300)"
fi

# --- F20-5 a single wheel notch cannot cross 28 options: the tool reports what it tried.
E="$(bash ops/reveal --hwnd "$H" --find-aid '^opt-28$' --strategy wheel --steps 1 --yes 2>/dev/null)"; RC=$?
NH="$(printf '%s' "$E" | jq -r '.history | length' 2>/dev/null)"
if [ "$RC" -eq 3 ] && [ "$(num "$E" code)" = "ENV_NOT_REVEALED" ] &&
   [ "$(num "$E" steps)" = "1" ] && [ "$NH" = "1" ] &&
   [ "$(num "$E" history[0].action)" = "wheel" ]; then
  ok "F20-5 steps used up: rc=3 ENV_NOT_REVEALED steps=1 history[0]=$(num "$E" history[0].action) $(num "$E" history[0].before) -> $(num "$E" history[0].after)"
else
  no "F20-5 steps used up: rc=$RC code=$(num "$E" code) steps=$(num "$E" steps) history=$NH :: $(printf '%s' "$E" | head -c 300)"
fi

# --- F20-1 the pattern fast path: one SetScrollPercent takes opt-28 into the viewport.
A="$(bash ops/reveal --hwnd "$H" --find-aid '^opt-28$' --yes 2>/dev/null)"; RC=$?
EX="$(num "$A" element.rect.x)"; EY="$(num "$A" element.rect.y)"
EW="$(num "$A" element.rect.w)"; EH="$(num "$A" element.rect.h)"
CX="$(num "$A" container.rect.x)"; CY="$(num "$A" container.rect.y)"
CW="$(num "$A" container.rect.w)"; CH="$(num "$A" container.rect.h)"
INSIDE=0
if [ "$EX" -ge "$((CX-2))" ] && [ "$EY" -ge "$((CY-2))" ] &&
   [ "$((EX+EW))" -le "$((CX+CW+2))" ] && [ "$((EY+EH))" -le "$((CY+CH+2))" ]; then INSIDE=1; fi
if [ "$RC" -eq 0 ] && [ "$(num "$A" revealed)" = "true" ] && [ "$(num "$A" steps)" -ge 1 ] &&
   [ "$(printf '%s' "$A" | jq -r '.moved | index("pattern") != null')" = "true" ] &&
   [ "$(num "$A" via)" = "scroll-pattern" ] && [ "$INSIDE" -eq 1 ] &&
   [ "$(num "$A" hit.name)" = "OPT-28" ]; then
  ok "F20-1 pattern down: steps=$(num "$A" steps) moved=$(printf '%s' "$A" | jq -c '.moved') scroll=$(num "$A" scroll.before)->$(num "$A" scroll.after) point=$(num "$A" point.x),$(num "$A" point.y) inside=yes"
else
  no "F20-1 pattern down: rc=$RC revealed=$(num "$A" revealed) via=$(num "$A" via) inside=$INSIDE :: $(printf '%s' "$A" | head -c 400)"
fi

# --- F20-2 already visible: zero steps, nothing injected.
B="$(bash ops/reveal --hwnd "$H" --find-aid '^opt-28$' --yes 2>/dev/null)"; RC=$?
if [ "$RC" -eq 0 ] && [ "$(num "$B" revealed)" = "true" ] && [ "$(num "$B" steps)" = "0" ] &&
   [ "$(num "$B" moved | jq -c 'length')" = "0" ]; then
  ok "F20-2 idempotent: steps=0 moved=$(printf '%s' "$B" | jq -c '.moved') scroll=$(num "$B" scroll.before)->$(num "$B" scroll.after)"
else
  no "F20-2 idempotent: rc=$RC steps=$(num "$B" steps) :: $(printf '%s' "$B" | head -c 300)"
fi

# --- F20-3 no such element: a clear miss, not an empty success.
M="$(bash ops/reveal --hwnd "$H" --find-aid '^no-such-element$' 2>/dev/null)"; RC=$?
if [ "$RC" -eq 3 ] && [ "$(num "$M" code)" = "ENV_NO_MATCH" ] && [ "$(num "$M" steps)" = "0" ]; then
  ok "F20-3 no match: rc=3 ENV_NO_MATCH steps=0"
else
  no "F20-3 no match: rc=$RC code=$(num "$M" code) :: $(printf '%s' "$M" | head -c 300)"
fi

# --- F20-7 winput click --reveal: reveal (from 100% back to the top), click, prove the title changed.
W="$(bin/winput click --reveal --reveal-aid '^opt-02$' --expect-hwnd "$H" --yes --expect-change title 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && [ "$(num "$W" ok)" = "true" ] && [ "$(num "$W" changed)" = "true" ] &&
   [ "$(num "$W" reveal.revealed)" = "true" ] && [ "$(num "$W" reveal.element.aid)" = "opt-02" ] &&
   [ "$(num "$W" after.title)" = "opt:OPT-02" ] && [ "$(num "$W" hit.name)" = "OPT-02" ]; then
  ok "F20-7 reveal click: steps=$(num "$W" reveal.steps) $(num "$W" reveal.scroll.before)->$(num "$W" reveal.scroll.after) title=$(num "$W" after.title)"
else
  no "F20-7 reveal click: rc=$RC ok=$(num "$W" ok) changed=$(num "$W" changed) title=$(num "$W" after.title) :: $(printf '%s' "$W" | head -c 400)"
fi

# --- F20-7 argument guards: click-only, no X Y, needs --expect-hwnd and a criterion.
bin/winput click --reveal 12,34 --reveal-aid '^opt-02$' --expect-hwnd "$H" >/dev/null 2>&1; RC1=$?
bin/winput click --reveal --expect-hwnd "$H" >/dev/null 2>&1; RC2=$?
if [ "$RC1" -eq 2 ] && [ "$RC2" -eq 2 ]; then
  ok "F20-7 guards: X Y together with --reveal rc=2, no criterion rc=2"
else
  no "F20-7 guards: X Y rc=$RC1 no-criterion rc=$RC2"
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
