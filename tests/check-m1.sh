#!/usr/bin/env bash
# tests/check-m1.sh - M1 acceptance: engineering E1-E7 + capability C1/C1b/C2/C3.
# No mocks: every check runs against the live Windows desktop.
set -uo pipefail
. "$(dirname "$0")/../lib/common.sh"

pass=0; fail=0; skip=0
ok()   { printf 'PASS %-4s %s\n' "$1" "$2"; pass=$((pass+1)); }
no()   { printf 'FAIL %-4s %s\n' "$1" "$2"; fail=$((fail+1)); }
sk()   { printf 'SKIP %-4s %s\n' "$1" "$2"; skip=$((skip+1)); }
say()  { printf '\n-- %s\n' "$*"; }

# ---------- E1 commit discipline ----------
say "E1 commit discipline"
# Object may name more than one layer when one change spans them: "bin+ops: ..." (each part
# must still be a known object). Rule: <object(s)>: <what changed>
bad="$(git -C "$REPO_DIR" log --format=%s | awk '
  { if (index($0, ": ") == 0) { print $0; next }
    obj = substr($0, 1, index($0, ": ") - 1); n = split(obj, p, "+"); bad = 0
    for (i = 1; i <= n; i++) if (p[i] !~ /^(init|docs|probe|bin|ops|guard|test|fix|chore|release|auth|missions)$/) bad = 1
    if (bad) print $0 }' | head -3)"
[ -z "$bad" ] && ok E1 "all commit subjects carry a known prefix" || no E1 "bad subjects: $bad"

# ---------- E2 doc/bin sync ----------
say "E2 doc/bin sync"
missing=""
for f in "$REPO_DIR"/bin/*; do
  b="$(basename "$f")"
  grep -q "$b" "$REPO_DIR/docs/05-architecture.md" || missing="$missing $b"
done
[ -z "$missing" ] && ok E2 "every primitive appears in docs/05" || no E2 "undocumented:$missing"

# ---------- E3 --help ----------
say "E3 --help contract"
badh=""
for f in "$REPO_DIR"/bin/*; do
  out="$(bash "$f" --help 2>&1)"; rc=$?
  if [ $rc -ne 0 ] || [ -z "$out" ]; then badh="$badh $(basename "$f")"; fi
done
[ -z "$badh" ] && ok E3 "--help exits 0 with text for all primitives" || no E3 "help broken:$badh"

# ---------- E4 exit-code semantics ----------
say "E4 exit codes"
bash "$REPO_DIR/bin/wdiag" >/dev/null 2>&1; [ $? -eq 0 ] && ok E4a "wdiag ok -> 0" || no E4a "wdiag not 0"
bash "$REPO_DIR/bin/wshot" --rect 99999,0,10,10 >/dev/null 2>&1; [ $? -eq 2 ] && ok E4b "out-of-screen -> 2" || no E4b "wrong code for ARG"
bash "$REPO_DIR/bin/wuia" --hwnd 1 >/dev/null 2>&1; [ $? -eq 3 ] && ok E4c "bad hwnd -> 3" || no E4c "wrong code for ENV"
mkdir -p /tmp/wa-empty-state; WINADMIN_STATE_DIR=/tmp/wa-empty-state bash "$REPO_DIR/guard/check.sh" input >/dev/null 2>&1; [ $? -eq 4 ] && ok E4d "guard denies input without grant -> 4" || no E4d "wrong code for GUARD"
bash "$REPO_DIR/bin/wshot" --nonsense >/dev/null 2>&1; [ $? -eq 2 ] && ok E4e "unknown flag -> 2" || no E4e "wrong code for unknown flag"

# ---------- E6 timing ----------
say "E6 timing"
t0=$(date +%s%N); bash "$REPO_DIR/bin/wdiag" >/dev/null 2>&1; t1=$(date +%s%N)
ms=$(( (t1-t0)/1000000 )); [ "$ms" -lt 3000 ] && ok E6a "wdiag $ms ms < 3000" || no E6a "wdiag $ms ms"
t0=$(date +%s%N); bash "$REPO_DIR/bin/wshot" >/dev/null 2>&1; t1=$(date +%s%N)
ms=$(( (t1-t0)/1000000 )); [ "$ms" -lt 4000 ] && ok E6b "wshot $ms ms < 4000" || no E6b "wshot $ms ms"
t0=$(date +%s%N); bash "$REPO_DIR/bin/wwin" list >/dev/null 2>&1; t1=$(date +%s%N)
ms=$(( (t1-t0)/1000000 )); [ "$ms" -lt 3000 ] && ok E6c "wwin $ms ms < 3000" || no E6c "wwin $ms ms"

# ---------- E7 encoding ----------
say "E7 encoding"
cjk=0
j="$(bash "$REPO_DIR/bin/wwin" list)"
cjk="$(printf '%s' "$j" | jq -r '[.windows[].title | select(test("[\u4e00-\u9fa5]"))] | length' 2>/dev/null)"
[ -z "$cjk" ] && cjk=0
[ "$cjk" -ge 1 ] && ok E7 "CJK titles survived the bridge ($cjk windows)" || no E7 "no CJK titles: encoding broken"

# ---------- E5 residue ----------
say "E5 residue"
before="$(find "$APP_ROOT/tmp" -maxdepth 1 -name 'winps-*.ps1' 2>/dev/null | sort)"
bash "$REPO_DIR/bin/wdiag" >/dev/null 2>&1
bash "$REPO_DIR/bin/wwin" list >/dev/null 2>&1
after="$(find "$APP_ROOT/tmp" -maxdepth 1 -name 'winps-*.ps1' 2>/dev/null | sort)"
newres="$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep -v '^$' | head -3)"
[ -z "$newres" ] && ok E5 "no new winps temp scripts after 2 primitive calls" || no E5 "new residue: $newres"

# ---------- C1 physical-pixel screenshot ----------
say "C1 physical-pixel screenshot"
shot="$(bash "$REPO_DIR/bin/wshot")"
sp="$(printf '%s' "$shot" | jq -r .wsl_path)"
sw="$(printf '%s' "$shot" | jq -r .screen.w)"
sh="$(printf '%s' "$shot" | jq -r .screen.h)"
dims="$(python3 - "$sp" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read(33)
w, h = struct.unpack('>II', d[16:24])
print(w, h)
PY
)"
if [ "$dims" = "$sw $sh" ]; then ok C1 "PNG dims = $dims = screen"; else no C1 "PNG $dims != screen $sw x $sh"; fi
rm -f "$sp" 2>/dev/null || true

# ---------- C1b vision ----------
say "C1b vision channel"
bytes="$(printf '%s' "$shot" | jq -r .bytes)"
[ -z "$bytes" ] && bytes=0
[ "$bytes" -gt 50000 ] && ok C1b "screenshot bytes=$bytes (>50000, readable)" || no C1b "screenshot too small: $bytes"

# ---------- C2 UIA hwnd ----------
say "C2 UIA hwnd vs process MainWindowHandle"
started=""
hx="$(bash "$REPO_DIR/bin/wuia" --title 'Notepad' --depth 0 2>/dev/null | jq -r '.hwnd // empty')"
if [ -z "$hx" ]; then
  winps 'Start-Process notepad' >/dev/null 2>&1; started=1
  for i in 1 2 3 4 5; do sleep 1; hx="$(bash "$REPO_DIR/bin/wuia" --title 'Notepad' --depth 0 2>/dev/null | jq -r '.hwnd // empty')"; [ -n "$hx" ] && break; done
fi
if [ -n "$hx" ]; then
  dec="$((hx))"
  mh="$(winps "(Get-Process notepad -ErrorAction SilentlyContinue | Where-Object { \$_.MainWindowHandle -eq $dec } | Measure-Object).Count" 2>/dev/null | tr -d '[:space:]' | grep -o '[0-9]\+' | head -1)"
  [ -z "$mh" ] && mh=0
  [ "$mh" -ge 1 ] && ok C2 "wuia hwnd $hx matches notepad MainWindowHandle" || no C2 "hwnd $hx not found among notepad MainWindowHandle (mh=$mh)"
  [ -n "$started" ] && winps 'Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force' >/dev/null 2>&1
else
  no C2 "no notepad window found"
fi

# ---------- C3 UIA rect vs GetWindowRect ----------
say "C3 UIA rect vs window rect (<=2px)"
if [ -n "$hx" ]; then
  rect_uia="$(bash "$REPO_DIR/bin/wuia" --hwnd "$hx" --depth 0 | jq -r '.nodes[0].rect | [.x,.y,.w,.h] | map(tostring) | join(" ")')"
  rect_win="$(bash "$REPO_DIR/bin/wwin" list | jq -r --arg hx "$hx" '.windows[] | select(.hwnd==$hx) | [.rect.x,.rect.y,.rect.w,.rect.h] | map(tostring) | join(" ")' | head -1)"
  if printf '%s' "$rect_uia" | grep -q null; then
    # A minimized window gets (-32000,-32000) from GetWindowRect and a NULL BoundingRectangle
    # from UIA: there is no rect to compare, so this is not a failure (K36).
    sk C3 "target window is minimized (UIA rect null) - no geometry to compare"
  elif [ -n "$rect_win" ]; then
    read -r ux uy uw uh <<< "$rect_uia"
    read -r wx wy ww wh <<< "$rect_win"
    # K36 (v1.1 expansion): a minimized window reports (-32000,-32000) from GetWindowRect; UIA may
    # return a NULL rect OR an all-zero one depending on the toolkit. Either way there is no
    # geometry to compare -- decide on the *window* side marker, not on the UIA shape.
    if [ "$wx" -le -30000 ] || [ "$wy" -le -30000 ]; then
      sk C3 "target window is minimized (win rect -32000) - no geometry to compare"
    else
      dx=$(( ux>wx ? ux-wx : wx-ux )); dy=$(( uy>wy ? uy-wy : wy-uy ))
      dw=$(( uw>ww ? uw-ww : ww-uw )); dh=$(( uh>wh ? uh-wh : wh-uh ))
      if [ "$dx" -le 2 ] && [ "$dy" -le 2 ] && [ "$dw" -le 2 ] && [ "$dh" -le 2 ]; then
        ok C3 "uia[$rect_uia] vs win[$rect_win]"
      else
        no C3 "uia[$rect_uia] vs win[$rect_win] (d=$dx,$dy,$dw,$dh)"
      fi
    fi
  else
    no C3 "hwnd $hx not in wwin list"
  fi
else
  no C3 "no target window"
fi

# ---------- out of scope for M1 ----------
say "out of scope (M2/M3)"
for c in C4 C5 C6 C7 C8 S1 S2 S3 S4 S5 S6 S7 S8 E8; do sk "$c" "not M1"; done

printf '\nSUMMARY pass=%s fail=%s skip=%s\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]