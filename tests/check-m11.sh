#!/usr/bin/env bash
# tests/check-m11.sh - M11/T7+T8 acceptance: ops/click-element (semantic act + verify),
# ops/wait-uia (predicate polling), ops/hover-menu (reach hover-only items).
# Fixtures: uiawnd (named controls, click counter, cycle button) and menutwin (hover-only submenu).
set -uo pipefail
cd "$(dirname "$0")/.."
. "$(pwd)/lib/common.sh"

PASS=0; FAIL=0; SKIP=0
pass() { echo "PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
skip() { echo "SKIP  $1"; SKIP=$((SKIP+1)); }

WIN=/mnt/c/Users/Public/win-admin
G="$STATE_DIR/grant.json"
GBK="$STATE_DIR/grant.json.m11-test-bak"
UJ="$WIN/tmp/uiawnd.json"
UEV="$WIN/tmp/uiawnd-events.txt"
MJ="$WIN/tmp/menutwin.json"
MMENU="$WIN/tmp/menutwin-menu.txt"
cleanup() {
  bash tests/helpers/uiawnd-stop.sh >/dev/null 2>&1
  bash tests/helpers/menutwin-stop.sh >/dev/null 2>&1
  if [ -f "$GBK" ]; then mv -f "$GBK" "$G"; else rm -f "$G"; fi
  rm -f "$STATE_DIR/uiawnd.pid" "$STATE_DIR/menutwin.pid"
}
trap cleanup EXIT

if [ -f "$G" ]; then cp "$G" "$GBK"; fi
bash guard/grant.sh issue --minutes 30 --scope shot,uia,input,file:read --note "tests/check-m11.sh 本机验收（ops 复合操作）" >/dev/null 2>&1 || true
bash tests/helpers/uiawnd-stop.sh >/dev/null 2>&1
bash tests/helpers/menutwin-stop.sh >/dev/null 2>&1
sleep 0.5
UW="$(bash tests/helpers/uiawnd-start.sh 'wa-m11uia')"
MW="$(bash tests/helpers/menutwin-start.sh 'wa-m11menu')"
if ! printf '%s' "$UW" | jq -e '.ok' >/dev/null 2>&1; then echo "FATAL: uiawnd fixture: $UW"; exit 1; fi
if ! printf '%s' "$MW" | jq -e '.ok' >/dev/null 2>&1; then echo "FATAL: menutwin fixture: $MW"; exit 1; fi
UH="$(printf '%s' "$UW" | jq -r '.hwnd_dec')"
MH="$(printf '%s' "$MW" | jq -r '.hwnd_dec')"
MX="$(printf '%s' "$MW" | jq -r '(.menu.root.x + .menu.root.w/2) | floor')"
MY="$(printf '%s' "$MW" | jq -r '(.menu.root.y + .menu.root.h/2) | floor')"

# ---- N15: click-element dry-run injects nothing; the real run invokes once and verifies ----
: > "$UEV"
D15="$(ops/click-element --hwnd "$UH" --aid wa-btn)"
n_after_dry="$(grep -c '^click ' "$UEV" 2>/dev/null || true)"; [ -n "$n_after_dry" ] || n_after_dry=0
R15="$(ops/click-element --hwnd "$UH" --aid wa-btn --yes)"
n_after_real="$(grep -c '^click ' "$UEV" 2>/dev/null || true)"; [ -n "$n_after_real" ] || n_after_real=0
if printf '%s' "$D15" | jq -e '.ok == true and .dry_run == true and .strategy == "invoke"' >/dev/null 2>&1 \
   && [ "$n_after_dry" = "0" ] \
   && printf '%s' "$R15" | jq -e '.ok == true and .injected == true and .action == "invoke" and .verify == "alive"' >/dev/null 2>&1 \
   && [ "$n_after_real" = "1" ]; then
  pass "N15 click-element: dry-run silent, real run invoked once (counter 1)"
else
  fail "N15 click-element: dry=$n_after_dry real=$n_after_real code=$(printf '%s' "$R15" | jq -r '.code // "-"')"
fi

# ---- N16: --verify value:RE proves an observable state change (Name changes on click) ----
R16="$(ops/click-element --hwnd "$UH" --aid wa-cycle --yes --verify 'value:CYCLE-1')"
R16B="$(ops/click-element --hwnd "$UH" --aid wa-cycle --yes --verify 'value:CYCLE-2')"
if printf '%s' "$R16" | jq -e '.ok == true and .verify == "value:CYCLE-1" and .verdict.value == "CYCLE-1"' >/dev/null 2>&1 \
   && printf '%s' "$R16B" | jq -e '.ok == true and .verdict.value == "CYCLE-2"' >/dev/null 2>&1; then
  pass "N16 click-element verify: CYCLE-1 then CYCLE-2 observed after two clicks"
else
  fail "N16 verify: $(printf '%s' "$R16" | jq -c '{ok,code,verdict}') / $(printf '%s' "$R16B" | jq -c '{ok,code,verdict}')"
fi

# ---- N17: a failed verification is reported as ENV_TIMEOUT, not as success ----
R17="$(ops/click-element --hwnd "$UH" --aid wa-cycle --yes --verify 'value:NEVER' --timeout 700 2>&1)"; rc17=$?
code17="$(printf '%s' "$R17" | jq -r '.code // ""' 2>/dev/null || true)"
if [ "$rc17" -eq 3 ] && [ "$code17" = "ENV_TIMEOUT" ]; then
  pass "N17 verification miss -> ENV_TIMEOUT rc=3"
else
  fail "N17 verification miss: rc=$rc17 code=$code17"
fi

# ---- N18: wait-uia returns immediately for an already-true predicate ----
S18="$(date +%s%3N)"
W18="$(ops/wait-uia --hwnd "$UH" --aid wa-btn --timeout 5000)"; rc18=$?
E18="$(date +%s%3N)"; ms18=$(( E18 - S18 ))
if [ "$rc18" -eq 0 ] && printf '%s' "$W18" | jq -e '.ok == true and .count >= 1' >/dev/null 2>&1 && [ "$ms18" -lt 3000 ]; then
  pass "N18 wait-uia already-true predicate returned in ${ms18} ms"
else
  fail "N18 wait-uia: rc=$rc18 ms=$ms18 $(printf '%s' "$W18" | head -c 150)"
fi

# ---- N19: wait-uia --value waits for a value the app writes (set-value then wait) ----
bin/wuia --hwnd "$UH" --find-aid wa-edit --set-value 'WAIT-OK-77' >/dev/null 2>&1
W19="$(ops/wait-uia --hwnd "$UH" --aid wa-edit --value 'WAIT-OK-[0-9]+' --timeout 3000)"; rc19=$?
W19B="$(ops/wait-uia --hwnd "$UH" --aid wa-edit --value 'WRONG' --timeout 600 2>&1)"; rc19b=$?
if [ "$rc19" -eq 0 ] && printf '%s' "$W19" | jq -e '.value_seen == "WAIT-OK-77"' >/dev/null 2>&1 \
   && [ "$rc19b" -eq 3 ] && printf '%s' "$W19B" | jq -e '.code == "ENV_TIMEOUT"' >/dev/null 2>&1; then
  pass "N19 wait-uia value: matched WAIT-OK-77, timed out on WRONG (rc=3)"
else
  fail "N19 wait-uia value: rc=$rc19/$rc19b seen=$(printf '%s' "$W19" | jq -r '.value_seen // "-"')"
fi

# ---- N20: hover-menu reaches an item that only exists while hovered ----
D20="$(ops/hover-menu --hwnd "$MH" --at "$MX,$MY" --pick 'SUB-ONE')"
R20="$(ops/hover-menu --hwnd "$MH" --at "$MX,$MY" --pick 'SUB-ONE' --yes)"
vis20="$(jq -r '.menu.visible' "$MJ" 2>/dev/null)"
if printf '%s' "$D20" | jq -e '.ok == true and .dry_run == true' >/dev/null 2>&1 \
   && printf '%s' "$R20" | jq -e '.ok == true and .injected == true and .node.name == "SUB-ONE"' >/dev/null 2>&1 \
   && [ "$vis20" = "true" ] && [ -s "$MMENU" ]; then
  pass "N20 hover-menu: hover revealed SUB-ONE and acted on it ($(wc -l < "$MMENU") menu events)"
else
  fail "N20 hover-menu: dry=$(printf '%s' "$D20" | jq -r .ok) real=$(printf '%s' "$R20" | jq -c '{ok,code,node:.node.name}') visible=$vis20"
fi

# ---- N21: hover-menu on a name that never appears -> ENV_MENU_NOT_SHOWN ----
R21="$(ops/hover-menu --hwnd "$MH" --at "$MX,$MY" --pick 'SUB-NEVER' --timeout 600 --yes 2>&1)"; rc21=$?
code21="$(printf '%s' "$R21" | jq -r '.code // ""' 2>/dev/null || true)"
if [ "$rc21" -eq 3 ] && [ "$code21" = "ENV_MENU_NOT_SHOWN" ]; then
  pass "N21 missing hover item -> ENV_MENU_NOT_SHOWN rc=3"
else
  fail "N21 missing hover item: rc=$rc21 code=$code21"
fi

# ---- N22: argument contracts for the three ops ----
ops/click-element --hwnd "$UH" >/dev/null 2>&1; c22a=$?
ops/click-element --hwnd "$UH" --aid wa-btn --strategy bogus >/dev/null 2>&1; c22b=$?
ops/click-element --hwnd "$UH" --aid wa-btn --verify bogus >/dev/null 2>&1; c22c=$?
ops/wait-uia --hwnd "$UH" >/dev/null 2>&1; c22d=$?
ops/wait-uia --hwnd "$UH" --aid wa-edit --value x --gone >/dev/null 2>&1; c22e=$?
ops/hover-menu --hwnd "$MH" --pick x >/dev/null 2>&1; c22f=$?
if [ "$c22a" -eq 2 ] && [ "$c22b" -eq 2 ] && [ "$c22c" -eq 2 ] && [ "$c22d" -eq 2 ] && [ "$c22e" -eq 2 ] && [ "$c22f" -eq 2 ]; then
  pass "N22 arg contracts: all six bad invocations exit 2"
else
  fail "N22 arg contracts: $c22a/$c22b/$c22c/$c22d/$c22e/$c22f (want all 2)"
fi

# ---- N24: S9 destructive-name guard (default refuse, --allow-danger overrides) ----
CE24="$(ops/click-element --hwnd "$UH" --aid wa-danger --yes 2>/dev/null)"; c24=$?
if [ "$c24" -eq 3 ] && [ "$(printf %s "$CE24" | jq -r .code)" = "ENV_DANGEROUS_ACTION" ]; then
  pass "N24 dangerous node refused: ENV_DANGEROUS_ACTION rc=3"
else
  fail "N24 danger guard: rc=$c24 code=$(printf %s "$CE24" | jq -r .code)"
fi
CE24b="$(ops/click-element --hwnd "$UH" --aid wa-danger --allow-danger --yes 2>/dev/null)"; c24b=$?
if [ "$c24b" -eq 0 ] && printf %s "$CE24b" | jq -e ".ok == true" >/dev/null; then
  pass "N24b --allow-danger permits the same node"
else
  fail "N24b --allow-danger: rc=$c24b $(printf %s "$CE24b" | jq -c "{code}")"
fi

# ---- N25: C11 disabled element -> ENV_ELEMENT_NOT_ACTIONABLE (not "not found") ----
CE25="$(ops/click-element --hwnd "$UH" --aid wa-disabled --yes 2>/dev/null)"; c25=$?
if [ "$c25" -eq 3 ] && [ "$(printf %s "$CE25" | jq -r .code)" = "ENV_ELEMENT_NOT_ACTIONABLE" ]; then
  pass "N25 disabled element -> ENV_ELEMENT_NOT_ACTIONABLE rc=3"
else
  fail "N25 disabled element: rc=$c25 code=$(printf %s "$CE25" | jq -r .code)"
fi

# ---- N26: dry-run still lets a dangerous node be inspected (no refusal before the preview) ----
CE26="$(ops/click-element --hwnd "$UH" --aid wa-danger 2>/dev/null)"; c26=$?
if [ "$c26" -eq 0 ] && printf %s "$CE26" | jq -e ".dry_run == true" >/dev/null; then
  pass "N26 dry-run previews dangerous node without acting"
else
  fail "N26 dry-run dangerous preview: rc=$c26"
fi

# ---- N27: auto-deepen contract (docs/18) ----
# Shallow fixture: normal hit must report deepened=false; a real miss must still be ENV_NO_NODE
# (after one deeper retry), not silently "not found" at the shallow depth.
CE27="$(ops/click-element --hwnd "$UH" --aid wa-btn 2>/dev/null)"
CE27b="$(ops/click-element --hwnd "$UH" --name 'no-such-node-xyz' 2>/dev/null)"; c27b=$?
if printf '%s' "$CE27" | jq -e '.ok == true and .deepened == false' >/dev/null 2>&1 \
   && [ "$c27b" -eq 3 ] && [ "$(printf %s "$CE27b" | jq -r .code)" = "ENV_NO_NODE" ]; then
  pass "N27 auto-deepen: shallow hit deepened=false, miss -> ENV_NO_NODE rc=3"
else
  fail "N27 auto-deepen: hit=$(printf '%s' "$CE27" | jq -c '{ok,deepened}') miss rc=$c27b code=$(printf %s "$CE27b" | jq -r .code)"
fi

# ---- N23: no grant -> the acting ops are refused with rc=4 ----
rm -f "$G"
ops/click-element --hwnd "$UH" --aid wa-btn --yes >/dev/null 2>&1; c23a=$?
ops/hover-menu --hwnd "$MH" --at "$MX,$MY" --pick 'SUB-ONE' --yes >/dev/null 2>&1; c23b=$?
ops/wait-uia --hwnd "$UH" --aid wa-btn --timeout 1000 >/dev/null 2>&1; c23c=$?
if [ "$c23a" -eq 4 ] && [ "$c23b" -eq 4 ] && [ "$c23c" -eq 0 ]; then
  pass "N23 no grant: click-element rc=4, hover-menu rc=4, wait-uia (read-only) rc=0"
else
  fail "N23 guard gate: $c23a/$c23b/$c23c (want 4/4/0)"
fi

echo "-----"
echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
