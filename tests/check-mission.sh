#!/usr/bin/env bash
# tests/check-mission.sh - mission 协议（docs/13）自测：状态机、证据强制、恢复点。
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. lib/common.sh

PASS=0; FAIL=0; SKIP=0
ok()  { PASS=$((PASS+1)); printf 'PASS  %s\n' "$*"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$*"; }
say() { printf '\n== %s\n' "$*"; }

MID="__selftest__"
cleanup() { rm -rf "missions/$MID" /tmp/mission-ev.txt /tmp/mission-resume.json; }
trap cleanup EXIT
cleanup

say "M1 init creates plan.json with empty steps"
OUT="$(bash bin/wmission init "$MID" --title "自测 mission")"; RC=$?
if [ "$RC" = "0" ] && [ "$(printf '%s' "$OUT" | jq -r .ok)" = "true" ] && [ -f "missions/$MID/plan.json" ] && [ "$(jq '.steps|length' "missions/$MID/plan.json")" = "0" ]; then ok "init ok"; else bad "init rc=$RC out=$OUT"; fi

say "M2 duplicate init refuses (protect evidence)"
bash bin/wmission init "$MID" --title "again" >/dev/null 2>&1; RC=$?
if [ "$RC" = "3" ]; then ok "duplicate init rc=3"; else bad "duplicate init rc=$RC"; fi

say "M3 add numbers steps from 1"
bash bin/wmission add "$MID" --title "第一步" >/dev/null
OUT="$(bash bin/wmission add "$MID" --title "第二步" --verify "true")"
if [ "$(printf '%s' "$OUT" | jq -r .step)" = "2" ] && [ "$(jq '.steps|length' "missions/$MID/plan.json")" = "2" ]; then ok "add step=2"; else bad "add: $OUT"; fi

say "M4 done without evidence is refused"
bash bin/wmission start "$MID" 1 >/dev/null
bash bin/wmission done "$MID" 1 >/dev/null 2>&1; RC=$?
if [ "$RC" = "2" ] && [ "$(jq -r '.steps[0].status' "missions/$MID/plan.json")" = "running" ]; then ok "done without --evidence rc=2"; else bad "done w/o evidence rc=$RC"; fi

say "M5 done with evidence + file copies into evidence/"
printf 'artifact %s\n' "$(date +%s)" > /tmp/mission-ev.txt
OUT="$(bash bin/wmission done "$MID" 1 --evidence "写了一个证据文件" --file /tmp/mission-ev.txt)"; RC=$?
if [ "$RC" = "0" ] && [ -f "missions/$MID/evidence/s1-mission-ev.txt" ] && [ "$(jq -r '.steps[0].status' "missions/$MID/plan.json")" = "done" ]; then ok "done copies evidence"; else bad "done rc=$RC out=$OUT"; fi

say "M6 resume points at the next pending step"
OUT="$(bash bin/wmission resume "$MID")"
if [ "$(printf '%s' "$OUT" | jq -r .next_step)" = "2" ] && [ "$(printf '%s' "$OUT" | jq -r .status)" = "pending" ]; then ok "resume next_step=2"; else bad "resume: $OUT"; fi

say "M7 three failures escalate instead of looping"
for i in 1 2 3; do bash bin/wmission start "$MID" 2 >/dev/null 2>&1; bash bin/wmission fail "$MID" 2 --reason "fail-$i" >/dev/null; done
bash bin/wmission resume "$MID" >/tmp/mission-resume.json 2>&1; RC=$?
if [ "$RC" = "3" ] && [ "$(jq -r .code /tmp/mission-resume.json)" = "ESCALATE" ]; then ok "3 failures -> ESCALATE rc=3"; else bad "escalate rc=$RC out=$(cat /tmp/mission-resume.json)"; fi

say "M8 log.jsonl is append-only with one event per transition"
N="$(wc -l < "missions/$MID/log.jsonl")"
EVENTS="$(jq -r .event "missions/$MID/log.jsonl" | sort | uniq -c | tr '\n' ' ')"
if [ "$N" -ge 9 ]; then ok "log has $N events :: $EVENTS"; else bad "log only $N events"; fi

say "M9 status --json is a stable contract"
OUT="$(bash bin/wmission status "$MID" --json)"
if printf '%s' "$OUT" | jq -e '.id and (.steps|length==2)' >/dev/null; then ok "status --json ok"; else bad "status --json: $OUT"; fi

printf '\nSUMMARY pass=%d fail=%d skip=%d\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
