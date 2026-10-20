#!/usr/bin/env bash
# lib/common.sh - shared helpers for the WSL-side CLI (P1).
# Contract: one JSON object on stdout, diagnostics on stderr, exit codes 0/2/3/4/5.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ROOT="${WINADMIN_APP_ROOT:-/mnt/c/Users/Public/win-admin}"
STATE_DIR="${WINADMIN_STATE_DIR:-$HOME/.dsh/win-admin}"
VERSION="$(cat "$REPO_DIR/VERSION" 2>/dev/null || echo unknown)"
export WINPS_TMPDIR="$APP_ROOT/tmp"

wa_err_json() { printf '{"ok":false,"code":"%s","msg":"%s"}\n' "$1" "$2"; }

wa_exit_for() {
  case "$1" in
    ARG*) exit 2 ;;
    ENV*|SESSION*|UAC*) exit 3 ;;
    GUARD*) exit 4 ;;
    *) exit 5 ;;
  esac
}

wa_app_dir() {
  local cur="$APP_ROOT/current.txt" v d
  [ -s "$cur" ] || return 1
  v="$(tr -d ' \r\n' < "$cur")"
  [ -n "$v" ] || return 1
  d="$APP_ROOT/app/$v"
  [ -d "$d" ] || return 1
  [ -f "$d/MANIFEST.sha256" ] || return 1
  printf '%s\n' "$d"
}

wa_require_app() {
  local d
  d="$(wa_app_dir)" || {
    wa_err_json ENV_NOT_INSTALLED "win-admin payload not installed; run: bash scripts/bootstrap.sh"
    exit 3
  }
  printf '%s\n' "$d"
}

wa_winpath() {
  printf '%s' "$1" | sed -e 's#^/mnt/c#C:#' -e 's#^/mnt/d#D:#' -e 's#^/mnt/e#E:#' -e 's#\\#/#g'
}

wa_wslpath() {
  printf '%s' "$1" | sed -e 's#^C:#/mnt/c#' -e 's#^D:#/mnt/d#' -e 's#^E:#/mnt/e#' -e 's#\\#/#g'
}

# Split "!pserr: ..." diagnostics from stdout, keep the JSON object line.
wa_json_of() {
  printf '%s\n' "$1" | grep -a -m1 '^{' || true
}

# wa_run <payload-name> [args...] -> prints JSON (or raw text), returns winps rc
wa_run() {
  local name="$1"; shift
  local app core
  app="$(wa_require_app)" || exit 3
  mkdir -p "$APP_ROOT/tmp" 2>/dev/null || true
  core="$(wa_winpath "$app/lib/wa-core.ps1")"
  winps -r -m 4000000 -t 120 -f "$app/$name.ps1" -Core "$core" "$@" 2>/dev/null
}

wa_finish() {
  local raw="$1" j code
  j="$(wa_json_of "$raw")"
  if [ -z "$j" ]; then
    printf '%s\n' "$raw" >&2
    wa_err_json EXEC_FAIL "no JSON from payload (see stderr)"
    exit 5
  fi
  printf '%s\n' "$j"
  if printf '%s' "$j" | jq -e '.ok == true' >/dev/null 2>&1; then
    exit 0
  fi
  code="$(printf '%s' "$j" | jq -r '.code // "EXEC_FAIL"' 2>/dev/null)"
  [ -n "$code" ] || code=EXEC_FAIL
  wa_exit_for "$code"
}

wa_guard_state() {
  local paused=false gp=false ge=""
  [ -f "$STATE_DIR/pause.flag" ] && paused=true
  if [ -f "$STATE_DIR/grant.json" ]; then
    gp=true
    ge="$(jq -r '.expires // ""' "$STATE_DIR/grant.json" 2>/dev/null || true)"
  fi
  printf '{"paused":%s,"grant_present":%s,"grant_expires":"%s","state_dir":"%s"}' \
    "$paused" "$gp" "$ge" "$STATE_DIR"
}
