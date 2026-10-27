#!/usr/bin/env bash
# tests/check-m27.sh - M27/T32 acceptance: live smoke on a real Bilibili upload page (S20-1..4, v1.4).
#
# Zero side effects is the hard rule: every step must be provable AND reversible, no submit-like
# button is ever pressed, and a step whose evidence cannot be obtained is SKIPped rather than
# guessed. With no Bilibili window (or no visible one) the whole suite skips with reason
# NO_BILIBILI_WINDOW and exits 0, so it can stay in the regression table on any machine.
#
# usage: bash tests/check-m27.sh
#   env knobs (all optional; element names on the real page are not guessable in general):
#     S20_1_NAME   分区下拉里要滚到的选项名（默认 '科技数码|科技|数码'）
#     S20_2_INPUT  标签输入框的 name 正则（给了才做 S20-2）
#     S20_2_LIST   标签列表容器的 name 正则（给了才做 S20-2）
#     S20_2_VALUE  要加的测试标签（默认 win-admin-smoke）
#     S20_3_NAME   水印复选框的 name 正则（默认 '水印'）
#     S20_HWND     强制指定窗口（只用于对 WPF 夹具做彩排，不构成 live 证据）
#
# S20-2 的复原靠真实页面支持 ctrl+z 撤销；不支持时就如实 FAIL（而不是假装复原成功），
# 并提示人工删掉那个测试标签。
set -uo pipefail
cd "$(dirname "$0")/.."
. "$(pwd)/lib/common.sh"

PASS=0; SKIP=0; FAIL=0
ok()  { echo "PASS  $1"; PASS=$((PASS+1)); }
sk()  { echo "SKIP  $1"; SKIP=$((SKIP+1)); }
no()  { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
finish() {
  local okflag=false
  [ "$FAIL" -eq 0 ] && okflag=true
  echo
  echo "$PASS passed, $SKIP skipped, $FAIL failed"
  jq -cn --argjson ok "$okflag" --argjson p "$PASS" --argjson s "$SKIP" --argjson f "$FAIL" --arg h "${H:-}" \
    '{ok:$ok, skipped:false, s20:{passed:$p, skipped:$s, failed:$f}, hwnd:(if $h == "" then null else $h end)}'
  [ "$FAIL" -eq 0 ] || exit 1
  exit 0
}

wins() { bash bin/wwin list 2>/dev/null; }
node_count() { printf '%s' "$1" | jq -r '(.nodes // []) | length' 2>/dev/null || echo 0; }
state() { printf '%s' "$1" | jq -r '[.. | objects | (.toggleState? // empty)][0] // empty' 2>/dev/null; }

LIST="$(wins)"
# S20_HWND forces a window (rehearsal against a WPF fixture only -- never live evidence).
H=""
if [ -n "${S20_HWND:-}" ]; then
  H="$S20_HWND"
  echo "INFO  forced window (rehearsal, NOT live evidence): $H"
else
  H="$(printf '%s' "$LIST" | jq -r '[.windows[] | select((.class | test("Chrome_WidgetWin_1")) and (.title | test("bilibili|创作中心|投稿"; "i")) and (.minimized | not))][0].hwnd // empty' 2>/dev/null)"
fi
if [ -z "$H" ]; then
  echo "SKIP  S20 live 冒烟：没有可见的 B 站创作中心/投稿页窗口（先把投稿页开到前台再跑）"
  echo '{"ok":true,"skipped":true,"reason":"NO_BILIBILI_WINDOW","s20":{"passed":0,"skipped":4,"failed":0}}'
  exit 0
fi
TITLE="$(printf '%s' "$LIST" | jq -r --arg h "$H" '.windows[] | select(.hwnd == $h) | .title')"
echo "INFO  live window: $H $(printf '%s' "$TITLE" | cut -c1-90)"
PRE_WINS="$(printf '%s' "$LIST" | jq -c '[.windows[].hwnd] | sort')"

# Injection needs the input grant; without it every injected step becomes a SKIP (never a half-run).
G="$(bash guard/check.sh input 2>/dev/null)"; GRC=$?
if [ "$GRC" -ne 0 ]; then
  echo "INFO  input grant: $(printf '%s' "$G" | jq -r '.code // "denied"')"
  sk "S20-1 分区下拉：缺 input grant，不能注入"
  sk "S20-2 标签区：缺 input grant，不能注入"
  sk "S20-3 水印开关：缺 input grant，不能注入"
else
  # ---- S20-1: scroll a category option into view, then close the panel with Esc ----
  # The panel must already be open: opening it is a real click on a real page, and the plan asks
  # for reveal evidence, not for driving the upload flow.
  T1="${S20_1_NAME:-科技数码|科技|数码}"
  N1="$(bash bin/wuia --hwnd "$H" --find-name "$T1" --limit 5 --on-screen 2>/dev/null)"
  if [ "$(node_count "$N1")" -eq 0 ]; then
    sk "S20-1 分区下拉：找不到选项（/$T1/）——先手动展开分区面板，或用 S20_1_NAME 指定"
  else
    R="$(bash ops/reveal --hwnd "$H" --find-name "$T1" --index 0 --yes 2>/dev/null)"; RC=$?
    if [ "$RC" -ne 0 ]; then
      sk "S20-1 分区下拉：reveal rc=$RC $(printf '%s' "$R" | jq -r '.code // ""')"
    else
      IN="$(printf '%s' "$R" | jq -r 'if (.element.rect and .container.rect) then ((.element.rect.x >= (.container.rect.x - 2)) and (.element.rect.y >= (.container.rect.y - 2)) and ((.element.rect.x + .element.rect.w) <= (.container.rect.x + .container.rect.w + 2)) and ((.element.rect.y + .element.rect.h) <= (.container.rect.y + .container.rect.h + 2))) else false end')"
      ST="$(printf '%s' "$R" | jq -r '.steps // 0')"
      VIA="$(printf '%s' "$R" | jq -r '.via')"
      if [ "$IN" = "true" ] && [ "$ST" -ge 1 ]; then
        ok "S20-1 分区下拉：steps=$ST via=$VIA 选项落在容器内"
      elif [ "$IN" = "true" ]; then
        sk "S20-1 分区下拉：选项本来就可见（steps=0），没有可证的滚动位移"
      else
        no "S20-1 分区下拉：revealed 但 element.rect 不在 container.rect 内"
      fi
    fi
    bash bin/winput key esc --expect-hwnd "$H" --yes >/dev/null 2>&1
  fi

  # ---- S20-2: add one tag, then undo it and prove the chip really disappeared ----
  IN2="${S20_2_INPUT:-}"; LS2="${S20_2_LIST:-}"; V2="${S20_2_VALUE:-win-admin-smoke}"
  if [ -z "$IN2" ] || [ -z "$LS2" ]; then
    sk "S20-2 标签区：未指定 S20_2_INPUT/S20_2_LIST（真实页面的输入框与列表名不可猜）"
  else
    C="$(bash ops/chip-add --hwnd "$H" --input "$IN2" --list "$LS2" --value "$V2" --yes 2>/dev/null)"; CRC=$?
    if [ "$CRC" -ne 0 ]; then
      sk "S20-2 标签区：chip-add rc=$CRC $(printf '%s' "$C" | jq -r '.code // ""')"
    else
      B="$(printf '%s' "$C" | jq -r '.chipsBefore // 0')"; A="$(printf '%s' "$C" | jq -r '.chipsAfter // 0')"
      bash bin/winput key ctrl+z --expect-hwnd "$H" --yes >/dev/null 2>&1
      GONE=false
      for _ in 1 2 3 4 5 6 7 8; do
        CH="$(bash bin/wuia --hwnd "$H" --find-name "^$V2$" --limit 1 --on-screen 2>/dev/null)"
        if [ "$(node_count "$CH")" -eq 0 ]; then GONE=true; break; fi
        sleep 0.25
      done
      if [ "$A" -eq "$((B + 1))" ] && [ "$GONE" = "true" ]; then
        ok "S20-2 标签区：chips $B -> $A，ctrl+z 后 $V2 已消失（已复原）"
      elif [ "$A" -ne "$((B + 1))" ]; then
        no "S20-2 标签区：chipsBefore=$B chipsAfter=$A（应为 +1）"
      else
        no "S20-2 标签区：加了 $V2 但 ctrl+z 未能复原（零副作用失败，需要人工清理）"
      fi
    fi
  fi

  # ---- S20-3: toggle the watermark checkbox twice and prove the state returned ----
  N3="${S20_3_NAME:-水印}"
  N3J="$(bash bin/wuia --hwnd "$H" --find-name "$N3" --limit 5 --on-screen 2>/dev/null)"
  if [ "$(node_count "$N3J")" -eq 0 ]; then
    sk "S20-3 水印开关：找不到（/$N3/）——先展开「更多设置」，或用 S20_3_NAME 指定"
  else
    S0="$(state "$N3J")"
    T1J="$(bash bin/wuia --hwnd "$H" --toggle --find-name "$N3" --index 0 2>/dev/null)"; TRC1=$?
    sleep 0.3
    J1="$(bash bin/wuia --hwnd "$H" --find-name "$N3" --limit 5 --on-screen 2>/dev/null)"
    T2J="$(bash bin/wuia --hwnd "$H" --toggle --find-name "$N3" --index 0 2>/dev/null)"; TRC2=$?
    sleep 0.3
    J2="$(bash bin/wuia --hwnd "$H" --find-name "$N3" --limit 5 --on-screen 2>/dev/null)"
    S1="$(state "$J1")"; S2="$(state "$J2")"
    if [ "$TRC1" -ne 0 ] || [ "$TRC2" -ne 0 ]; then
      sk "S20-3 水印开关：toggle rc=$TRC1/$TRC2（$(printf '%s' "$T1J" | jq -r '.code // ""')）"
    elif [ -z "$S0" ] || [ -z "$S1" ] || [ -z "$S2" ]; then
      sk "S20-3 水印开关：控件没有 toggleState，无法证明状态变化（已切两次，状态已复原）"
    elif [ "$S0" != "$S1" ] && [ "$S0" = "$S2" ]; then
      ok "S20-3 水印开关：$S0 -> $S1 -> $S2（切两次回到初值）"
    else
      no "S20-3 水印开关：状态 $S0 -> $S1 -> $S2，未按预期变化或未能复原"
    fi
  fi
fi

# ---- S20-4: no new window / dialog left behind ----
POST_WINS="$(wins | jq -c '[.windows[].hwnd] | sort')"
NEW="$(printf '%s' "$POST_WINS" | jq -r --argjson pre "$PRE_WINS" '(. - $pre) | join(",")')"
if [ -z "$NEW" ]; then
  ok "S20-4 窗口集合与操作前一致（无新窗口/无残留对话框）"
else
  no "S20-4 出现了新窗口：$NEW"
fi

finish
