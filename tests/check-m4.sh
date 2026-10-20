#!/usr/bin/env bash
# tests/check-m4.sh - M4 acceptance: composite ops + C8 end-to-end (docs/07). Negative cases first.
# Every check prints PASS/FAIL/SKIP; SUMMARY pass=N fail=M skip=K; exit 1 on any FAIL.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. lib/common.sh

PASS=0; FAIL=0; SKIP=0
ok()  { PASS=$((PASS+1)); printf "PASS  %s\n" "$*"; }
bad() { FAIL=$((FAIL+1)); printf "FAIL  %s\n" "$*"; }
skp() { SKIP=$((SKIP+1)); printf "SKIP  %s\n" "$*"; }
say() { printf "\n== %s\n" "$*"; }

GH="$STATE_DIR/grant.json"
GB="$STATE_DIR/grant.json.m4-bak"
SHOTS="$APP_ROOT/tmp"
WIN_TMP="/mnt/c/Users/Public/win-admin/tmp"
OPENED=""
HAD_GRANT=0
CREATED_GRANT=0

cleanup() {
  for h in $OPENED; do bash bin/wwin close --hwnd "$h" >/dev/null 2>&1 || true; done
  if [ "$HAD_GRANT" = "1" ] && [ -f "$GB" ]; then mv -f "$GB" "$GH"; fi
  if [ "$CREATED_GRANT" = "1" ]; then bash guard/grant.sh revoke >/dev/null 2>&1 || true; rm -f "$GH"; fi
  rm -f "$STATE_DIR/grant.json.m4-n1"
}
trap cleanup EXIT

say "env"
DIAG="$(bash bin/wdiag 2>/dev/null || true)"
if [ "$(printf "%s" "$DIAG" | jq -r ".ok // false" 2>/dev/null)" != "true" ]; then
  echo "FATAL: wdiag failed (payload not installed?)"; exit 1
fi
SECURED="$(printf "%s" "$DIAG" | jq -r ".desktop.secured")"
GUI=1; BR="n/a"
[ "$SECURED" = "true" ] && GUI=0
if [ "$GUI" = "1" ]; then
  bash bin/wshot --out "$SHOTS/m4-probe.png" >/dev/null 2>&1 || GUI=0
fi
if [ "$GUI" = "1" ]; then
  BR="$(python3 tests/helpers/brightness.py "$SHOTS/m4-probe.png" 2>/dev/null || echo 0)"
  case "$BR" in ""|*[!0-9.]*) BR=0 ;; esac
  if awk "BEGIN{exit !($BR < 8)}"; then GUI=0; fi
fi
echo "screen=$(printf "%s" "$DIAG" | jq -r ".screen.w")x$(printf "%s" "$DIAG" | jq -r ".screen.h") secured=$SECURED gui=$GUI brightness=$BR"

if [ -f "$GH" ]; then HAD_GRANT=1; cp -f "$GH" "$GB"; fi
GRANT_OK="$(bash guard/grant.sh status 2>/dev/null | jq -r ".valid // false")"
if [ "$GRANT_OK" != "true" ]; then
  bash guard/grant.sh issue --minutes 30 --scope input --note "tests/check-m4.sh：M4 验收（用户 m00805 夜间授权）" >/dev/null 2>&1
  CREATED_GRANT=1
  echo "note: issued a 30-min test grant (revoked at exit)"
fi

# one full end-to-end round: shared with check-m5 (tests/helpers/e2e.sh)
. tests/helpers/e2e.sh

if [ "$GUI" != "1" ]; then
  skp "M4-C8 all end-to-end checks (desktop secured or display off)"
  printf "\nSUMMARY pass=%d fail=%d skip=%d\n" "$PASS" "$FAIL" "$SKIP"
  [ "$FAIL" -eq 0 ] && exit 0 || exit 1
fi

# ------------------------------------------------------------------ guard / arg negatives
say "N1 no grant -> ops/open exit 4, no window"
GN="$STATE_DIR/grant.json.m4-n1"   # park our own grant here; must NOT share the $GB cleanup slot (K35)
mv -f "$GH" "$GN" 2>/dev/null || true
if [ -f "$GH" ]; then rm -f "$GH"; fi
OUT="$(bash ops/open --exe notepad --args "C:\\Users\\Public\\win-admin\\tmp\\m4-guard.txt" --title "m4-guard" --timeout 3 --yes 2>&1)"; RC=$?
CODE="$(printf "%s" "$OUT" | jq -r '.code // empty' 2>/dev/null)"
WINS="$(bash bin/wwin list | jq -r --arg t "m4-guard" '[.windows[] | select(.title | test($t))] | length')"
if [ -f "$GN" ]; then mv -f "$GN" "$GH"; fi   # restore unconditionally (own grant or inherited)
if [ "$RC" = "4" ] && [ "$CODE" = "GUARD_NO_GRANT" ] && [ "$WINS" = "0" ]; then
  ok "N1 rc=4 GUARD_NO_GRANT, windows opened=0"
else
  bad "N1 rc=$RC code=$CODE windows=$WINS"
fi

say "N2 ops/open unknown exe -> exit 3 ENV_NO_EXE"
OUT="$(bash ops/open --exe definitely-not-a-program-xyz --title "nope" --timeout 3 --yes 2>&1)"; RC=$?
CODE="$(printf "%s" "$OUT" | jq -r '.code // empty' 2>/dev/null)"
if [ "$RC" = "3" ] && [ "$CODE" = "ENV_NO_EXE" ]; then ok "N2 rc=3 ENV_NO_EXE"; else bad "N2 rc=$RC code=$CODE"; fi

say "N3 ops/open dry-run -> JSON plan, no window"
OUT="$(bash ops/open --exe notepad --args "C:\\Users\\Public\\win-admin\\tmp\\m4-dry.txt" --title "m4-dry" 2>&1)"; RC=$?
DR="$(printf "%s" "$OUT" | jq -r ".dry_run // false" 2>/dev/null)"
if [ "$RC" = "0" ] && [ "$DR" = "true" ]; then ok "N3 rc=0 dry_run=true"; else bad "N3 rc=$RC dry_run=$DR"; fi

say "N4 ops/fill without --text -> exit 2"
OUT="$(bash ops/fill --hwnd 1 2>&1)"; RC=$?
if [ "$RC" = "2" ]; then ok "N4 rc=2"; else bad "N4 rc=$RC"; fi

say "N6 ops/wait-for timeout -> exit 3 ENV_WAIT_TIMEOUT"
OUT="$(bash ops/wait-for --title "zzz-not-there-xyz" --timeout 1 2>&1)"; RC=$?
CODE="$(printf "%s" "$OUT" | jq -r '.code // empty' 2>/dev/null)"
if [ "$RC" = "3" ] && [ "$CODE" = "ENV_WAIT_TIMEOUT" ]; then ok "N6 rc=3 ENV_WAIT_TIMEOUT"; else bad "N6 rc=$RC code=$CODE"; fi

# ------------------------------------------------------------------ C8 unit pieces
say "C8-1 ops/open real -> hwnd in <10s"
WF="$WIN_TMP/m4-c8-1.txt"; rm -f "$WF"; : > "$WF"
O="$(bash ops/open --exe notepad --args "C:\\Users\\Public\\win-admin\\tmp\\m4-c8-1.txt" --title "m4-c8-1" --timeout 10 --yes 2>&1)"; RC=$?
H="$(printf "%s" "$O" | jq -r ".window.hwnd_dec // 0" 2>/dev/null || echo 0)"
MS="$(printf "%s" "$O" | jq -r ".elapsed_ms // 99999" 2>/dev/null || echo 99999)"
[ "$H" != "0" ] && OPENED="$OPENED $H"
if [ "$RC" = "0" ] && [ "$H" != "0" ] && [ "$MS" -lt 10000 ]; then ok "C8-1 hwnd=$H elapsed=${MS}ms"; else bad "C8-1 rc=$RC hwnd=$H ms=$MS"; fi

say "N5 ops/find-and-click unknown control -> exit 3 ENV_NO_NODE"
OUT="$(bash ops/find-and-click --hwnd "$H" --name "zzz-not-there" --yes 2>&1)"; RC=$?
CODE="$(printf "%s" "$OUT" | jq -r '.code // empty' 2>/dev/null)"
if [ "$RC" = "3" ] && [ "$CODE" = "ENV_NO_NODE" ]; then ok "N5 rc=3 ENV_NO_NODE"; else bad "N5 rc=$RC code=$CODE"; fi

say "C8-2 ops/fill dry-run -> node + point, no injection"
OUT="$(bash ops/fill --hwnd "$H" --name "文本编辑器" --text "dry" 2>&1)"; RC=$?
PT="$(printf "%s" "$OUT" | jq -r ".point.x // empty" 2>/dev/null)"
if [ "$RC" = "0" ] && [ -n "$PT" ] && [ "$(printf "%s" "$OUT" | jq -r ".dry_run // false")" = "true" ]; then ok "C8-2 dry_run point.x=$PT"; else bad "C8-2 rc=$RC out=$(printf "%s" "$OUT" | head -c 200)"; fi

say "C8-3 ops/fill real -> readback matches (C5)"
FO="$(bash ops/fill --hwnd "$H" --name "文本编辑器" --text "M4 验收：中文输入、emoji ✅、第二行" --yes 2>&1)"; RC=$?
MATCH="$(printf "%s" "$FO" | jq -r ".matches // false" 2>/dev/null)"
if [ "$RC" = "0" ] && [ "$MATCH" = "true" ]; then ok "C8-3 matches=true"; else bad "C8-3 rc=$RC matches=$MATCH"; fi

say "C8-4 ctrl+s then file content equals text"
bash bin/winput key ctrl+s --expect-hwnd "$H" --yes >/dev/null 2>&1 || true
sleep 0.8
CONTENT="$(cat "$WF" 2>/dev/null || true)"
if [ "$CONTENT" = "M4 验收：中文输入、emoji ✅、第二行" ]; then ok "C8-4 file bytes=$(stat -c %s "$WF") content matches"; else bad "C8-4 file content=[$CONTENT]"; fi

say "C8-5 ops/wait-for --uia-name finds the document control"
T0=$(date +%s%3N)
OUT="$(bash ops/wait-for --hwnd "$H" --uia-name "^文本编辑器$" --timeout 3 2>&1)"; RC=$?
EL=$(( $(date +%s%3N) - T0 ))
if [ "$RC" = "0" ] && [ "$(printf "%s" "$OUT" | jq -r '.mode // empty' 2>/dev/null)" = "uia" ]; then ok "C8-5 found in ${EL}ms"; else bad "C8-5 rc=$RC out=$(printf "%s" "$OUT" | head -c 200)"; fi

say "C8-6 wwin close -> window gone, unsaved dialog handled by app"
bash bin/wwin close --hwnd "$H" >/dev/null 2>&1 || true
sleep 0.8
if [ "$(cat "$WF" 2>/dev/null || true)" = "M4 验收：中文输入、emoji ✅、第二行" ] && ! bash bin/wwin info --hwnd "$H" >/dev/null 2>&1; then ok "C8-6 closed cleanly (no dirty prompt)"; else bad "C8-6 window still open or content changed"; fi

# ------------------------------------------------------------------ E8 repeatability
say "E8 three consecutive end-to-end rounds (C8), each <60s"
GREEN=0
for i in 1 2 3; do
  R="$(c8_once "r$i" "M4 验收第 $i 轮：中文 ✅")"
  MS="$(printf "%s" "$R" | awk "{print \$1}")"
  RES="$(printf "%s" "$R" | awk "{print \$2}")"
  if [ "$RES" = "true" ] && [ "$MS" -lt 60000 ]; then GREEN=$((GREEN+1)); echo "  round $i: ${MS}ms PASS"; else echo "  round $i: ${MS}ms FAIL $(printf "%s" "$R" | cut -d" " -f3-)"; fi
done
if [ "$GREEN" = "3" ]; then ok "E8 3/3 end-to-end rounds green"; else bad "E8 $GREEN/3 rounds green"; fi

printf "\nSUMMARY pass=%d fail=%d skip=%d\n" "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
