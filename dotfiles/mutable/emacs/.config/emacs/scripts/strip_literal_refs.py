#!/usr/bin/env python3
"""Strip (require 'literal-X) and (provide 'literal-X) from emacs.org."""
import re
import sys

PATH = "emacs.org"
with open(PATH, encoding="utf-8") as f:
    lines = f.readlines()

rx_req = re.compile(r"^\(require\s+'literal-[\w-]+\)\s*$")
rx_prov = re.compile(r"^\(provide\s+'literal-[\w-]+\)\s*$")

removed = 0
out = []
for line in lines:
    stripped = line.rstrip("\n")
    if rx_req.match(stripped) or rx_prov.match(stripped):
        removed += 1
        continue
    out.append(line)

with open(PATH, "w", encoding="utf-8") as f:
    f.writelines(out)
print(f"Removed {removed} literal-* require/provide lines")