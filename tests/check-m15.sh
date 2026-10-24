#!/usr/bin/env bash
# tests/check-m15.sh - M15 acceptance: ops/map element map (T16, v1.2)
# Covers: N1 map lists elements; N2 idx is reading order (y,x); N3 actionable count agrees with an
# independent wuia search; N4 the PNG is exactly the window rect; N5 boxes are actually painted;
# N6 --text writes no screenshot; N7 map needs no scope=input (S11) while input still does;
# N8 argument contract.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 5
. "$(pwd)/lib/common.sh"
PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf 'ok   %s
' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL %s  [%s]
' "$1" "$2"; }
skip() { SKIP=$((SKIP+1)); printf 'SKIP %s  [%s]
' "$1" "$2"; }
TMP="/mnt/c/Users/Public/win-admin/tmp"
WTMP="C:/Users/Public/win-admin/tmp"
SHOTS="$APP_ROOT/shots"
G="$STATE_DIR/grant.json"; GBK="$G.m15-bak"
cleanup() {
  bash tests/helpers/uiawnd-stop.sh >/dev/null 2>&1
  rm -f "$TMP/m15-plain.png" "$TMP/m15-map.png"
  if [ -f "$GBK" ]; then mv -f "$GBK" "$G"; else rm -f "$G"; fi
}
trap cleanup EXIT
if [ -f "$G" ]; then cp "$G" "$GBK"; fi
bash guard/grant.sh issue --minutes 30 --scope shot,uia,input,file:read --note 'tests/check-m15.sh 本机验收（元素地图）' >/dev/null 2>&1 || true
mkdir -p "$TMP"
bash tests/helpers/uiawnd-start.sh >/dev/null 2>&1 || { echo 'fixture failed'; exit 5; }
W="$(jq -r .hwnd_dec /mnt/c/Users/Public/win-admin/tmp/uiawnd.json)"
[ -n "$W" ] && [ "$W" != null ] || { echo 'no fixture hwnd'; exit 5; }
RECT="$(bin/wwin info --hwnd "$W" | jq -c .window.rect)"
WW="$(printf %s "$RECT" | jq -r .w)"
WH="$(printf %s "$RECT" | jq -r .h)"
mkdir -p "$SHOTS"
S0="$(find "$SHOTS" -maxdepth 1 -type f | wc -l)"

# N1 --text lists elements without touching the screen
JT="$(ops/map --hwnd "$W" --text 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && [ "$(printf %s "$JT" | jq -r .ok)" = true ] && [ "$(printf %s "$JT" | jq -r .count)" -ge 10 ]; then
  ok "N1 ops/map --text lists $(printf %s "$JT" | jq -r .count) elements"
else
  bad 'N1 map --text' "rc=$RC $(printf %s "$JT" | head -c 200)"
fi

# N2 numbering follows reading order (y,x)
ORD="$(printf %s "$JT" | jq -c '[.nodes[] | [.rect.y, .rect.x]] as $k | ($k == ($k | sort))')"
IDXOK="$(printf %s "$JT" | jq -c '[.nodes[].idx] as $i | ($i == [range(0; ($i|length))])')"
if [ "$ORD" = true ] && [ "$IDXOK" = true ]; then
  ok 'N2 idx is 0..n-1 in (y,x) reading order'
else
  bad 'N2 reading order' "by_yx=$ORD contiguous=$IDXOK"
fi

# N3 actionable count agrees with an independent wuia search (same tree, different code path)
# --find-type . rather than --find-name .: an Edit and a ComboBox often have an EMPTY name yet are
# perfectly actionable, so a name-based cross-check would silently undercount (docs/20 E15-4 note).
WF="$(bin/wuia --hwnd "$W" --find-type . --enabled --on-screen --depth 16 --max 8000 --limit 1000 2>/dev/null)"
EXP="$(printf %s "$WF" | jq '[.nodes[] | select(.rect.w > 0 and .rect.h > 0) | select((.patterns | map(select(test("^(Invoke|Toggle|SelectionItem|ExpandCollapse|Value|RangeValue|ScrollItem)$"))) | length) > 0)] | length')"
GOT="$(printf %s "$JT" | jq -r .actionable)"
if [ -n "$EXP" ] && [ "$EXP" = "$GOT" ]; then
  ok "N3 actionable=$GOT agrees with wuia patterns cross-check"
else
  bad 'N3 actionable cross-check' "map=$GOT wuia=$EXP"
fi

# N6 (before the shot tests) --text mode wrote no file
S1="$(find "$SHOTS" -maxdepth 1 -type f | wc -l)"
if [ "$S0" = "$S1" ]; then ok 'N6 --text produced no screenshot (S11)'; else bad 'N6 --text shot-free' "shots $S0 -> $S1"; fi

# N4 the PNG is exactly the window rect
JM="$(ops/map --hwnd "$W" --out "$TMP/m15-map.png" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && [ "$(printf %s "$JM" | jq -r .ok)" = true ]; then
  DIM="$(python3 -c "import struct,sys; d=open(sys.argv[1],'rb').read(33); w,h=struct.unpack('>II', d[16:24]); print(f'{w}x{h}')" "$TMP/m15-map.png")"
  WANT="${WW}x${WH}"
  if [ "$DIM" = "$WANT" ]; then ok "N4 map png is exactly the window rect $DIM"; else bad 'N4 png geometry' "$DIM != $WANT"; fi
else
  bad 'N4 map png' "rc=$RC $(printf %s "$JM" | head -c 200)"
fi

# N5 the boxes are really painted: annotated shot differs from a clean one
bin/wshot --hwnd "$W" --out "$TMP/m15-plain.png" >/dev/null 2>&1
CMP="$(winps -r -t 60 -f /root/win-admin/tests/helpers/imgcmp.ps1 -A "$WTMP/m15-plain.png" -B "$WTMP/m15-map.png" -Pixels "10,10;400,465" | tail -1)"
DR="$(printf %s "$CMP" | jq -r .diff_ratio)"
SAME="$(printf %s "$CMP" | jq -r .same_size)"
if [ "$SAME" = true ] && [ "$(awk -v d="$DR" 'BEGIN{print (d>0.002)?1:0}')" = 1 ]; then
  ok "N5 element boxes painted on the shot (diff_ratio=$DR)"
else
  bad 'N5 boxes painted' "same=$SAME diff=$DR $(printf %s "$CMP" | head -c 120)"
fi

# N7 only-read grant: map still works, input still does not (S11)
bash guard/grant.sh issue --minutes 30 --scope shot,uia --note 'tests/check-m15.sh S11 只读边界' >/dev/null 2>&1 || true
JRO="$(ops/map --hwnd "$W" --text 2>&1)"; RCRO=$?
bin/winput click 10 10 --yes >/dev/null 2>&1; RCIN=$?
bash guard/grant.sh issue --minutes 30 --scope shot,uia,input,file:read --note 'tests/check-m15.sh 复原' >/dev/null 2>&1 || true
if [ "$RCRO" -eq 0 ] && [ "$(printf %s "$JRO" | jq -r .ok)" = true ] && [ "$RCIN" -eq 4 ]; then
  ok 'N7 map runs on a shot,uia grant while input still needs scope=input'
else
  bad 'N7 read-only boundary' "map_rc=$RCRO input_rc=$RCIN"
fi

# N8 argument contract
ops/map --hwnd "$W" --depth 0 >/dev/null 2>&1; R1=$?
ops/map --hwnd "$W" --bogus >/dev/null 2>&1; R2=$?
ops/map --text >/dev/null 2>&1; R3=$?
if [ "$R1" -eq 2 ] && [ "$R2" -eq 2 ] && [ "$R3" -eq 2 ]; then
  ok 'N8 bad depth / unknown flag / missing target all rc=2'
else
  bad 'N8 arg contract' "depth0=$R1 bogus=$R2 notarget=$R3"
fi

printf "\n%s passed, %s failed, %s skipped\n" "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" = "0" ] || exit 1
exit 0
