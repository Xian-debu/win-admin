#!/usr/bin/env bash
# tests/check-m5.sh - M5 stabilization: full regression (m1..m4 + release) + E8 ten rounds (docs/07).
# Prints PASS/FAIL per suite and per round; SUMMARY pass=N fail=M skip=K; exit 1 on any FAIL.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. lib/common.sh

# --only-b: skip part A (used when re-running the E8 rounds alone, e.g. after a transient lock)
ONLY_A=1
[ "${1:-}" = "--only-b" ] && ONLY_A=0
# --only-a: skip part B (regression sweep without touching the desktop)
ONLY_B=1
[ "${1:-}" = "--only-a" ] && ONLY_B=0

PASS=0; FAIL=0; SKIP=0
ok()  { PASS=$((PASS+1)); printf "PASS  %s\n" "$*"; }
bad() { FAIL=$((FAIL+1)); printf "FAIL  %s\n" "$*"; }
skp() { SKIP=$((SKIP+1)); printf "SKIP  %s\n" "$*"; }
say() { printf "\n== %s\n" "$*"; }

GH="$STATE_DIR/grant.json"
GB="$STATE_DIR/grant.json.m5-bak"
SHOTS="$APP_ROOT/tmp"
WIN_TMP="/mnt/c/Users/Public/win-admin/tmp"
OPENED=""
HAD_GRANT=0
CREATED_GRANT=0

cleanup() {
  for h in $OPENED; do bash bin/wwin close --hwnd "$h" >/dev/null 2>&1 || true; done
  if [ "$HAD_GRANT" = "1" ] && [ -f "$GB" ]; then mv -f "$GB" "$GH"; fi
  if [ "$CREATED_GRANT" = "1" ]; then bash guard/grant.sh revoke >/dev/null 2>&1 || true; rm -f "$GH"; fi
}
trap cleanup EXIT

# E5 no residue: remember whether a grant was valid BEFORE any suite ran (K34)
bash guard/grant.sh status >/dev/null 2>&1
PRE_GRANT="$(bash guard/grant.sh status 2>/dev/null | jq -r '.valid' 2>/dev/null)"
[ "$PRE_GRANT" = "true" ] || PRE_GRANT=false

say "payload"
if ! bash scripts/bootstrap.sh --force >/dev/null 2>&1; then
  echo "FATAL: bootstrap failed"; exit 1
fi
VER="$(bash bin/wdiag 2>/dev/null | jq -r '.version // "?"')"
echo "payload version=$VER"

# ---------------------------------------------------------------- part A: regressions
# each suite prints its own SUMMARY; a suite counts as one check here
if [ "$ONLY_A" = "1" ]; then
say "A. regression suites (m1 / m2 / m3 / m4 / release)"
run_suite() {
  local name="$1" cmd="$2" out sum p f
  out="$(eval "$cmd" 2>&1)"
  sum="$(printf "%s" "$out" | grep -E '^SUMMARY' | tail -1)"
  p="$(printf "%s" "$sum" | sed -n 's/.*pass=\([0-9]*\).*/\1/p')"
  f="$(printf "%s" "$sum" | sed -n 's/.*fail=\([0-9]*\).*/\1/p')"
  if [ -z "$sum" ]; then
    bad "$name: no SUMMARY (tail: $(printf "%s" "$out" | tail -2 | tr '\n' ' '))"
  elif [ "${f:-1}" != "0" ]; then
    bad "$name: pass=${p:-?} fail=${f:-?} :: $(printf "%s" "$out" | grep -E '^FAIL' | head -3 | tr '\n' ' ')"
  else
    ok "$name: pass=$p fail=0"
  fi
}
run_suite "check-m1" "bash tests/check-m1.sh"
run_suite "check-m2" "bash tests/check-m2.sh"
run_suite "check-m3" "bash tests/check-m3.sh"
run_suite "check-m4" "bash tests/check-m4.sh"
case "$(bash scripts/check-release.sh 2>&1 | grep -E '^SUMMARY' | tail -1)" in
  *yes*) ok "check-release: pass=yes" ;;
  *) bad "check-release: $(bash scripts/check-release.sh 2>&1 | grep -E '^FAIL|^SUMMARY' | head -3 | tr '\n' ' ')" ;;
esac

fi

# E5: suites must not leave a live grant behind when there was none before
POST_GRANT="$(bash guard/grant.sh status 2>/dev/null | jq -r '.valid' 2>/dev/null)"
if [ "$PRE_GRANT" != "true" ] && [ "$POST_GRANT" = "true" ]; then
  bad "E5 residue: suites left a valid grant behind ($(bash guard/grant.sh status 2>/dev/null | jq -r '.note // "?"'))"
  bash guard/grant.sh revoke >/dev/null 2>&1
elif [ "$PRE_GRANT" != "true" ]; then
  ok "E5 no residue: no grant left behind by the suites"
fi

# ---------------------------------------------------------------- part B: E8 ten rounds
if [ "$ONLY_B" != "1" ]; then
printf "\nSUMMARY pass=%d fail=%d skip=%d\n" "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
fi
say "B. E8 ten consecutive end-to-end rounds (C8), each <60s"
DIAG="$(bash bin/wdiag 2>/dev/null || true)"
GUI=1; BR="n/a"
# NB: jq `//` treats false as empty, so `.desktop.secured // true` would yield true when UNLOCKED (K32).
# Use a plain read and treat "missing" as secured (fail closed).
SECURED="$(printf "%s" "$DIAG" | jq -r ".desktop.secured" 2>/dev/null)"
[ -z "$SECURED" ] || [ "$SECURED" = "null" ] && SECURED=true
# a transient lock/UAC state is common; poll up to 90s before giving up (red line: never act while locked)
for _ in $(seq 1 18); do
  [ "$SECURED" = "true" ] || break
  sleep 5
  DIAG="$(bash bin/wdiag 2>/dev/null || true)"
  SECURED="$(printf "%s" "$DIAG" | jq -r ".desktop.secured" 2>/dev/null)"
  [ -z "$SECURED" ] || [ "$SECURED" = "null" ] && SECURED=true
done
[ "$SECURED" = "true" ] && GUI=0
if [ "$GUI" = "1" ]; then
  bash bin/wshot --out "$SHOTS/m5-probe.png" >/dev/null 2>&1 || GUI=0
fi
if [ "$GUI" = "1" ]; then
  BR="$(python3 tests/helpers/brightness.py "$SHOTS/m5-probe.png" 2>/dev/null || echo 0)"
  case "$BR" in ""|*[!0-9.]*) BR=0 ;; esac
  if awk "BEGIN{exit !($BR < 8)}"; then GUI=0; fi
fi
echo "secured=$SECURED gui=$GUI brightness=$BR"

if [ "$GUI" != "1" ]; then
  skp "E8 ten rounds (desktop secured or display off)"
  printf "\nSUMMARY pass=%d fail=%d skip=%d\n" "$PASS" "$FAIL" "$SKIP"
  [ "$FAIL" -eq 0 ] && exit 0 || exit 1
fi

if [ -f "$GH" ]; then HAD_GRANT=1; cp -f "$GH" "$GB"; fi
if [ "$(bash guard/grant.sh status 2>/dev/null | jq -r '.valid // false')" != "true" ]; then
  bash guard/grant.sh issue --minutes 60 --scope input --note "tests/check-m5.sh：M5 全表回归 E8 十轮（用户 m00805 夜间授权）" >/dev/null 2>&1
  CREATED_GRANT=1
  echo "note: issued a 60-min test grant (revoked at exit)"
fi

. tests/helpers/e2e.sh
GREEN=0; MAXMS=0
for i in $(seq 1 10); do
  R="$(c8_once "r$i" "M5 回归第 $i 轮：中文 ✅" m5-c8)"
  MS="$(printf "%s" "$R" | awk "{print \$1}")"
  RES="$(printf "%s" "$R" | awk "{print \$2}")"
  case "$MS" in ''|*[!0-9]*) MS=999999 ;; esac
  [ "$MS" -gt "$MAXMS" ] && MAXMS="$MS"
  if [ "$RES" = "true" ] && [ "$MS" -lt 60000 ]; then
    GREEN=$((GREEN+1)); echo "  round $i: ${MS}ms PASS"
  else
    echo "  round $i: ${MS}ms FAIL $(printf "%s" "$R" | cut -d" " -f3-)"
  fi
done
if [ "$GREEN" = "10" ]; then ok "E8 10/10 rounds green (max ${MAXMS}ms)"; else bad "E8 $GREEN/10 rounds green"; fi

printf "\nSUMMARY pass=%d fail=%d skip=%d\n" "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
