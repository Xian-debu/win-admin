#!/usr/bin/env bash
# tests/check-m16.sh - M16 acceptance: wuia cold/warm tree reliability + adaptive depth (T20, v1.3)
# Covers: N1 cold first look finds a depth-23 element with no --depth; N2 diagnostic fields;
#         N3 --no-warm stops the retries (warmRetries=0); N4 default depth >= the element's;
#         N5 explicit --depth 12 auto-deepens and hits; N6 --no-deepen leaves it unfound;
#         N7 warm-tree find under the 5 s budget; N8 tree JSON carries the same diagnostics;
#         N9 lazy DOM: retries until the content appears; N10 --no-warm does not;
#         N11 live smoke on the user's browser (WINADMIN_LIVE=1 only).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 5
PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL %s  [%s]\n' "$1" "$2"; }
skip() { SKIP=$((SKIP+1)); printf 'SKIP %s  [%s]\n' "$1" "$2"; }
TMP="/mnt/c/Users/Public/win-admin/tmp"
mkdir -p "$TMP"
cleanup() { bash tests/helpers/deepwin-stop.sh >/dev/null 2>&1; }
trap cleanup EXIT

# jq helper: compact diagnostic subset for failure messages
diag() { printf '%s' "$1" | jq -c '{ok,total,passes,warmRetries,warmMs,depthUsed,deepened,code}'; }
num()  { printf '%s' "$1" | jq -r ".$2 // empty"; }

# --- fixture A: static deep tree (22 nested GroupBoxes, leaf at UIA depth 23) -------------
bash tests/helpers/deepwin-stop.sh >/dev/null 2>&1
OUT="$(bash tests/helpers/deepwin-start.sh wa-deep 2>/dev/null)"
if [ "$(printf %s "$OUT" | jq -r .ok 2>/dev/null)" != "true" ]; then
  echo "fixture failed to start: $OUT"; exit 5
fi
H="$(printf %s "$OUT" | jq -r .hwnd_dec)"

# N1 (E16-1) cold first look, no --depth/--max: the depth-23 leaf must be found
J="$(bash bin/wuia --hwnd "$H" --find-name '^深层按钮$' 2>/dev/null)"
T="$(num "$J" total)"
if [ "$(printf %s "$J" | jq -r .ok)" = "true" ] && [ -n "$T" ] && [ "$T" -ge 1 ]; then
  ok "N1 cold first look finds '深层按钮' without --depth (total=$T)"
else
  bad "N1 cold first look" "$(diag "$J")"
fi

# N2 (E16-2) diagnostics present and in range
P="$(num "$J" passes)"; WM="$(num "$J" warmMs)"; DU="$(num "$J" depthUsed)"; WR="$(num "$J" warmRetries)"
if [ -n "$P" ] && [ "$P" -ge 1 ] && [ "$P" -le 3 ] && [ -n "$WM" ] && [ "$WM" -ge 0 ] \
   && [ -n "$DU" ] && [ -n "$WR" ] && printf '%s' "$J" | jq -e 'has("deepened")' >/dev/null; then
  ok "N2 diagnostics passes=$P warmMs=$WM depthUsed=$DU warmRetries=$WR"
else
  bad "N2 diagnostics incomplete" "$(diag "$J")"
fi

# N3 (E16-2b) --no-warm: no retries (passes may still be 2 because of auto-deepen)
J="$(bash bin/wuia --hwnd "$H" --no-warm --find-aid deep-btn 2>/dev/null)"
WR="$(num "$J" warmRetries)"; T="$(num "$J" total)"
if [ "$WR" = "0" ] && [ -n "$T" ] && [ "$T" -ge 1 ] && [ "$(printf %s "$J" | jq -r .ok)" = "true" ]; then
  ok "N3 --no-warm keeps warmRetries=0 (passes=$(num "$J" passes))"
else
  bad "N3 --no-warm" "$(diag "$J")"
fi

# N4 (E16-3) the element really is deep, and the default depth reached it
D="$(printf '%s' "$J" | jq -r '.nodes[0].depth // empty')"
DU="$(num "$J" depthUsed)"
if [ -n "$D" ] && [ "$D" -ge 22 ] && [ -n "$DU" ] && [ "$DU" -ge "$D" ]; then
  ok "N4 element depth=$D <= depthUsed=$DU"
else
  bad "N4 element vs depthUsed" "depth=$D depthUsed=$DU"
fi

# N5 (E16-4a) explicit shallow --depth 12 still hits via one auto-deepen
J="$(bash bin/wuia --hwnd "$H" --depth 12 --find-aid deep-btn 2>/dev/null)"
T="$(num "$J" total)"
if [ "$(printf %s "$J" | jq -r .deepened)" = "true" ] && [ -n "$T" ] && [ "$T" -ge 1 ]; then
  ok "N5 --depth 12 auto-deepened and found (depthUsed=$(num "$J" depthUsed))"
else
  bad "N5 auto-deepen" "$(diag "$J")"
fi

# N6 (E16-4b) --no-deepen leaves it unfound, and does not claim to have deepened
J="$(bash bin/wuia --hwnd "$H" --depth 12 --no-deepen --find-aid deep-btn 2>/dev/null)"
T="$(num "$J" total)"
if [ "$(printf %s "$J" | jq -r .deepened)" = "false" ] && [ "$T" = "0" ]; then
  ok "N6 --depth 12 --no-deepen: total=0 deepened=false (passes=$(num "$J" passes))"
else
  bad "N6 --no-deepen" "$(diag "$J")"
fi

# N7 (E16-5) warm-tree find (deepening included) inside the 5 s budget
S0="$(date +%s%N)"
bash bin/wuia --hwnd "$H" --find-aid deep-btn >/dev/null 2>&1
RC=$?
S1="$(date +%s%N)"
MS=$(( (S1 - S0) / 1000000 ))
if [ "$RC" = "0" ] && [ "$MS" -le 5000 ]; then
  ok "N7 warm-tree find took ${MS}ms (<= 5000ms)"
else
  bad "N7 warm-tree timing" "rc=$RC ms=$MS"
fi

# N8 tree JSON carries the same diagnostics and a >= 23 depth
J="$(bash bin/wuia --hwnd "$H" --depth 40 2>/dev/null)"
if printf '%s' "$J" | jq -e '.ok and .count >= 40 and .depth == .depthUsed and .passes >= 1 and (.warmRetries != null) and (.warmMs != null)' >/dev/null 2>&1; then
  ok "N8 tree: count=$(num "$J" count) depth=depthUsed=$(num "$J" depthUsed) passes=$(num "$J" passes) warmRetries=$(num "$J" warmRetries)"
else
  bad "N8 tree diagnostics" "$(printf '%s' "$J" | jq -c '{count,depth,depthUsed,passes,warmRetries,warmMs,code}')"
fi

# --- fixture B: DOM that appears late (4 s) ----------------------------------------------
bash tests/helpers/deepwin-stop.sh >/dev/null 2>&1
OUT="$(bash tests/helpers/deepwin-start.sh wa-deep lazy 4000 2>/dev/null)"
if [ "$(printf %s "$OUT" | jq -r .ok 2>/dev/null)" != "true" ]; then
  echo "lazy fixture failed to start: $OUT"; exit 5
fi
H="$(printf %s "$OUT" | jq -r .hwnd_dec)"

# N9 warm retries until the late content shows up
J="$(bash bin/wuia --hwnd "$H" --find-name '延迟出现' --warm-passes 12 --warm-ms 300 2>/dev/null)"
T="$(num "$J" total)"; P="$(num "$J" passes)"; WR="$(num "$J" warmRetries)"
if [ "$(printf %s "$J" | jq -r .ok)" = "true" ] && [ -n "$T" ] && [ "$T" -ge 1 ] \
   && [ -n "$WR" ] && [ "$WR" -ge 1 ] && [ -n "$P" ] && [ "$P" -ge 3 ]; then
  ok "N9 warm retries reach late DOM (total=$T passes=$P warmRetries=$WR warmMs=$(num "$J" warmMs))"
else
  bad "N9 warm retries" "$(diag "$J")"
fi

# N10 --no-warm does not retry, so the late DOM stays invisible in one look
bash tests/helpers/deepwin-stop.sh >/dev/null 2>&1
OUT="$(bash tests/helpers/deepwin-start.sh wa-deep lazy 8000 2>/dev/null)"
H="$(printf %s "$OUT" | jq -r .hwnd_dec)"
J="$(bash bin/wuia --hwnd "$H" --no-warm --find-name '延迟出现' --warm-passes 12 --warm-ms 300 2>/dev/null)"
T="$(num "$J" total)"; WR="$(num "$J" warmRetries)"
if [ "$T" = "0" ] && [ "$WR" = "0" ]; then
  ok "N10 --no-warm sees nothing yet (total=0 warmRetries=0)"
else
  bad "N10 --no-warm late DOM" "$(diag "$J")"
fi

# N11 live smoke: the user's own browser, read-only (WINADMIN_LIVE=1)
if [ "${WINADMIN_LIVE:-0}" = "1" ]; then
  EH="$(bash bin/wwin list 2>/dev/null | jq -r '.windows[] | select(.title | test("Microsoft Edge")) | .hwnd_dec' | head -1)"
  if [ -z "$EH" ] || [ "$EH" = "null" ]; then
    skip "N11 live find-type Edit" "no Edge window open"
  else
    J="$(bash bin/wuia --hwnd "$EH" --find-type ControlType.Edit 2>/dev/null)"
    T="$(num "$J" total)"
    if [ "$(printf %s "$J" | jq -r .ok)" = "true" ] && [ -n "$T" ] && [ "$T" -ge 1 ]; then
      ok "N11 live Edge find-type Edit total=$T depthUsed=$(num "$J" depthUsed) warmRetries=$(num "$J" warmRetries)"
    else
      bad "N11 live Edge find-type Edit" "$(diag "$J")"
    fi
  fi
else
  skip "N11 live find-type Edit" "set WINADMIN_LIVE=1 to run"
fi

printf "\n%s passed, %s failed, %s skipped\n" "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" = "0" ] || exit 1
exit 0
