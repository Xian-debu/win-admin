#!/usr/bin/env bash
# tests/helpers/e2e.sh - one full end-to-end round shared by check-m4 / check-m5.
# Requires: repo root as cwd, lib/common.sh already sourced (wa_run/audit), a valid grant,
# and WIN_TMP pointing at the Windows-visible temp dir.
# c8_once TAG TEXT [PREFIX] -> echoes "<ms> <true|false> [reason]"; leaves no window behind.
c8_once() {
  local tag="$1" text="$2" prefix="${3:-m4-c8}"
  local f="C:\\Users\\Public\\win-admin\\tmp/${prefix}-${tag}.txt" wf="$WIN_TMP/${prefix}-${tag}.txt"
  local t0 h o fo content
  rm -f "$wf"; : > "$wf"
  t0=$(date +%s%3N)
  o="$(bash ops/open --exe notepad --args "$f" --title "${prefix}-${tag}" --timeout 10 --yes 2>&1)" || true
  h="$(printf "%s" "$o" | jq -r ".window.hwnd_dec // 0" 2>/dev/null || echo 0)"
  if [ "$h" = "0" ] || [ "$h" = "null" ] || [ -z "$h" ]; then
    echo "$(( $(date +%s%3N) - t0 )) false open:$(printf "%s" "$o" | head -c 200)"; return 1
  fi
  OPENED="${OPENED:-} $h"
  fo="$(bash ops/fill --hwnd "$h" --name "文本编辑器" --text "$text" --yes 2>&1)" || true
  if [ "$(printf "%s" "$fo" | jq -r ".matches // false" 2>/dev/null)" != "true" ]; then
    echo "$(( $(date +%s%3N) - t0 )) false fill:$(printf "%s" "$fo" | head -c 200)"; bash bin/wwin close --hwnd "$h" >/dev/null 2>&1; return 1
  fi
  bash bin/winput key ctrl+s --expect-hwnd "$h" --yes >/dev/null 2>&1 || true
  sleep 0.8
  content="$(cat "$wf" 2>/dev/null || true)"
  if [ "$content" != "$text" ]; then
    echo "$(( $(date +%s%3N) - t0 )) false file:[$content]"; bash bin/wwin close --hwnd "$h" >/dev/null 2>&1; return 1
  fi
  bash bin/wwin close --hwnd "$h" >/dev/null 2>&1 || true
  sleep 0.6
  if bash bin/wwin info --hwnd "$h" >/dev/null 2>&1; then
    echo "$(( $(date +%s%3N) - t0 )) false close:window-still-open"; return 1
  fi
  echo "$(( $(date +%s%3N) - t0 )) true"
}
