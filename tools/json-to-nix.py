#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
# SPDX-License-Identifier: MIT

# json-to-nix - 把 Zed 的 settings.json 转换成等价的 nix 配置并打印，
# 供手动粘贴进 source/nix/configuration/programs/zed.nix 的 userSettings。
#
# 用法:
#   tools/zed-to-nix.py    # 读取 ~/.config/zed/settings.json
#
# /nix/store/<hash>-<pkg>-<ver>/bin/<bin> 会被还原成
# lib.getExe pkgs.<pkg>（bin 与包同名）或 lib.getExe' pkgs.<pkg> "<bin>"，
# 避免 nixpkgs 升级后 store hash 失效。

import json
import re
import sys
from pathlib import Path

SETTINGS = Path.home() / ".config" / "zed" / "settings.json"

# nix 合法 identifier：字母/下划线开头，可含连字符
NIX_IDENT = re.compile(r"^[a-zA-Z_][a-zA-Z0-9_'-]*$")
# /nix/store/<32位hash>-<目录名>/bin/<bin名>
STORE_BIN = re.compile(r"^/nix/store/[a-z0-9]{32}-([^/]+)/bin/([^/]+)$")

# 单行列表的最大宽度，超过则每元素一行（近似 nixfmt 的折行习惯）
LINE_LIMIT = 90


def pkg_attr(dirname):
    """从 store 目录名剥离尾部版本段，猜 nixpkgs attr 名。

    prettier-3.8.3 -> prettier, rust-analyzer-2026-06-15 -> rust-analyzer
    """
    m = re.match(r"^(.*?)-\d", dirname)
    return m.group(1) if m else dirname


def nix_string(s):
    """转成 nix 字符串字面量。JSON 与 nix 转义规则接近，仅两处例外：

    - "${" 在 nix 是插值，$ 写成 \\u0024 规避
    - \b \f nix 不支持，统一用 \\uXXXX
    """
    out = ['"']
    i = 0
    while i < len(s):
        ch = s[i]
        if ch == '"':
            out.append('\\"')
        elif ch == "\\":
            out.append("\\\\")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "$" and i + 1 < len(s) and s[i + 1] == "{":
            out.append("\\u0024{")
            i += 1
        elif ord(ch) < 0x20:
            out.append("\\u%04x" % ord(ch))
        else:
            out.append(ch)
        i += 1
    out.append('"')
    return "".join(out)


def nix_key(k):
    return k if NIX_IDENT.match(k) else nix_string(k)


def nix_scalar(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if v is None:
        return "null"
    if isinstance(v, (int, float)):
        return str(v)
    m = STORE_BIN.match(v) if isinstance(v, str) else None
    if m:
        dirname, binname = m.groups()
        attr = pkg_attr(dirname)
        if binname == attr:
            return "lib.getExe pkgs.%s" % attr
        return "lib.getExe' pkgs.%s %s" % (attr, nix_string(binname))
    return nix_string(v)


def is_scalar(v):
    return not isinstance(v, (list, dict))


def to_nix(v, indent):
    pad = "  " * indent
    if isinstance(v, dict):
        if not v:
            return "{ }"
        lines = ["{"]
        for k in sorted(v):
            lines.append("%s  %s = %s;" % (pad, nix_key(k), to_nix(v[k], indent + 1)))
        lines.append(pad + "}")
        return "\n".join(lines)
    if isinstance(v, list):
        if not v:
            return "[ ]"
        if all(is_scalar(x) for x in v):
            flat = "[ %s ]" % " ".join(nix_scalar(x) for x in v)
            if len(pad) + len(flat) <= LINE_LIMIT:
                return flat
        lines = ["["]
        for x in v:
            lines.append("%s  %s" % (pad, to_nix(x, indent + 1)))
        lines.append(pad + "]")
        return "\n".join(lines)
    return nix_scalar(v)


def main():
    if not SETTINGS.is_file():
        sys.exit("错误: 找不到 %s" % SETTINGS)

    data = json.loads(SETTINGS.read_text(encoding="utf-8"))

    print(
        "# 粘贴进 source/nix/configuration/programs/zed.nix 的 userSettings = { ... }"
    )
    print()
    for k in sorted(data):
        print("%s = %s;" % (nix_key(k), to_nix(data[k], 1)))


if __name__ == "__main__":
    main()
