#!/usr/bin/env bash
# tests/check-m17.sh - M17 acceptance: text lines + geometric hit-test + click-by-text (T21, v1.3)
# Covers: N1 find-text returns named lines with geometry; N2 a page's lines come back in reading order;
#         N3 a regex that matches nothing is an honest empty answer; N4 point auto at a text center;
#         N5 --point-mode rect reports via:rect-hit; N6 blank area is ENV_NO_HIT (not "the Window");
#         N7 click --click-text clicks the line's center and the app really reacts;
#         N8 injection stays gated while find-text stays read-only; N9/N10 argument contracts;
#         N11 live smoke on the user's browser (WINADMIN_LIVE=1 only).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 5
. "$(pwd)/lib/common.sh"
PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL %s  [%s]\n' "$1" "$2"; }
skip() { SKIP=$((SKIP+1)); printf 'SKIP %s  [%s]\n' "$1" "$2"; }
TMP="/mnt/c/Users/Public/win-admin/tmp"
mkdir -p "$TMP"
G="$STATE_DIR/grant.json"
GBK="$STATE_DIR/grant.json.m17-bak"
cleanup() {
  bash tests/helpers/deepwin-stop.sh >/dev/null 2>&1
  if [ -f "$GBK" ]; then mv -f "$GBK" "$G"; fi
}
trap cleanup EXIT

num() { printf '%s' "$1" | jq -r ".$2 // empty"; }
diag() { printf '%s' "$1" | jq -c '{ok,mode,code,total,count,via,depthUsed,passes}'; }
# does json's .under/.hit/.lines[N] rect contain the point x,y?
contains() { # $1=json $2=jq path to rect $3=x $4=y
  printf '%s' "$1" | jq -e --argjson x "$3" --argjson y "$4" "($2) as \$r | (\$r.w > 0 and \$r.h > 0 and \$x >= \$r.x and \$x < (\$r.x + \$r.w) and \$y >= \$r.y and \$y < (\$r.y + \$r.h))" >/dev/null 2>&1
}

bash guard/grant.sh issue --minutes 30 --scope shot,uia,input,file:read --note "tests/check-m17.sh 本机验收（文本行与几何命中）" >/dev/null 2>&1 || true
bash tests/helpers/deepwin-stop.sh >/dev/null 2>&1
sleep 0.5
OUT="$(bash tests/helpers/deepwin-start.sh 2>/dev/null)"
if [ "$(printf %s "$OUT" | jq -r .ok 2>/dev/null)" != "true" ]; then
  echo "fixture failed to start: $OUT"; exit 5
fi
H="$(printf %s "$OUT" | jq -r .hwnd_dec)"
WRECT="$(bash bin/wuia --hwnd "$H" --depth 1 2>/dev/null | jq -c '.nodes[0].rect')"
WRX="$(printf '%s' "$WRECT" | jq -r .x)"; WRY="$(printf '%s' "$WRECT" | jq -r .y)"
WRW="$(printf '%s' "$WRECT" | jq -r .w)"; WRH="$(printf '%s' "$WRECT" | jq -r .h)"

# N1 (E17-1a) a text query returns named lines that carry geometry and depth
J="$(bash bin/wuia --hwnd "$H" --find-text '深层按钮' 2>/dev/null)"
T="$(num "$J" total)"; C="$(num "$J" count)"
L0OK="$(printf '%s' "$J" | jq -r '.lines[0] | (.text|length>0) and (.rect.w>0) and (.rect.h>0) and (.depth>0)' 2>/dev/null)"
if [ "$(printf %s "$J" | jq -r .ok)" = "true" ] && [ -n "$T" ] && [ "$T" -ge 1 ] && [ "$L0OK" = "true" ]; then
  ok "N1 find-text returns $T named line(s), first has text+rect+depth"
else
  bad "N1 find-text" "$(diag "$J")"
fi

# N2 (E17-1b) the three paragraphs come back in reading order (ascending y), each with a real rect
J2="$(bash bin/wuia --hwnd "$H" --find-text '第.条文本' 2>/dev/null)"
C2="$(num "$J2" count)"
ORDER="$(printf '%s' "$J2" | jq -r '[.lines[].rect.y] as $ys | ($ys == ($ys | sort))' 2>/dev/null)"
ALLPOS="$(printf '%s' "$J2" | jq -r '[.lines[] | (.rect.w>0 and .rect.h>0)] | all' 2>/dev/null)"
if [ "$C2" = "3" ] && [ "$ORDER" = "true" ] && [ "$ALLPOS" = "true" ]; then
  ok "N2 three paragraphs in y order, all rects positive"
else
  bad "N2 paragraph order" "count=$C2 order=$ORDER allpos=$ALLPOS $(diag "$J2")"
fi

# N3 (E17-1c) a query that matches nothing is an honest empty answer, not an error
J3="$(bash bin/wuia --hwnd "$H" --find-text '不存在的字' 2>/dev/null)"
if [ "$(printf %s "$J3" | jq -r .ok)" = "true" ] && [ "$(num "$J3" total)" = "0" ]; then
  ok "N3 no match -> ok:true total=0 (mode=$(num "$J3" mode))"
else
  bad "N3 empty answer" "$(diag "$J3")"
fi

# N4 (E17-3a) point at the center of the button line: something real is under it
CX="$(printf '%s' "$J" | jq -r '.lines[0].rect | .x + (.w/2) | floor')"
CY="$(printf '%s' "$J" | jq -r '.lines[0].rect | .y + (.h/2) | floor')"
P1="$(bash bin/wuia --hwnd "$H" --point "$CX,$CY" 2>/dev/null)"
if [ "$(printf %s "$P1" | jq -r .ok)" = "true" ] && [ "$(num "$P1" under.name)" != "" ] && contains "$P1" '.under.rect' "$CX" "$CY"; then
  ok "N4 point auto at ($CX,$CY) -> under='$(num "$P1" under.name)' via=$(num "$P1" via), rect contains the point"
else
  bad "N4 point auto" "$(diag "$P1") rect=$(printf '%s' "$P1" | jq -c '.under.rect')"
fi

# N5 (E17-3b) --point-mode rect forces the warm-tree geometric answer
P2="$(bash bin/wuia --hwnd "$H" --point "$CX,$CY" --point-mode rect 2>/dev/null)"
if [ "$(printf %s "$P2" | jq -r .ok)" = "true" ] && [ "$(num "$P2" via)" = "rect-hit" ] && contains "$P2" '.under.rect' "$CX" "$CY"; then
  ok "N5 --point-mode rect -> via=rect-hit under='$(num "$P2" under.name)'"
else
  bad "N5 rect mode" "via=$(num "$P2" via) $(diag "$P2")"
fi

# N6 (E17-4) a blank area inside the window is ENV_NO_HIT, not a fake "Window" hit
BX=$((WRX + WRW - 6)); BY=$((WRY + WRH - 6))
bash bin/wuia --hwnd "$H" --point "$BX,$BY" >"$TMP/m17-blank.json" 2>/dev/null; N6RC=$?
N6CODE="$(jq -r '.code // empty' "$TMP/m17-blank.json" 2>/dev/null)"
if [ "$N6RC" -eq 3 ] && [ "$N6CODE" = "ENV_NO_HIT" ] && [ "$(jq -r '.under // "null"' "$TMP/m17-blank.json")" = "null" ]; then
  ok "N6 blank ($BX,$BY) -> rc=3 ENV_NO_HIT, under=null"
else
  bad "N6 blank point" "rc=$N6RC code=$N6CODE $(diag "$(cat "$TMP/m17-blank.json" 2>/dev/null)")"
fi

# N7 (E17-2) click the line's center through --click-text; the app must really react
C1="$(bash bin/winput click --click-text '深层按钮' --expect-hwnd "$H" --yes 2>/dev/null)"
PTC="$(printf '%s' "$C1" | jq -c '.point // null')"
PX="$(printf '%s' "$C1" | jq -r '.point.x // empty')"; PY="$(printf '%s' "$C1" | jq -r '.point.y // empty')"
HITN="$(printf '%s' "$C1" | jq -r '.hit.name // empty')"
TITLE=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  TITLE="$(bash bin/wwin info --hwnd "$H" 2>/dev/null | jq -r '.window.title // ""')"
  case "$TITLE" in clicked:*) break ;; esac
  sleep 0.2
done
if [ "$(printf %s "$C1" | jq -r .ok)" = "true" ] && [ -n "$PX" ] && [ -n "$HITN" ] \
   && contains "$C1" '.hit.rect' "$PX" "$PY" && [ "$TITLE" = "clicked:deep-btn" ]; then
  ok "N7 click --click-text landed at $PTC on '$HITN', window title -> $TITLE"
else
  bad "N7 click-by-text" "ok=$(printf %s "$C1" | jq -r .ok) point=$PTC hit=$HITN title=$TITLE"
fi

# N8 injection stays gated: find-text is read-only (rc 0), click-by-text without a grant is rc 4
cp -f "$G" "$GBK" 2>/dev/null || true
rm -f "$G"
bash bin/wuia --hwnd "$H" --find-text '深层按钮' >/dev/null 2>&1; N8A=$?
bash bin/winput click --click-text '深层按钮' --expect-hwnd "$H" --yes >/dev/null 2>&1; N8B=$?
if [ -f "$GBK" ]; then mv -f "$GBK" "$G"; fi
if [ "$N8A" -eq 0 ] && [ "$N8B" -eq 4 ]; then
  ok "N8 no grant: find-text rc=0, click --click-text rc=4"
else
  bad "N8 guard gate" "find=$N8A click=$N8B (want 0/4)"
fi

# N9 --point-mode only knows auto|rect|uia
bash bin/wuia --hwnd "$H" --point 10,10 --point-mode nope >/dev/null 2>&1; N9=$?
if [ "$N9" -eq 2 ]; then ok "N9 --point-mode nope -> rc=2"; else bad "N9 point-mode contract" "rc=$N9"; fi

# N10 --click-text needs a window and takes no blind X Y
bash bin/winput click --click-text '深层按钮' --yes >/dev/null 2>&1; N10A=$?
bash bin/winput click --click-text '深层按钮' --expect-hwnd "$H" 100 100 --yes >/dev/null 2>&1; N10B=$?
if [ "$N10A" -eq 2 ] && [ "$N10B" -eq 2 ]; then
  ok "N10 --click-text without --expect-hwnd rc=2, with X Y rc=2"
else
  bad "N10 click-text contract" "no-hwnd=$N10A with-xy=$N10B (want 2/2)"
fi

# N11 live smoke: the user's own browser, read-only (WINADMIN_LIVE=1)
if [ "${WINADMIN_LIVE:-0}" = "1" ]; then
  EH="$(bash bin/wwin list 2>/dev/null | jq -r '.windows[] | select(.title | test("Microsoft Edge")) | .hwnd_dec' | head -1)"
  if [ -z "$EH" ] || [ "$EH" = "null" ]; then
    skip "N11 live find-text" "no Edge window open"
  else
    J="$(bash bin/wuia --hwnd "$EH" --find-text '.' 2>/dev/null)"
    T="$(num "$J" total)"
    if [ "$(printf %s "$J" | jq -r .ok)" = "true" ] && [ -n "$T" ] && [ "$T" -ge 1 ]; then
      ok "N11 live Edge find-text total=$T depthUsed=$(num "$J" depthUsed)"
    else
      bad "N11 live find-text" "$(diag "$J")"
    fi
  fi
else
  skip "N11 live find-text" "set WINADMIN_LIVE=1 to run"
fi

printf "\n%s passed, %s failed, %s skipped\n" "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" = "0" ] || exit 1
exit 0
