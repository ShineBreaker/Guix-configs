#!/usr/bin/env bash
# Rebuild emacs.org from emacs.org.bak (with PROPERTY updated) + emacs.org.newhead.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORG="$ROOT/emacs.org"
BAK="$ROOT/emacs.org.bak"
HEAD="$ROOT/emacs.org.newhead"

# Lines 1-6 of bak are the original org header (#+TITLE ... #+OPTIONS).
# Line 7 is blank, line 8 starts "* 启动顺序与模块依赖速查" (the original old head).
# Lines 8-26 are the old intro.
# Line 28 starts "* 启动与基础设施".
# Lines 28-100 cover: GC, 路径常量 (bootstrap require), Frame require.
# Lines 101-286 cover: 键位辅助函数, 包管理, 基础行为设置.
# Line 287 starts "* 界面与外观".
# We want:
#   New header (#+TITLE ... #+OPTIONS ... :noweb tangle) +
#   emacs.org.newhead (new intro + new "* 启动与基础设施" with inlined bootstrap/frame + new GC) +
#   bak lines 101-286 (键位辅助函数, 包管理, 基础行为设置) +
#   emacs.org.bak from line 287 (the original "* 界面与外观") onwards.

# Write new header
cat > "$ROOT/scripts/_emacs.head" <<'ORGTAG'
#+TITLE: literal-config
#+AUTHOR: BrokenShine
#+DATE: 2026-07-04
#+PROPERTY: header-args:emacs-lisp :tangle main.el :lexical yes :mkdirp yes :noweb tangle
#+STARTUP: content
#+OPTIONS: toc:2

ORGTAG

# Extract bak middle (lines 101-286) and tail (287+)
sed -n '101,286p' "$BAK" > "$ROOT/scripts/_emacs.middle"
tail -n +287 "$BAK" > "$ROOT/scripts/_emacs.tail"

# Concatenate
cat "$ROOT/scripts/_emacs.head" "$HEAD" "$ROOT/scripts/_emacs.middle" "$ROOT/scripts/_emacs.tail" > "$ORG"
rm -f "$ROOT/scripts/_emacs.head" "$ROOT/scripts/_emacs.middle" "$ROOT/scripts/_emacs.tail"

echo "Rebuilt $ORG from bak + newhead + middle"
wc -l "$ORG"