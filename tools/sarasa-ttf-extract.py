#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
# SPDX-License-Identifier: MIT
# sarasa-ttf-extract — 从系统 profile 的 Sarasa TTC 提取 Gothic SC 单文件 TTF
# 文档：docs/scripts/repo/sarasa-ttf-extract.md

import subprocess
from pathlib import Path

from fontTools.ttLib import TTCollection

SRC = Path('/run/current-system/profile/share/fonts/truetype')
DST = Path.home() / '.local/share/fonts'
BASE = 'Sarasa Gothic SC'


def target_name(family: str, subfamily: str) -> str:
    suffix = family[len(BASE):].strip()
    if subfamily and subfamily != 'Regular':
        suffix = f'{suffix} {subfamily}'.strip()
    return f'SarasaGothicSC-{suffix.replace(" ", "") or "Regular"}.ttf'


def main() -> None:
    DST.mkdir(parents=True, exist_ok=True)
    for ttc in sorted(SRC.glob('Sarasa-*.ttc')):
        for font in TTCollection(ttc).fonts:
            family = font['name'].getDebugName(1) or ''
            if family == BASE or family.startswith(f'{BASE} '):
                out = DST / target_name(family, font['name'].getDebugName(2))
                font.save(str(out))
                print(f'{ttc.name} -> {out.name}')
    subprocess.run(['fc-cache', '-f', str(DST)], check=True)


if __name__ == '__main__':
    main()
