#!/usr/bin/env bash
# harvest-cart.sh - 逐屏采集淘宝购物车渲染文本（只读，不点击商品）
set -u
cd /root/win-admin
HWND=593116
OUT="missions/taobao-cart-2026-10-21/raw"
mkdir -p "$OUT"
ROUNDS=${1:-24}
for i in $(seq 1 "$ROUNDS"); do
  bash bin/winput key ctrl+a --yes --expect-hwnd "$HWND" >/dev/null 2>&1
  sleep 0.35
  bash bin/winput key ctrl+c --yes --expect-hwnd "$HWND" >/dev/null 2>&1
  sleep 0.8
  bash bin/wclip get | jq -r '.text // ""' > "$OUT/sweep-$(printf %02d "$i").txt"
  printf 'round %02d bytes=%s hd=%s\n' "$i" "$(wc -c < "$OUT/sweep-$(printf %02d "$i").txt")" "$(head -c 40 "$OUT/sweep-$(printf %02d "$i").txt" | tr -d '\n')"
  bash bin/winput key escape --yes --expect-hwnd "$HWND" >/dev/null 2>&1
  bash bin/winput key pagedown --yes --expect-hwnd "$HWND" >/dev/null 2>&1
  sleep 0.6
done
