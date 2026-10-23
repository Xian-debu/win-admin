#!/usr/bin/env python3
"""scan-sessions.py - reproducible evidence extractor for docs/16.

Reads DSH session logs (zstd-compressed jsonl) and reports how win-admin was
USED: every tool call whose arguments mention the repo CLI, plus counters for
"hand-written Win32" patterns (Add-Type/ShowWindow/SetCursorPos/mouse_event...).

Why: after v1.0.0 the failure mode is not an error code, it is "the primitive
does not exist, so the agent improvised". Exit codes cannot show that; tool
argument text can.

usage:
  python3 scripts/scan-sessions.py --session c0ace632-8b18-4955-87c1-cd96752f4ebd
  python3 scripts/scan-sessions.py --session c0ace632... --from 3800 --to 4900
  python3 scripts/scan-sessions.py --session c0ace632... --full   # print matched calls

session id = the uuid in ~/.dsh/sessions/--root--/session-<uuid>/
No network, no write; session content stays local (only counts/paths printed
unless --full, and --full output is for the operator s own review).
"""
import argparse, json, os, re, subprocess, sys

HOME = os.path.expanduser('~')
ROOT = os.path.join(HOME, '.dsh', 'sessions', '--root--')
PATTERNS = {
    'Add-Type': r'Add-Type',
    'ShowWindow': r'ShowWindow',
    'SetCursorPos': r'SetCursorPos',
    'mouse_event': r'mouse_event',
    'SendInput': r'SendInput',
    'keybd_event': r'keybd_event',
    'user32.dll': r'user32\.dll',
    'cdp_status': r'cdp_status',
    'pywin32': r'pywin32',
    'comtypes': r'comtypes',
}
CLI_RE = re.compile(r'\b(bin/)?(winput|wwin|wuia|wshot|wclip|wwait|wdiag|wmission)\b|ops/(open|find-and-click|fill|wait-for)')

def find_log(uuid):
    d = os.path.join(ROOT, 'session-' + uuid)
    if not os.path.isdir(d):
        sys.exit('no such session dir: ' + d)
    for name in ('session.v4.jsonl.zstd', 'session.v4.jsonl'):
        p = os.path.join(d, name)
        if os.path.exists(p):
            return p
    sys.exit('no session log in ' + d)

def iter_lines(path):
    if path.endswith('.zstd'):
        with subprocess.Popen(['zstd', '-dc', path], stdout=subprocess.PIPE) as p:
            for raw in p.stdout:
                yield raw
    else:
        with open(path, 'rb') as f:
            for raw in f:
                yield raw

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--session', required=True, help='session uuid (dir name without session- prefix)')
    ap.add_argument('--from', dest='lo', type=int, default=0)
    ap.add_argument('--to', dest='hi', type=int, default=10**9)
    ap.add_argument('--full', action='store_true', help='print every matched tool call (first 240 chars)')
    ap.add_argument('--json', action='store_true', help='machine-readable output')
    a = ap.parse_args()
    log = find_log(a.session)
    counts = {k: 0 for k in PATTERNS}
    calls = {k: 0 for k in PATTERNS}
    cli = []
    for raw in iter_lines(log):
        try:
            o = json.loads(raw)
        except Exception:
            continue
        seq = o.get('seq') or 0
        if seq < a.lo or seq > a.hi:
            continue
        if o.get('type') != 'tool/call':
            continue
        d = o.get('data') or {}
        args = json.dumps(d.get('arguments'), ensure_ascii=False)
        for k, rx in PATTERNS.items():
            if re.search(rx, args):
                calls[k] += 1
        if CLI_RE.search(args):
            cli.append((seq, d.get('name'), ' '.join(args.split())[:240]))
    out = {'session': a.session, 'log': log, 'seqRange': [a.lo, a.hi],
           'winAdminCalls': len(cli), 'handWrittenWin32': {k: v for k, v in calls.items() if v}}
    if a.json:
        print(json.dumps(out, ensure_ascii=False, indent=2))
    else:
        print('session : %s' % a.session)
        print('log     : %s' % log)
        print('seq     : %s..%s' % (a.lo, a.hi if a.hi < 10**9 else '*'))
        print('win-admin CLI calls : %d' % len(cli))
        print('hand-written Win32  : %s' % (out['handWrittenWin32'] or '{}'))
        if a.full:
            for seq, name, args in cli:
                print('  seq=%-6s %-10s %s' % (seq, name, args))

if __name__ == '__main__':
    main()
