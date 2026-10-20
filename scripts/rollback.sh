#!/usr/bin/env bash
# scripts/rollback.sh - switch current.txt to another installed payload version. Never deletes files.
set -uo pipefail
. "$(dirname "$0")/../lib/common.sh"

APP_ROOT="${WINADMIN_APP_ROOT:-/mnt/c/Users/Public/win-admin}"
CUR_FILE="$APP_ROOT/current.txt"

list_versions() { ls -1 "$APP_ROOT/app" 2>/dev/null | sort -V; }

cur="$(cat "$CUR_FILE" 2>/dev/null || true)"

case "${1:-}" in
  -h|--help|'')
    echo "usage: rollback.sh --previous | <version> | --list"
    echo "installed: $(list_versions | tr '\n' ' ')"
    [ -n "$cur" ] && echo "current: $cur"
    exit 0 ;;
  --list) list_versions; exit 0 ;;
  --previous)
    target="$(list_versions | grep -v -x "$cur" | tail -1)"
    [ -n "$target" ] || { echo "no other version installed" >&2; exit 2; } ;;
  *) target="$1" ;;
esac

DEST="$APP_ROOT/app/$target"
[ -d "$DEST" ] || { echo "version not installed: $target" >&2; exit 2; }
[ -f "$DEST/MANIFEST.sha256" ] || { echo "incomplete install: $DEST" >&2; exit 1; }

printf '%s\n' "$target" > "$CUR_FILE"
printf '[rollback] current.txt: %s -> %s\n' "${cur:-none}" "$target"
bash "$(dirname "$0")/../bin/wdiag" >/dev/null 2>&1 && echo "[rollback] smoke ok" || { echo "[rollback] smoke FAILED" >&2; exit 1; }
