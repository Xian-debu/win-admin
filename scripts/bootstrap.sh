#!/usr/bin/env bash
# scripts/bootstrap.sh - deploy the Windows-side payload (P2) from this repo (P1) and smoke-test it.
# Idempotent per version: repeated runs reuse app/<version>/ unless --force.
set -uo pipefail
. "$(dirname "$0")/../lib/common.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
V="$(cat "$REPO/VERSION" 2>/dev/null || echo unknown)"
APP_ROOT="${WINADMIN_APP_ROOT:-/mnt/c/Users/Public/win-admin}"
LOG_DIR="$APP_ROOT/logs"
TS="$(date +%Y%m%d-%H%M%S)"

CHECK_ONLY=0
FORCE=0
for a in "$@"; do
  case "$a" in
    --check) CHECK_ONLY=1 ;;
    --force) FORCE=1 ;;
    *) echo "unknown arg: $a" >&2; exit 2 ;;
  esac
done

info() { printf '[bootstrap] %s\n' "$*"; }
fail() { printf '[bootstrap] FAIL %s\n' "$*"; exit 1; }

# 1. environment checks (never mutate anything in --check mode)
[ -d /mnt/c ] || fail "not a WSL machine with /mnt/c mounted"
command -v winps >/dev/null 2>&1 || fail "winps not found in PATH (see docs/02 section 4)"
command -v jq >/dev/null 2>&1 || fail "jq not found in PATH"
[ -x /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe ] || fail "powershell.exe not reachable"
mkdir -p "$APP_ROOT/tmp" 2>/dev/null || true
[ -d "$APP_ROOT/tmp" ] || fail "$APP_ROOT is not writable"
info "env ok: version=$V app_root=$APP_ROOT"

if [ "$CHECK_ONLY" = 1 ]; then
  info "SMOKE SKIP (--check)"
  info "PASS"
  exit 0
fi

mkdir -p "$APP_ROOT/app" "$APP_ROOT/shots" "$LOG_DIR"
LOG="$LOG_DIR/install-$TS.log"
: > "$LOG"

DEST="$APP_ROOT/app/$V"
if [ -d "$DEST" ] && [ "$FORCE" = 0 ]; then
  info "reusing existing payload at $DEST (use --force to overwrite)"
else
  rm -rf "$DEST"
  mkdir -p "$DEST"
  cp -a "$REPO/win/." "$DEST/" || fail "copy to $DEST failed"
  info "copied payload -> $DEST"
fi

# 2. manifest: hash every payload file, then verify what actually landed
( cd "$REPO/win" && find . -type f | sed 's|^\./||' | sort | while IFS= read -r f; do
    printf '%s  %s\n' "$(sha256sum "$REPO/win/$f" | cut -d' ' -f1)" "$f"
  done ) > "$DEST/MANIFEST.sha256"
[ -s "$DEST/MANIFEST.sha256" ] || fail "manifest empty"

bad=0
while IFS= read -r line; do
  h="${line%% *}"
  rel="${line#*  }"
  [ -f "$DEST/$rel" ] || { printf '[bootstrap] MISSING %s\n' "$rel"; bad=1; continue; }
  got="$(sha256sum "$DEST/$rel" | cut -d' ' -f1)"
  if [ "$got" != "$h" ]; then printf '[bootstrap] MISMATCH %s\n' "$rel"; bad=1; fi
done < "$DEST/MANIFEST.sha256"
[ "$bad" = 0 ] || fail "integrity check failed; current.txt left untouched"
info "integrity ok: $(wc -l < "$DEST/MANIFEST.sha256") files verified" | tee -a "$LOG"

# 3. switch pointer only after integrity passes
printf '%s\n' "$V" > "$APP_ROOT/current.txt"
info "current.txt -> $V" | tee -a "$LOG"

# 4. smoke: the deployed payload must answer wdiag with its own version
smoke="$(bash "$REPO/bin/wdiag" 2>/dev/null)"
if ! printf '%s' "$smoke" | jq -e '.ok == true' >/dev/null 2>&1; then
  printf '%s\n' "$smoke" | tee -a "$LOG"
  fail "wdiag smoke test failed"
fi
smoke_v="$(printf '%s' "$smoke" | jq -r '.version')"
[ "$smoke_v" = "$V" ] || fail "smoke version mismatch: payload says $smoke_v, repo says $V"
info "smoke: version=$smoke_v screen=$(printf '%s' "$smoke" | jq -c '.screen')" | tee -a "$LOG"
printf '%s\n' "$smoke" >> "$LOG"
info "SMOKE PASS"
