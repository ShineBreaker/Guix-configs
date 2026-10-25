#!/usr/bin/env python3
"""Scan translated/*.zh.md for untranslated English residues.

Catches the pattern that bit us during the Guix Cookbook polish pass:
a Chinese paragraph containing ≥3 English words (≥4 chars each) right
after a Chinese punctuation mark — usually a stray word like "spurious",
"the user's", or other leakage from the source that the translator
forgot to translate.

Usage:
    python3 scripts/polish_scan.py [translated_dir]

Default translated_dir is `./translated` next to this script. With
--strict, also flags smaller 2-word leaks near Chinese punctuation.
"""
import os
import re
import sys

# Chinese Han range (CJK Unified Ideographs, basic block) + common
# Chinese punctuation marks that often precede a stray English word.
_CN = r'[\u4e00-\u9fff，、。！？；：()]'
# Single word (≥4 letters) — lowered from 5 because we want to catch
# 3-letter terms only when context is suspicious.
_WORD = r'[a-zA-Z]{4,}'
# Skip lines whose stripped text starts with one of these.
_SKIP_PREFIXES = ('```', '#', '<!--', 'http', 'https', '//')
# Named entities where English-in-Chinese-context is legitimate.
_NAMED_ENTITIES = (
    'Free Software Foundation', 'Creative Commons',
    'GNU General Public License', 'GNU Free Documentation',
)


def _is_named_entity(line: str) -> bool:
    return any(ne in line for ne in _NAMED_ENTITIES)


def scan(workspace: str, strict: bool = False) -> int:
    translated_dir = os.path.join(workspace, 'translated')
    if not os.path.isdir(translated_dir):
        print(f'Error: {translated_dir} is not a directory', file=sys.stderr)
        return 2

    pattern = (
        _CN + r'\s*'
        + (rf'({_WORD}\s+){{2,}{_WORD}' if strict else rf'({_WORD}\s+){{2,}}{_WORD}')
        + r'\b'
    )
    rx = re.compile(pattern)
    hits = 0
    for fn in sorted(os.listdir(translated_dir)):
        if not fn.endswith('.zh.md'):
            continue
        path = os.path.join(translated_dir, fn)
        in_code = False
        with open(path, encoding='utf-8') as f:
            for ln, line in enumerate(f, 1):
                stripped = line.lstrip()
                if stripped.startswith('```'):
                    in_code = not in_code
                    continue
                if in_code:
                    continue
                if any(stripped.startswith(p) for p in _SKIP_PREFIXES):
                    continue
                if _is_named_entity(line):
                    continue
                # Look only in narrative prose — line must contain Chinese.
                if not re.search(r'[\u4e00-\u9fff]', line):
                    continue
                if rx.search(line):
                    print(f'{fn}:{ln}: {line.rstrip()[:160]}')
                    hits += 1

    if hits == 0:
        print('No obvious untranslated-English residues found.')
    else:
        print(f'\n{hits} suspicious line(s) — review each before editing.')
    return 0


def main() -> int:
    args = sys.argv[1:]
    if '--help' in args or '-h' in args:
        print(__doc__)
        return 0
    strict = '--strict' in args
    args = [a for a in args if a != '--strict']
    workspace = args[0] if args else os.path.dirname(
        os.path.dirname(os.path.abspath(__file__))
    )
    # `workspace` here = this skill dir; default to "." parent for
    # projects that nest the skill next to translated/.
    workspace = os.path.dirname(os.path.abspath(workspace)) \
        if workspace.endswith('document-translation') else workspace
    return scan(workspace, strict=strict)


if __name__ == '__main__':
    raise SystemExit(main())
