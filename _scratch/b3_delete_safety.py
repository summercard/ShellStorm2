# -*- coding: utf-8 -*-
"""B3 预检 3：待删项是否仍被「存活文件」引用。

存活文件 = 仓库内除「本批待删文件」与「已删除的旧名」以外的所有文本文件。
若某待删路径被存活文件引用 → 断链，必须停下。
"""
import os
import re
import sys

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(PROJECT)

plan = open(sys.argv[1] if len(sys.argv) > 1 else "/tmp/b3_plan.txt",
            encoding="utf-8", errors="replace").read().splitlines()

# 解析 plan：重命名段 "  old\n    -> new"，删除段在「第一步之后」
renames = []
deletes = []
mode = None
pending = None
for i, ln in enumerate(plan):
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
    elif mode == "d":
        if ln.startswith("  assets/"):
            deletes.append(ln[2:])

del_set = {d for d in deletes if d.endswith((".glb", ".tscn", ".import", ".uid"))}
ren_src = {a for a, b in renames}

TEXT_EXT = (".gd", ".tscn", ".py", ".mjs", ".json", ".md", ".tres", ".cfg", ".txt", ".sh")
SKIP_DIRS = {".git", ".godot", "outputs"}
hits = {}
alive_files = []
for dp, dn, fn in os.walk("."):
    dn[:] = [d for d in dn if d not in SKIP_DIRS]
    for f in fn:
        if not f.endswith(TEXT_EXT):
            continue
        fp = os.path.join(dp, f).replace(os.sep, "/").lstrip("./")
        if fp in del_set:
            continue
        alive_files.append(fp)

print("存活文本文件：%d" % len(alive_files))

for fp in alive_files:
    try:
        text = open(fp, encoding="utf-8", errors="replace").read()
    except OSError:
        continue
    for d in del_set:
        if d in text:
            hits.setdefault(d, []).append(fp)

if hits:
    print("\n!! %d 个待删文件仍被存活文件引用：" % len(hits))
    for d in sorted(hits):
        print("   %s" % d)
        for w in hits[d][:5]:
            print("        <- %s" % w)
else:
    print("\nOK：178 个待删项没有被任何存活文件引用（除了它们自己）。")

# 反向：改名的旧路径是否仍被存活文件引用（应由 fix_code_refs 处理，此处仅统计）
old_hits = {}
for fp in alive_files:
    if fp in ren_src:
        continue
    try:
        text = open(fp, encoding="utf-8", errors="replace").read()
    except OSError:
        continue
    for a in ren_src:
        if a in text:
            old_hits.setdefault(a, []).append(fp)

print("\n改名旧路径仍被存活的非资产文件引用（应由 --fix-code-refs / 人工同步）：%d 条" % len(old_hits))
byext = {}
for a, ws in old_hits.items():
    for w in ws:
        byext.setdefault(os.path.splitext(w)[1], set()).add(w)
for ext, ws in sorted(byext.items()):
    print("   %-8s %d 文件" % (ext, len(ws)))
print("   明细（前 25 文件）：")
for w in sorted({w for ws in old_hits.values() for w in ws})[:25]:
    print("      ", w)
