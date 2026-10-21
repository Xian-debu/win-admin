#!/usr/bin/env bash
# sweep-page.sh - 采集当前购物车分页的渲染文本（100% 缩放，逐屏 Ctrl+A/Ctrl+C）
set -u
cd /root/win-admin
HWND=593116
OUT="${2:-missions/taobao-cart-2026-10-21/raw/p1}"
ROUNDS=${1:-20}
mkdir -p "$OUT"
for i in $(seq 1 "$ROUNDS"); do
  f="$OUT/round-$(printf %02d "$i").txt"
  bash bin/winput key ctrl+a --yes --expect-hwnd "$HWND" >/dev/null 2>&1
  sleep 0.3
  bash bin/winput key ctrl+c --yes --expect-hwnd "$HWND" >/dev/null 2>&1
  sleep 0.7
  bash bin/wclip get | jq -r '.text // ""' | tr -d '\r' > "$f"
  items="$(grep -c '^移入收藏$' "$f" || true)"
  tail_marker=0; grep -q '猜你喜欢' "$f" && tail_marker=1
  printf 'round %02d items=%s guess_you_like=%s\n' "$i" "$items" "$tail_marker"
  bash bin/winput key escape --yes --expect-hwnd "$HWND" >/dev/null 2>&1
  bash bin/winput key pagedown --yes --expect-hwnd "$HWND" >/dev/null 2>&1
  sleep 0.5
done
