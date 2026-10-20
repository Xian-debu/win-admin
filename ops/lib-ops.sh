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

# op_focus H - raise the target to the foreground before an input action (no synthetic input).
# Windows refuses clicks on occluded windows (winput assert), so composite ops activate first.
op_focus() {
  local h="$1" j
  j="$(bash "$REPO_DIR/bin/wwin" focus --hwnd "$h")" || {
    printf '%s\n' "$j"; return 1; }
  return 0
}

# op_pause_gate MODE - deny unless the grant covers it (mode read|input|write).
op_pause_gate() {
  local g rc
  g="$(bash "$REPO_DIR/guard/check.sh" "$1")"; rc=$?
  if [ $rc -ne 0 ]; then printf '%s\n' "$g"; exit $rc; fi
}
