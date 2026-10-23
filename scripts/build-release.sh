#!/usr/bin/env bash
# scripts/build-release.sh - reproducible archives: P1 (tar.gz) + P2 (zip) + SHA256SUMS.
set -uo pipefail
. "$(dirname "$0")/../lib/common.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
V="$(cat "$REPO/VERSION")"
EPOCH="$(git -C "$REPO" log -1 --format=%ct 2>/dev/null || echo 0)"
DIST="$REPO/dist"

cd "$REPO" || exit 1
rm -rf "$DIST"
mkdir -p "$DIST"

# K45: git quotes non-ASCII paths (C-style) unless core.quotepath=false; tar cannot stat those
# quoted names. Read NUL-separated names instead of word-splitting quoted output.
mapfile -d '' -t FILES < <(git -c core.quotepath=false ls-files -z | grep -zv -E '^(dist/|tests/reports/tmp)' )
[ "${#FILES[@]}" -gt 0 ] || { echo "no tracked files" >&2; exit 1; }

LIST="$(mktemp)"
trap 'rm -f "$LIST"' EXIT
printf '%s\0' "${FILES[@]}" > "$LIST"

tar --null --no-recursion --sort=name --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner \
    -czf "$DIST/win-admin-$V.tar.gz" -T "$LIST" || exit 1

python3 - "$REPO" "$V" "$EPOCH" "$DIST" <<'PY'
import os, sys, zipfile
repo, v, epoch, dist = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
root = os.path.join(repo, 'win')
out = os.path.join(dist, 'win-admin-win-%s.zip' % v)
names = []
for base, _, files in os.walk(root):
    for f in files:
        p = os.path.join(base, f)
        names.append(os.path.relpath(p, root).replace(os.sep, '/'))
names.sort()
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for n in names:
        zi = zipfile.ZipInfo(n, date_time=(1980, 1, 1, 0, 0, 0))
        zi.compress_type = zipfile.ZIP_DEFLATED
        zi.external_attr = 0o644 << 16
        with open(os.path.join(root, n), 'rb') as fh:
            z.writestr(zi, fh.read())
print('zip: %d files' % len(names))
PY

( cd "$DIST" && sha256sum ./*.tar.gz ./*.zip > SHA256SUMS )
echo "[release] dist:"
ls -l "$DIST"
cat "$DIST/SHA256SUMS"
