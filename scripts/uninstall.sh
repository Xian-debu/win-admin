#!/usr/bin/env bash
# scripts/uninstall.sh - remove the Windows-side payload directory.
# Keeps WSL-side state ($HOME/.dsh/win-admin: grants, pause flag, audit) unless --purge-state.
set -uo pipefail
. "$(dirname "$0")/../lib/common.sh"

APP_ROOT="${WINADMIN_APP_ROOT:-/mnt/c/Users/Public/win-admin}"
YES=0; PURGE=0
for a in "$@"; do
  case "$a" in
    --yes) YES=1 ;;
    --purge-state) PURGE=1 ;;
    -h|--help) echo "usage: uninstall.sh --yes [--purge-state]"; exit 0 ;;
    *) echo "unknown arg: $a" >&2; exit 2 ;;
  esac
done
[ "$YES" = 1 ] || { echo "refusing to delete $APP_ROOT without --yes"; exit 2; }
[ -d "$APP_ROOT" ] || { echo "nothing to uninstall at $APP_ROOT"; exit 0; }

echo "[uninstall] removing $APP_ROOT"
rm -rf "$APP_ROOT" || exit 1
echo "[uninstall] done"

if [ "$PURGE" = 1 ] && [ -d "$STATE_DIR" ]; then
  echo "[uninstall] removing state $STATE_DIR"
  rm -rf "$STATE_DIR"
else
  [ -d "$STATE_DIR" ] && echo "[uninstall] kept state at $STATE_DIR (grants/audit)"
fi
