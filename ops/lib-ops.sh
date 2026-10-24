#!/usr/bin/env bash
# ops/lib-ops.sh - shared helpers for composite operations (M4).
# Contract kept identical to primitives: one JSON object on stdout, exit 0/2/3/4/5.

op_die() { printf '{"ok":false,"code":"%s","msg":"%s"}\n' "$1" "$2"; wa_exit_for "$1"; }

# Resolve a target window: --hwnd wins, else --title regex over wwin list.
op_resolve_hwnd() {
  local hwnd="$1" title="$2" j h
  if [ "$hwnd" != "0" ]; then printf '%s\n' "$hwnd"; return 0; fi
  [ -n "$title" ] || op_die ARG_NEED_TARGET "pass --hwnd or --title"
  j="$(bash "$REPO_DIR/bin/wwin" list)" || op_die ENV_WIN_LIST "wwin list failed"
  h="$(printf '%s' "$j" | jq -r --arg t "$title" '[.windows[] | select(.title | test($t))][0].hwnd_dec // empty')"
  [ -n "$h" ] || op_die ENV_NO_WINDOW "no window matching title: $title"
  printf '%s\n' "$h"
}

# op_find_node H NAME_RE TYPE_FILTER INDEX DEPTH MAX -> node JSON (empty if none)
op_find_node() {
  local h="$1" name="$2" typ="$3" idx="$4" depth="$5" max="$6" j
  j="$(bash "$REPO_DIR/bin/wuia" --hwnd "$h" --depth "$depth" --max "$max")" || return 1
  printf '%s' "$j" | jq -c --arg n "$name" --arg t "$typ" --argjson i "$idx" '
    [.nodes[]
     | select(.rect.w > 0 and .rect.h > 0)
     | select(.offscreen == false)
     | select(.enabled == true)
     | select(($n == "") or (.name | test($n)))
     | select(($t == "") or (.type | test($t)))
    ][$i] // empty'
}

# op_window_sig H -> "state\tx\ty\tw\th" (rectNormal): a comparable placement fingerprint.
# rectNormal (not rect) is the right field: a maximized window's GetWindowRect is the off-screen
# border rect, so geometry alone cannot tell maximized from maximized-but-moved.
op_window_sig() {
  local j
  j="$(bash "$REPO_DIR/bin/wwin" state --hwnd "$1")" || return 1
  printf '%s' "$j" | jq -r '[.window.state, .window.rectNormal.x, .window.rectNormal.y, .window.rectNormal.w, .window.rectNormal.h] | @tsv'
}

OP_FOCUS_CODE=""; OP_FOCUS_MSG=""; OP_FOCUS_AFTER=""

# op_focus H - raise the target to the foreground before an input action (no synthetic input).
# Windows refuses clicks on occluded windows (winput assert), so composite ops activate first.
# v1.2 (T12/E13): activation must be a no-op on the window's placement. Before T12 the inner
# Set-WaForeground called ShowWindow(SW_RESTORE), which un-maximized the target and silently
# invalidated every coordinate the caller had just screenshotted (docs/19 F3, K49). We now
# fingerprint placement before/after and fail closed with ENV_STATE_CHANGED if it moved.
# Exception: a freshly restored minimized window legitimately changes state - that is what
# focus is for, so the guard only applies when the window was not minimized.
op_focus() {
  local h="$1" j after
  OP_FOCUS_CODE=""; OP_FOCUS_MSG=""; OP_FOCUS_AFTER=""
  local before
  before="$(op_window_sig "$h" 2>/dev/null)" || before=""
  j="$(bash "$REPO_DIR/bin/wwin" focus --hwnd "$h")" || {
    OP_FOCUS_CODE="$(printf '%s' "$j" | jq -r '.code // "ENV_NOT_FOREGROUND"' 2>/dev/null)"
    OP_FOCUS_CODE="${OP_FOCUS_CODE:-ENV_NOT_FOREGROUND}"
    OP_FOCUS_MSG="could not bring hwnd $h to the foreground"
    printf '%s\n' "$j"; return 1; }
  if [ -n "$before" ]; then
    case "$before" in
      minimized*) return 0 ;;
    esac
    after="$(op_window_sig "$h" 2>/dev/null)" || after=""
    OP_FOCUS_AFTER="$after"
    if [ -n "$after" ] && [ "$after" != "$before" ]; then
      OP_FOCUS_CODE=ENV_STATE_CHANGED
      OP_FOCUS_MSG="focus changed the window placement (before '$before' after '$after')"
      printf '{"ok":false,"code":"ENV_STATE_CHANGED","msg":"focus changed the window placement","hwnd":%s,"before":"%s","after":"%s"}\n' "$h" "$before" "$after"
      return 1
    fi
  fi
  return 0
}

# op_pause_gate MODE - deny unless the grant covers it (mode read|input|write).
op_pause_gate() {
  local g rc
  g="$(bash "$REPO_DIR/guard/check.sh" "$1")"; rc=$?
  if [ $rc -ne 0 ]; then printf '%s\n' "$g"; exit $rc; fi
}
