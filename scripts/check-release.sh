#!/usr/bin/env bash
# scripts/check-release.sh - static release gate (E9) + red-line grep (S8, D14).
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
V="$(cat "$REPO/VERSION")"
fail=0
pass() { printf 'PASS %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

# 1. version single source of truth
first="$(grep -m1 -E '^## \[' "$REPO/CHANGELOG.md" | sed -E 's/^## \[([^]]+)\].*/\1/')"
[ "$V" = "$first" ] && pass "VERSION == CHANGELOG head ($V)" || bad "VERSION=$V but CHANGELOG head=$first"

# 2. required deployment files
for f in VERSION LICENSE CHANGELOG.md THIRD_PARTY_NOTICES.md docs/10-deployment.md docs/11-known-issues.md \
         scripts/bootstrap.sh scripts/rollback.sh scripts/uninstall.sh scripts/build-release.sh; do
  [ -s "$REPO/$f" ] && pass "exists $f" || bad "missing $f"
done

# 3. payload scripts must set UTF-8 before doing anything (K1)
# v1.1/v1.3: param blocks grow with new switches, so the UTF-8 assertion looks at the first 60 lines
# (still before any payload work: every script sets it right after param()).
for f in "$REPO"/win/*.ps1; do
  h="$(head -60 "$f")"
  if printf '%s' "$h" | grep -q 'OutputEncoding'; then
    pass "utf8 first lines: $(basename "$f")"
  elif printf '%s' "$h" | grep -q 'wa-core.ps1'; then
    pass "utf8 via core: $(basename "$f")"
  else
    bad "no OutputEncoding: $(basename "$f")"
  fi
done

# 4. input-injection keywords only inside the sanctioned primitives (D14: M1 passed, M2 authorized)
hits="$(grep -rn -E 'SendInput|mouse_event|keybd_event|SendKeys|SetCursorPos' "$REPO/bin" "$REPO/lib" "$REPO/win" "$REPO/guard" 2>/dev/null | grep -v -E '^.*/(bin|win)/winput(\.ps1)?:' | grep -v -E '/bin/winput:' || true)"
[ -z "$hits" ] && pass "injection keywords confined to winput (D14)" || bad "input-injection keywords outside winput: $hits"

# 5. every primitive answers --help with exit 0
for f in "$REPO"/bin/*; do
  bash "$f" --help >/dev/null 2>&1 && pass "help ok: $(basename "$f")" || bad "help failed: $(basename "$f")"
done

# 6. forbidden weasel phrases in docs (docs/08)
weasel="$(grep -rn -E '一般来说|应该没问题|基本可用' "$REPO/docs" 2>/dev/null | grep -v -E '禁止|不写|视为' || true)"
[ -z "$weasel" ] && pass "no weasel phrases" || bad "weasel phrases: $weasel"

echo "SUMMARY pass=$([ "$fail" = 0 ] && echo yes || echo no)"
[ "$fail" = 0 ] || exit 1
echo "PASS"
