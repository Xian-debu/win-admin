#!/usr/bin/env bash
# tests/check-m10.sh - M10/T5+T6 acceptance: wuia find by semantics (name/type/aid/class/enabled/on-screen/point)
# and act on one match (invoke/select/toggle/expand/collapse/focus/get-value/get-text/set-value) with read-back.
# Fixture: tests/helpers/uiawnd.ps1 - every control is named, and each interaction appends a line to
# uiawnd-events.txt, so every assertion here is about observable state, not about JSON shape alone.
set -uo pipefail
cd "$(dirname "$0")/.."
. "$(pwd)/lib/common.sh"

PASS=0; FAIL=0; SKIP=0
pass() { echo "PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
skip() { echo "SKIP  $1"; SKIP=$((SKIP+1)); }

WIN=/mnt/c/Users/Public/win-admin
G="$STATE_DIR/grant.json"
GBK="$STATE_DIR/grant.json.m10-test-bak"
JSONF="$WIN/tmp/uiawnd.json"
EV="$WIN/tmp/uiawnd-events.txt"
cleanup() {
  bash tests/helpers/uiawnd-stop.sh >/dev/null 2>&1
  if [ -f "$GBK" ]; then mv -f "$GBK" "$G"; else rm -f "$G"; fi
  rm -f "$STATE_DIR/uiawnd.pid"
}
trap cleanup EXIT

if [ -f "$G" ]; then cp "$G" "$GBK"; fi
bash guard/grant.sh issue --minutes 30 --scope shot,uia,input,file:read --note "tests/check-m10.sh 本机验收（UIA 控件夹具）" >/dev/null 2>&1 || true
bash tests/helpers/uiawnd-stop.sh >/dev/null 2>&1
sleep 0.5
TW="$(bash tests/helpers/uiawnd-start.sh 'wa-m10uia')"
if ! printf '%s' "$TW" | jq -e '.ok' >/dev/null 2>&1; then
  echo "FATAL: cannot launch fixture: $TW"; exit 1
fi
H="$(printf '%s' "$TW" | jq -r '.hwnd_dec')"
BX="$(printf '%s' "$TW" | jq -r '(.rects.btn.x + .rects.btn.w/2) | floor')"
BY="$(printf '%s' "$TW" | jq -r '(.rects.btn.y + .rects.btn.h/2) | floor')"

# ---- F1: find every named element in the window, bounded by --limit ----
F1="$(bin/wuia --hwnd "$H" --find-name '.' --limit 40)"
f1n="$(printf '%s' "$F1" | jq -r '.total')"
if printf '%s' "$F1" | jq -e '.ok == true and .mode == "find" and .total >= 12 and .count >= 12' >/dev/null 2>&1; then
  pass "F1 find by name '.' -> total=$f1n"
else
  fail "F1 find all: $(printf '%s' "$F1" | head -c 200)"
fi

# ---- F2: find by AutomationId; the result must advertise the Invoke pattern ----
F2="$(bin/wuia --hwnd "$H" --find-aid wa-btn)"
if printf '%s' "$F2" | jq -e '.total == 1 and .nodes[0].name == "BTN-COUNT" and (.nodes[0].patterns | index("Invoke") != null)' >/dev/null 2>&1; then
  pass "F2 find by aid: BTN-COUNT declares Invoke"
else
  fail "F2 find aid: $(printf '%s' "$F2" | head -c 200)"
fi

# ---- F3: find by control type returns every button (enabled and disabled) ----
F3="$(bin/wuia --hwnd "$H" --find-type Button)"
if printf '%s' "$F3" | jq -e '.total == 4 and ([.nodes[].name] | sort) == ["BTN-COUNT","BTN-DISABLED","CYCLE-0","删除"]' >/dev/null 2>&1; then
  pass "F3 find by type Button -> 4 buttons (incl. disabled and 删除)"
else
  fail "F3 find type: $(printf '%s' "$F3" | head -c 200)"
fi

# ---- F4: find by class name reaches the TextBox by its WPF class ----
# --find-class is a regex, so bare "TextBox" also matches "RichTextBox" (the wa-ro read-only
# editor added in v1.3). Anchor it; the unanchored behaviour is documented in K71.
F4="$(bin/wuia --hwnd "$H" --find-class '^TextBox$')"
if printf '%s' "$F4" | jq -e '.total == 1 and .nodes[0].aid == "wa-edit"' >/dev/null 2>&1; then
  pass "F4 find by class ^TextBox$ -> wa-edit"
else
  fail "F4 find class: $(printf '%s' "$F4" | head -c 200)"
fi

# ---- F5: --enabled drops the disabled button ----
F5="$(bin/wuia --hwnd "$H" --find-type Button --enabled)"
if printf '%s' "$F5" | jq -e '.total == 3 and ([.nodes[].name] | sort) == ["BTN-COUNT","CYCLE-0","删除"]' >/dev/null 2>&1; then
  pass "F5 --enabled filters BTN-DISABLED out (3 enabled buttons remain)"
else
  fail "F5 enabled filter: $(printf '%s' "$F5" | head -c 200)"
fi

# ---- F6: --on-screen drops the collapsed 'GHOST' element ----
F6="$(bin/wuia --hwnd "$H" --find-name GHOST --on-screen)"
F6B="$(bin/wuia --hwnd "$H" --find-name GHOST)"
if printf '%s' "$F6" | jq -e '.total == 0' >/dev/null 2>&1 && printf '%s' "$F6B" | jq -e '.total >= 1' >/dev/null 2>&1; then
  pass "F6 GT: GHOST is visible to find but excluded by --on-screen"
else
  fail "F6 on-screen filter: with=$(printf '%s' "$F6" | jq -r '.total') all=$(printf '%s' "$F6B" | jq -r '.total')"
fi

# ---- F7: probe a point and get the element that owns it ----
F7="$(bin/wuia --point "$BX,$BY")"
if printf '%s' "$F7" | jq -e --argjson x "$BX" --argjson y "$BY" '
     .ok == true and .element.name == "BTN-COUNT"
     and (.element.rect.x <= $x and $x <= .element.rect.x + .element.rect.w)
     and (.element.rect.y <= $y and $y <= .element.rect.y + .element.rect.h)' >/dev/null 2>&1; then
  pass "F7 point $BX,$BY -> BTN-COUNT (rect contains the point)"
else
  fail "F7 point probe: $(printf '%s' "$F7" | head -c 250)"
fi

# ---- F8: find/act argument and environment contracts ----
bin/wuia --hwnd "$H" --invoke >/dev/null 2>&1; f8a=$?
bin/wuia --hwnd "$H" --find-name NOPE --invoke >/dev/null 2>&1; f8b=$?
bin/wuia --hwnd "$H" --find-type Button --index 5 --invoke >/dev/null 2>&1; f8c=$?
if [ "$f8a" -eq 2 ] && [ "$f8b" -eq 3 ] && [ "$f8c" -eq 2 ]; then
  pass "F8 contracts: action without find rc=2, no match rc=3, bad index rc=2"
else
  fail "F8 contracts: $f8a/$f8b/$f8c (want 2/3/2)"
fi

# ---- A1/A2: invoke runs the handler twice; the counter proves two distinct injections ----
: > "$EV"
A1="$(bin/wuia --hwnd "$H" --find-aid wa-btn --invoke)"
A2="$(bin/wuia --hwnd "$H" --find-aid wa-btn --invoke)"
c1="$(grep -c '^click ' "$EV" 2>/dev/null || echo 0)"
last="$(grep '^click ' "$EV" 2>/dev/null | tail -1)"
if printf '%s' "$A1" | jq -e '.ok == true and .action == "invoke" and .injected == true' >/dev/null 2>&1 \
   && printf '%s' "$A2" | jq -e '.ok == true' >/dev/null 2>&1 && [ "$c1" = "2" ] && [ "$last" = "click 2" ]; then
  pass "A1/A2 invoke twice -> fixture counted click 2"
else
  fail "A1/A2 invoke: clicks=$c1 last='$last' ok=$(printf '%s' "$A1" | jq -r .ok)/$(printf '%s' "$A2" | jq -r .ok)"
fi

# ---- A3: set-value writes text (hostile characters included) and get-value reads it back ----
TXT="A1 中文 & \"q\" <b> \$HOME ;|"
A3="$(bin/wuia --hwnd "$H" --find-aid wa-edit --set-value "$TXT")"
A3B="$(bin/wuia --hwnd "$H" --find-aid wa-edit --get-value)"
got="$(printf '%s' "$A3B" | jq -r '.value // ""')"
if printf '%s' "$A3" | jq -e '.ok == true and .action == "set-value"' >/dev/null 2>&1 \
   && printf '%s' "$A3B" | jq -e '.ok == true and .action == "get-value" and .via == "value"' >/dev/null 2>&1 \
   && [ "$got" = "$TXT" ]; then
  pass "A3 set-value/get-value round-trip ($(printf '%s' "$got" | wc -c) bytes, hostile chars intact)"
else
  fail "A3 value round-trip: want='$TXT' got='$got' code=$(printf '%s' "$A3" | jq -r '.code // "-"')"
fi

# ---- A4/A5: toggle flips the check box and says which way ----
: > "$EV"
A4="$(bin/wuia --hwnd "$H" --find-aid wa-chk --toggle)"
s4="$(printf '%s' "$A4" | jq -r '.toggleState // ""')"
A5="$(bin/wuia --hwnd "$H" --find-aid wa-chk --toggle)"
s5="$(printf '%s' "$A5" | jq -r '.toggleState // ""')"
if [ "$s4" != "$s5" ] && [ -n "$s4" ] && [ -n "$s5" ] && [ "$(grep -c '^toggle ' "$EV")" -ge 2 ]; then
  pass "A4/A5 toggle: $s4 -> $s5 (fixture logged both)"
else
  fail "A4/A5 toggle: $s4 -> $s5 events=$(wc -l < "$EV" 2>/dev/null)"
fi

# ---- A6: select one list row and read the selection back ----
: > "$EV"
A6="$(bin/wuia --hwnd "$H" --find-name ROW-TWO --select)"
if printf '%s' "$A6" | jq -e '.ok == true and .action == "select" and .selected == true' >/dev/null 2>&1 \
   && grep -q '^row ROW-TWO$' "$EV"; then
  pass "A6 select ROW-TWO -> selected=true, SelectionChanged fired"
else
  fail "A6 select: $(printf '%s' "$A6" | head -c 200) events=$(tr '\n' ',' < "$EV" 2>/dev/null)"
fi

# ---- A7: focus moves keyboard focus into the edit box ----
A7="$(bin/wuia --hwnd "$H" --find-aid wa-edit --focus)"
if printf '%s' "$A7" | jq -e '.ok == true and .action == "focus" and .state.focused == true' >/dev/null 2>&1; then
  pass "A7 focus wa-edit -> focused=true"
else
  fail "A7 focus: $(printf '%s' "$A7" | head -c 200)"
fi

# ---- A8: get-text reads a label (TextPattern or its Name fallback) ----
A8="$(bin/wuia --hwnd "$H" --find-name LBL-TITLE --get-text)"
A8B="$(bin/wuia --hwnd "$H" --find-aid wa-edit --get-text)"
if printf '%s' "$A8" | jq -e '.ok == true and .value == "LBL-TITLE" and .via == "name"' >/dev/null 2>&1 \
   && printf '%s' "$A8B" | jq -e '.ok == true and .via == "text" and (.len >= 1)' >/dev/null 2>&1; then
  pass "A8 get-text: label via name, edit via TextPattern"
else
  fail "A8 get-text: label=$(printf '%s' "$A8" | jq -c '{ok,via,value}') edit=$(printf '%s' "$A8B" | jq -c '{ok,via,len}')"
fi

# ---- A9: a disabled control refuses injection with a deterministic code, not an opaque COM error ----
A9="$(bin/wuia --hwnd "$H" --find-name BTN-DISABLED --invoke 2>&1)"; rc9=$?
code9="$(printf '%s' "$A9" | jq -r '.code // ""' 2>/dev/null || true)"
if [ "$rc9" -eq 3 ] && [ "$code9" = "ENV_DISABLED" ]; then
  pass "A9 disabled button: ENV_DISABLED rc=3"
else
  fail "A9 disabled button: rc=$rc9 code=$code9"
fi

# ---- A10: expand/collapse on a combo box reports the state it read back ----
A10="$(bin/wuia --hwnd "$H" --find-aid wa-cbo --expand)"
A10B="$(bin/wuia --hwnd "$H" --find-aid wa-cbo --collapse)"
if printf '%s' "$A10" | jq -e '.ok == true and .expandState == "Expanded"' >/dev/null 2>&1 \
   && printf '%s' "$A10B" | jq -e '.ok == true and .expandState == "Collapsed"' >/dev/null 2>&1; then
  pass "A10 expand -> Expanded, collapse -> Collapsed"
else
  fail "A10 expand/collapse: $(printf '%s' "$A10" | jq -c '{ok,expandState}')/$(printf '%s' "$A10B" | jq -c '{ok,expandState}')"
fi

# ---- A11: no grant -> find is allowed (read-only) but every action is refused with rc=4 ----
rm -f "$G"
bin/wuia --hwnd "$H" --find-aid wa-btn >/dev/null 2>&1; a11a=$?
bin/wuia --hwnd "$H" --find-aid wa-btn --invoke >/dev/null 2>&1; a11b=$?
bin/wuia --hwnd "$H" --find-aid wa-edit --set-value x >/dev/null 2>&1; a11c=$?
if [ "$a11a" -eq 0 ] && [ "$a11b" -eq 4 ] && [ "$a11c" -eq 4 ]; then
  pass "A11 no grant: find rc=0, invoke rc=4, set-value rc=4"
else
  fail "A11 guard gate: find=$a11a invoke=$a11b setvalue=$a11c (want 0/4/4)"
fi

echo "-----"
echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
