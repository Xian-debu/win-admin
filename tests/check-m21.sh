#!/usr/bin/env bash
# tests/check-m21.sh - M21/T25 acceptance: live read-only smoke against a real browser (C19, v1.3).
# Optional by design (docs/22 §2 T25): no browser window -> SKIP, never FAIL, no network needed
# (it only reads the page that is already open). It never clicks, switches tabs or injects input.
set -uo pipefail
cd "$(dirname "$0")/.."
. "$(pwd)/lib/common.sh"

PASS=0; FAIL=0; SKIP=0
pass() { echo "PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
skip() { echo "SKIP  $1"; SKIP=$((SKIP+1)); }
J() { printf '%s' "$1" | jq -r ".$2" 2>/dev/null; }

# No fixture, no grant: every call below is read-only UIA.
EH="$(bin/wwin list 2>/dev/null | jq -r '.windows[] | select(.class|test("Chrome_WidgetWin"; "i")) | select(.rect.w > 200) | .hwnd' | head -1)"
if [ -z "$EH" ]; then
  EH="$(bin/wwin list 2>/dev/null | jq -r '.windows[] | select(.title|test("Edge|Chrome"; "i")) | .hwnd' | head -1)"
fi
if [ -z "$EH" ]; then
  echo "SKIP  M21 live smoke: no Edge/Chrome window open"
  echo
  echo "0 passed, 0 failed, 1 skipped"
  exit 0
fi
TITLE="$(bin/wwin list 2>/dev/null | jq -r --arg h "$EH" '.windows[] | select(.hwnd==$h) | .title')"
echo "INFO  live target: $EH  $TITLE"

# N1 the a11y tree is reachable at all: text lines with real geometry
T0="$(date +%s%3N)"
L1="$(bin/wuia --hwnd "$EH" --find-text '.' --limit 120 2>/dev/null)"; RC1=$?
M1=$(( $(date +%s%3N) - T0 ))
C1="$(J "$L1" total)"
R1="$(printf '%s' "$L1" | jq -r '[.lines[]? | select(.rect.w>0 and .rect.h>0)] | length' 2>/dev/null)"
D1="$(printf '%s' "$L1" | jq -r '[.lines[]? | select(.depth>=8)] | length' 2>/dev/null)"
if [ "$RC1" -eq 0 ] && [ "$(J "$L1" ok)" = "true" ] && [ "${C1:-0}" -ge 20 ] 2>/dev/null && [ "${R1:-0}" -ge 3 ] 2>/dev/null && [ "${D1:-0}" -ge 3 ] 2>/dev/null; then
  echo "PASS  N1 --find-text '.' -> total=$C1 (geometry: $R1, depth>=8: $D1) in ${M1}ms"; PASS=$((PASS+1))
else
  echo "FAIL  N1 find-text live: rc=$RC1 $(printf '%s' "$L1" | head -c 240)"; FAIL=$((FAIL+1))
fi

# N2 the address/search bar is visible to find-type (a Chromium-specific shape)
L2="$(bin/wuia --hwnd "$EH" --find-type ControlType.Edit 2>/dev/null)"; RC2=$?
N2="$(J "$L2" total)"
if [ "$RC2" -eq 0 ] && [ "$(J "$L2" ok)" = "true" ] && [ "${N2:-0}" -ge 1 ] 2>/dev/null; then
  echo "PASS  N2 --find-type Edit -> total=$N2 (first: $(printf '%s' "$L2" | jq -c '.elements[0].name // .elements[0].type' 2>/dev/null))"; PASS=$((PASS+1))
else
  echo "FAIL  N2 find-type live: rc=$RC2 $(printf '%s' "$L2" | head -c 240)"; FAIL=$((FAIL+1))
fi

# N3 geometry hit-test lands inside the page: take one real text row and probe its centre
# page body only: skip the browser toolbar band (y < 150) and keep rows deep in the a11y tree
ROW="$(printf '%s' "$L1" | jq -c '[.lines[]? | select(.rect.w>0 and .rect.y > 150 and .rect.y < 1450 and .depth >= 8)] | .[0] // empty' 2>/dev/null)"
if [ -n "$ROW" ]; then
  PX="$(printf '%s' "$ROW" | jq -r '(.rect.x + .rect.w/2)|floor')"
  PY="$(printf '%s' "$ROW" | jq -r '(.rect.y + .rect.h/2)|floor')"
  P="$(bin/wuia --hwnd "$EH" --point "$PX,$PY" 2>/dev/null)"; RC3=$?
  VIA="$(J "$P" via)"
  CONTAINS="$(printf '%s' "$P" | jq -r --argjson x "$PX" --argjson y "$PY" '(.under.rect // null) as $r | if $r == null then false else ($x >= $r.x and $x <= ($r.x+$r.w) and $y >= $r.y and $y <= ($r.y+$r.h)) end' 2>/dev/null)"
  if [ "$RC3" -eq 0 ] && [ "$(J "$P" ok)" = "true" ] && [ "$(J "$P" under)" != "null" ] && [ "$CONTAINS" = "true" ]; then
    echo "PASS  N3 --point $PX,$PY -> under=$(printf '%s' "$P" | jq -r '.under.type + " " + (.under.name // "")' 2>/dev/null) via=$VIA"; PASS=$((PASS+1))
  else
    echo "FAIL  N3 point hit: rc=$RC3 via=$VIA contains=$CONTAINS $(printf '%s' "$P" | head -c 200)"; FAIL=$((FAIL+1))
  fi
else
  echo "SKIP  N3 no page-body text row (y 150..1450, depth>=8) to probe"; SKIP=$((SKIP+1))
fi

# N4 bilibili-specific wording, only when the active tab actually is bilibili
if printf '%s' "$TITLE" | grep -qi 'bilibili\|哔哩哔哩'; then
  L4="$(bin/wuia --hwnd "$EH" --find-text '投稿' 2>/dev/null)"; RC4=$?
  N4="$(J "$L4" total)"
  if [ "$RC4" -eq 0 ] && [ "${N4:-0}" -ge 1 ] 2>/dev/null; then
    echo "PASS  N4 bilibili tab -> --find-text '投稿' total=$N4"; PASS=$((PASS+1))
  else
    echo "FAIL  N4 bilibili find-text: rc=$RC4 $(printf '%s' "$L4" | head -c 200)"; FAIL=$((FAIL+1))
  fi
else
  echo "SKIP  N4 active tab is not bilibili (read-only smoke never switches tabs)"; SKIP=$((SKIP+1))
fi

# N5 performance budget (E16-5): a second, warm call must stay under 5 s
T1="$(date +%s%3N)"
bin/wuia --hwnd "$EH" --find-name '.' >/dev/null 2>&1
M5=$(( $(date +%s%3N) - T1 ))
if [ "$M5" -le 5000 ]; then
  echo "PASS  N5 warm --find-name '.' -> ${M5}ms (budget 5000ms)"; PASS=$((PASS+1))
else
  echo "FAIL  N5 warm find too slow: ${M5}ms > 5000ms"; FAIL=$((FAIL+1))
fi

echo
echo "$PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
