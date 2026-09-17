# -*- coding: utf-8 -*-
"""定位：指定的若干存活文件里，引用了哪些「本批待删」路径。"""
import os
import re
import sys

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(PROJECT)

plan = open(sys.argv[1], encoding="utf-8", errors="replace").read().splitlines()
mode, pending = None, None
renames, deletes = [], []
for ln in plan:
    if ln.startswith("重命名 "):
        mode = "r"
        continue
    if ln.startswith("第一步之后还需删除"):
        mode = "d"
        continue
    if ln.startswith("本批排除"):
        mode = None
        continue
    if mode == "r":
        if ln.startswith("    -> ") and pending:
            renames.append((pending, ln[7:]))
            pending = None
        elif ln.startswith("  assets/"):
            pending = ln[2:]
    elif mode == "d" and ln.startswith("  assets/"):
        deletes.append(ln[2:])

del_set = set(deletes)
ren_map = dict(renames)

for fp in sys.argv[2:]:
    text = open(fp, encoding="utf-8", errors="replace").read()
    print("### %s" % fp)
    found = [d for d in del_set if d in text]
    if found:
        for d in sorted(found):
            i = text.index(d)
            line = text[:i].count("\n") + 1
            print("   L%-5d 待删: %s" % (line, d))
            # 该路径归一后应落到哪
            import re as _re
            VER_ANY = _re.compile(r"_v(\d{3})(?=[._]|$)")
            VER_DIR = _re.compile(r"^v\d{3}$")
            parts = [p for p in d.split("/") if not VER_DIR.match(p)]
            st = "/".join(VER_ANY.sub("", p) for p in parts)
            keep = [b for a, b in renames if st in a or b == st]
            print("        稳定目标: %s" % st)
            print("        本批改名到: %s" % (ren_map.get(st) or keep or "（无，可能被删代）"))
    print()
