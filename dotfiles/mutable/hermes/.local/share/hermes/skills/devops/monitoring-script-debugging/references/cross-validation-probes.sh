#!/usr/bin/env bash
# Cross-validation probes for monitoring script output.
# Run these to verify that metabolism_check.py (or similar audit scripts)
# are reporting real signals, not parser/counting bugs.

set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.local/share/hermes}"

echo "=== 1. Inject Size Cross-Check ==="
echo "Sum of skill description fields + memory files:"
python3 -c "
import re, pathlib
total = 0
for p in pathlib.Path('${HERMES_HOME}/skills').rglob('SKILL.md'):
    head = p.read_text(errors='ignore')[:4096]
    if not head.startswith('---'): continue
    fm_end = head.find('\n---', 3)
    if fm_end < 0: fm_end = len(head)
    m = re.search(r'^description\s*:\s*(.*?)(?=\n[a-zA-Z_][\w-]*\s*:|\Z)', head[3:fm_end], re.M|re.S)
    if m:
        d = m.group(1).strip().strip('\"').strip(\"'\")
        total += len(d.encode())
mem_bytes = 0
mem_dir = pathlib.Path('${HERMES_HOME}/memories')
if mem_dir.exists():
    for p in mem_dir.rglob('*.md'):
        mem_bytes += p.stat().st_size
total += mem_bytes
print(f'  {total} bytes ({total/1024:.1f} KB)')
"

echo ""
echo "=== 2. Error Count Cross-Check ==="
echo "Unique exception types in logs:"
grep -h "Traceback\|ERROR" "${HERMES_HOME}/logs/"*.log 2>/dev/null | \
  python3 -c "
import sys, re, collections
c = collections.Counter()
for line in sys.stdin:
    m = re.search(r'\b\w+(?:Error|Exception)\b', line)
    if m: c[m.group(0)] += 1
for k, v in c.most_common(10): print(f'  {v:>5}  {k}')
print(f'  Total unique: {len(c)}')
" || echo "  (no logs found)"

echo ""
echo "=== 3. Broken JSON Cross-Check ==="
echo "Files where standard json.loads fails:"
python3 -c "
import json, pathlib
home = pathlib.Path('${HERMES_HOME}')
broken = []
for p in home.rglob('*.json'):
    if any(s in p.as_posix() for s in ('node_modules', '.venv', 'lsp/', 'Trash/')): continue
    try: json.loads(p.read_text(errors='ignore'))
    except Exception as e: broken.append(f'{p.relative_to(home)}  [{type(e).__name__}]')
print(f'  Total broken: {len(broken)}')
for b in broken[:10]: print(f'  {b}')
if len(broken) > 10: print(f'  ... and {len(broken)-10} more')
"

echo ""
echo "=== 4. Parser Sanity Check ==="
echo "Files where lenient parser fails but standard parser passes (should be 0):"
python3 -c "
import json, pathlib, re

def _parse_json_lenient(text):
    text_no_block = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
    out_lines = []
    for line in text_no_block.split('\n'):
        in_str = False
        esc = False
        cleaned = []
        i = 0
        while i < len(line):
            ch = line[i]
            if esc:
                cleaned.append(ch); esc = False
            elif ch == '\\\\\\\\':
                cleaned.append(ch); esc = True
            elif ch == '\"':
                in_str = not in_str; cleaned.append(ch)
            elif not in_str and i + 1 < len(line) and line[i] == '/' and line[i + 1] == '/':
                break
            else:
                cleaned.append(ch)
            i += 1
        out_lines.append(''.join(cleaned))
    cleaned = '\n'.join(out_lines)
    cleaned = re.sub(r',(\s*[\\]}])', r'\1', cleaned)
    try:
        json.loads(cleaned)
        return True
    except:
        return False

home = pathlib.Path('${HERMES_HOME}')
suspicious = []
for p in home.rglob('*.json'):
    if any(s in p.as_posix() for s in ('node_modules', '.venv', 'lsp/', 'Trash/')): continue
    text = p.read_text(errors='ignore')
    try:
        json.loads(text)
        std_ok = True
    except:
        std_ok = False
    lenient_ok = _parse_json_lenient(text)
    if not std_ok and lenient_ok:
        suspicious.append(str(p.relative_to(home)))

print(f'  Total: {len(suspicious)} (these are JSONC-fixed, not bugs)')
for s in suspicious[:5]: print(f'  {s}')
if len(suspicious) > 5: print(f'  ... and {len(suspicious)-5} more')
"