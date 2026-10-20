#!/usr/bin/env bash
# tests/check-m3.sh - M3 acceptance: safety family S1-S8 (docs/07). Negative cases first.
# Every check prints PASS/FAIL/SKIP; SUMMARY pass=N fail=M skip=K; exit 1 on any FAIL.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. lib/common.sh

PASS=0; FAIL=0; SKIP=0
ok()  { PASS=$((PASS+1)); printf 'PASS  %s\n' "$*"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$*"; }
skp() { SKIP=$((SKIP+1)); printf 'SKIP  %s\n' "$*"; }
say() { printf '\n== %s\n' "$*"; }

GH="$STATE_DIR/grant.json"
GB="$STATE_DIR/grant.json.m3-bak"
HOOK="$APP_ROOT/tmp/force-desktop.txt"
AUDDIR="$STATE_DIR/audit"
TODAY="$AUDDIR/$(date +%F).jsonl"
SHOTS="$APP_ROOT/tmp"

HAD_GRANT=0
[ -f "$GH" ] && { HAD_GRANT=1; cp -f "$GH" "$GB"; }

cleanup() {
  rm -f "$STATE_DIR/pause.flag" "$HOOK"
  if [ "$HAD_GRANT" = "1" ] && [ -f "$GB" ]; then mv -f "$GB" "$GH"; fi
  if [ "$HAD_GRANT" = "0" ]; then rm -f "$GH" "$GB"; fi
  bash tests/helpers/testwin-stop.sh >/dev/null 2>&1 || true
}
trap cleanup EXIT

say "env"
DIAG="$(bash bin/wdiag 2>/dev/null || true)"
if [ "$(printf '%s' "$DIAG" | jq -r '.ok // false' 2>/dev/null)" != "true" ]; then
  echo "FATAL: wdiag failed (payload not installed?)"; exit 1
fi
SW="$(printf '%s' "$DIAG" | jq -r '.screen.w')"
SH="$(printf '%s' "$DIAG" | jq -r '.screen.h')"
SECURED="$(printf '%s' "$DIAG" | jq -r '.desktop.secured')"
GUI=1
BR="n/a"
[ "$SECURED" = "true" ] && GUI=0

if [ "$GUI" = "1" ]; then
  bash bin/wshot --out "$SHOTS/m3-probe.png" >/dev/null 2>&1 || GUI=0
fi
if [ "$GUI" = "1" ]; then
  BR="$(python3 tests/helpers/brightness.py "$SHOTS/m3-probe.png" 2>/dev/null || echo 0)"
  case "$BR" in ''|*[!0-9.]*) BR=0 ;; esac
  if awk "BEGIN{exit !($BR < 8)}"; then GUI=0; fi
fi
echo "screen=${SW}x${SH} secured=$SECURED gui=$GUI brightness=$BR"

TW=""
TW_HWND=0
if [ "$GUI" = "1" ]; then
  TW="$(bash tests/helpers/testwin-start.sh wa-m3win 2>/dev/null | tail -1)"
  TW_HWND="$(printf '%s' "$TW" | jq -r '.hwnd_dec // 0' 2>/dev/null || echo 0)"
fi

# ---------------------------------------------------------------- S1
say "S1 no grant -> exit 4, screen region unchanged"
rm -f "$GH"
if [ "$GUI" = "1" ] && [ "$TW_HWND" -gt 0 ]; then
  BX="$(printf '%s' "$TW" | jq -r '.button.x + (.button.w / 2 | floor)')"
  BY="$(printf '%s' "$TW" | jq -r '.button.y + (.button.h / 2 | floor)')"
  RECT="$(printf '%s' "$TW" | jq -r '[.button.x,.button.y,.button.w,.button.h] | join(",")')"
  bash bin/wshot --out "$SHOTS/m3-s1-a.png" >/dev/null 2>&1
  OUT="$(bash bin/winput click "$BX" "$BY" --expect-hwnd "$TW_HWND" --yes 2>&1)"; RC=$?
  CODE="$(printf '%s' "$OUT" | jq -r '.code // ""' 2>/dev/null)"
  bash bin/wshot --out "$SHOTS/m3-s1-b.png" >/dev/null 2>&1
  PD="$(python3 tests/helpers/pixdiff.py "$SHOTS/m3-s1-a.png" "$SHOTS/m3-s1-b.png" --rect "$RECT" 2>/dev/null || true)"
  SAME="$(printf '%s' "$PD" | jq -r '.same // false' 2>/dev/null)"
  if [ "$RC" = "4" ] && [ "$CODE" = "GUARD_NO_GRANT" ] && [ "$SAME" = "true" ]; then
    ok "S1 rc=4 GUARD_NO_GRANT, region $RECT diff_pixels=0"
  else
    bad "S1 rc=$RC code=$CODE pixdiff=$PD"
  fi
else
  OUT="$(bash bin/winput move 100 100 --yes 2>&1)"; RC=$?
  CODE="$(printf '%s' "$OUT" | jq -r '.code // ""' 2>/dev/null)"
  if [ "$RC" = "4" ] && [ "$CODE" = "GUARD_NO_GRANT" ]; then ok "S1 rc=4 GUARD_NO_GRANT (pixel check skipped: no gui)"; else bad "S1 rc=$RC code=$CODE"; fi
  skp "S1 pixel diff (gui unavailable or no test window)"
fi

bash guard/grant.sh issue --minutes 30 --scope input --note "M3 验收自测（SG-0001 夜间授权）" >/dev/null 2>&1 || true

# ---------------------------------------------------------------- S2
say "S2 pause.flag blocks input even with a valid grant"
bash guard/grant.sh pause >/dev/null 2>&1
OUT="$(bash bin/winput move 100 100 --yes 2>&1)"; RC=$?
CODE="$(printf '%s' "$OUT" | jq -r '.code // ""' 2>/dev/null)"
if [ "$RC" = "4" ] && [ "$CODE" = "GUARD_PAUSED" ]; then ok "S2 rc=4 GUARD_PAUSED"; else bad "S2 rc=$RC code=$CODE"; fi
bash guard/grant.sh resume >/dev/null 2>&1
if [ ! -f "$STATE_DIR/pause.flag" ]; then ok "S2 resume removes pause.flag"; else bad "S2 pause.flag still present"; fi
OUT="$(bash bin/winput move 100 100 --yes 2>&1)"; RC=$?
CODE="$(printf '%s' "$OUT" | jq -r '.code // ""' 2>/dev/null)"
if [ "$RC" = "0" ]; then ok "S2 after resume real move rc=0"; else bad "S2 after resume rc=$RC code=$CODE"; fi

# ---------------------------------------------------------------- S3
say "S3 locked session -> exit 3 SESSION_LOCKED"
printf 'LockedSession' > "$HOOK"
OUT="$(bash bin/winput move 100 100 --yes 2>&1)"; RC=$?
CODE="$(printf '%s' "$OUT" | jq -r '.code // ""' 2>/dev/null)"
if [ "$RC" = "3" ] && [ "$CODE" = "SESSION_LOCKED" ]; then ok "S3 rc=3 SESSION_LOCKED"; else bad "S3 rc=$RC code=$CODE"; fi
rm -f "$HOOK"

# ---------------------------------------------------------------- S4
say "S4 secure desktop (UAC) -> exit 3 UAC_SECURE_DESKTOP"
printf 'Winlogon' > "$HOOK"
OUT="$(bash bin/winput move 100 100 --yes 2>&1)"; RC=$?
CODE="$(printf '%s' "$OUT" | jq -r '.code // ""' 2>/dev/null)"
WOUT="$(bash bin/wshot --out "$SHOTS/m3-s4.png" 2>&1)"; WRC=$?
WCODE="$(printf '%s' "$WOUT" | jq -r '.code // ""' 2>/dev/null)"
if [ "$RC" = "3" ] && [ "$CODE" = "UAC_SECURE_DESKTOP" ]; then ok "S4 winput rc=3 UAC_SECURE_DESKTOP"; else bad "S4 rc=$RC code=$CODE"; fi
if [ "$WRC" = "3" ] && [ "$WCODE" = "UAC_SECURE_DESKTOP" ]; then ok "S4 wshot rc=3 UAC_SECURE_DESKTOP"; else bad "S4 wshot rc=$WRC code=$WCODE"; fi
rm -f "$HOOK"

# ---------------------------------------------------------------- S5
say "S5 audit ledger: 20 actions -> 20 lines, 5 failures"
BASE=0
[ -f "$TODAY" ] && BASE="$(wc -l < "$TODAY")"
for i in $(seq 1 15); do bash bin/winput move 100 100 >/dev/null 2>&1; done
mv -f "$GH" "$STATE_DIR/grant.json.s5" 2>/dev/null
for i in $(seq 1 5); do bash bin/winput move 100 100 --yes >/dev/null 2>&1 || true; done
mv -f "$STATE_DIR/grant.json.s5" "$GH" 2>/dev/null
AFTER=0
[ -f "$TODAY" ] && AFTER="$(wc -l < "$TODAY")"
DELTA=$(( AFTER - BASE ))
if [ "$DELTA" = "20" ]; then ok "S5 delta lines=$DELTA"; else bad "S5 delta lines=$DELTA (want 20)"; fi
LINES="$(tail -n 20 "$TODAY")"
NF="$(printf '%s\n' "$LINES" | jq -r 'select(.result != "ok" and .result != "dryrun") | .result' 2>/dev/null | wc -l)"
if [ "$NF" = "5" ]; then ok "S5 failure lines=$NF"; else bad "S5 failure lines=$NF (want 5)"; fi
BADSCHEMA="$(printf '%s\n' "$LINES" | jq -r 'select((.ts // "") == "" or (.tool // "") != "winput" or (.args | type) != "array" or (.result // "") == "" or (.duration_ms | type) != "number") | .ts' 2>/dev/null | wc -l)"
if [ "$BADSCHEMA" = "0" ]; then ok "S5 every line has ts/tool/args/result/duration_ms"; else bad "S5 $BADSCHEMA malformed audit lines"; fi
FRES="$(printf '%s\n' "$LINES" | jq -r 'select(.result == "GUARD_NO_GRANT") | .pid' 2>/dev/null | wc -l)"
if [ "$FRES" = "5" ]; then ok "S5 denials audited as GUARD_NO_GRANT"; else bad "S5 GUARD_NO_GRANT lines=$FRES"; fi

# ---------------------------------------------------------------- S6
say "S6 grant token integrity"
cp -f "$GH" "$STATE_DIR/grant.json.s6bak"
jq '.note = "edited by hand"' "$STATE_DIR/grant.json.s6bak" > "$GH"
OUT="$(bash guard/check.sh input 2>&1)"; RC=$?
CODE="$(printf '%s' "$OUT" | jq -r '.code // ""' 2>/dev/null)"
if [ "$RC" = "4" ] && [ "$CODE" = "GUARD_TAMPERED" ]; then ok "S6 edited note -> GUARD_TAMPERED"; else bad "S6 edited note rc=$RC code=$CODE"; fi
jq '.sig = "deadbeef"' "$STATE_DIR/grant.json.s6bak" > "$GH"
OUT="$(bash guard/check.sh input 2>&1)"; RC=$?
CODE="$(printf '%s' "$OUT" | jq -r '.code // ""' 2>/dev/null)"
if [ "$RC" = "4" ] && [ "$CODE" = "GUARD_TAMPERED" ]; then ok "S6 forged sig -> GUARD_TAMPERED"; else bad "S6 forged sig rc=$RC code=$CODE"; fi
jq 'del(.sig)' "$STATE_DIR/grant.json.s6bak" > "$GH"
OUT="$(bash guard/check.sh input 2>&1)"; RC=$?
CODE="$(printf '%s' "$OUT" | jq -r '.code // ""' 2>/dev/null)"
if [ "$RC" = "4" ] && [ "$CODE" = "GUARD_TAMPERED" ]; then ok "S6 unsigned grant -> GUARD_TAMPERED"; else bad "S6 unsigned rc=$RC code=$CODE"; fi
mv -f "$STATE_DIR/grant.json.s6bak" "$GH"
OUT="$(bash guard/check.sh input 2>&1)"; RC=$?
if [ "$RC" = "0" ]; then ok "S6 restored signed grant -> ok"; else bad "S6 restored rc=$RC out=$OUT"; fi
WRITERS="$(grep -rl 'mv "$G.tmp" "$G"' guard bin lib 2>/dev/null | sort | tr '\n' ' ')"
if [ "$WRITERS" = "guard/grant.sh " ]; then ok "S6 only guard/grant.sh writes grant.json"; else bad "S6 grant writers: $WRITERS"; fi

# ---------------------------------------------------------------- S7
say "S7 coordinate click must verify the expected window"
OUT="$(bash bin/winput click 100 100 --yes 2>&1)"; RC=$?
CODE="$(printf '%s' "$OUT" | jq -r '.code // ""' 2>/dev/null)"
if [ "$RC" = "2" ] && [ "$CODE" = "ARG_NEED_EXPECT_HWND" ]; then ok "S7 missing --expect-hwnd rc=2"; else bad "S7 missing hwnd rc=$RC code=$CODE"; fi
OUT="$(bash bin/winput click 100 100 --expect-hwnd 1 --yes 2>&1)"; RC=$?
CODE="$(printf '%s' "$OUT" | jq -r '.code // ""' 2>/dev/null)"
if [ "$RC" = "3" ] && [ "$CODE" = "ENV_NO_WINDOW" ]; then ok "S7 bogus hwnd rc=3 ENV_NO_WINDOW"; else bad "S7 bogus hwnd rc=$RC code=$CODE"; fi

# ---------------------------------------------------------------- S8
say "S8 red lines absent from code"
HITS="$(grep -rInE 'consent\.exe|LockWorkStation|taskkill[[:space:]].*explorer|netsh |schtasks |reg add |net user ' bin lib guard win 2>/dev/null | grep -v 'wa-core.ps1:.*Winlogon' || true)"
if [ -z "$HITS" ]; then ok "S8 no consent/LockWorkStation/explorer-kill/system-config calls"; else bad "S8 red-line hits: $HITS"; fi
HITS2="$(grep -rInE 'https?://' win bin lib guard 2>/dev/null || true)"
if [ -z "$HITS2" ]; then ok "S8 no network calls in code"; else bad "S8 network refs: $HITS2"; fi

printf '\nSUMMARY pass=%d fail=%d skip=%d\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
