# -*- coding: utf-8 -*-
"""扫描与「远征01 / expedition」相关的 .blend 原始文件，按修改时间倒序。"""
import os, sys, time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), os.pardir))
print("ROOT =", ROOT)

KEY_DIR = "expedition"
KEY_CN = "远征"

hits = []
for dirpath, dirnames, filenames in os.walk(ROOT):
    # 跳过噪音目录
    dirnames[:] = [d for d in dirnames if d not in (".git", ".godot", "node_modules", ".import")]
    for fn in filenames:
        if not fn.lower().endswith(".blend"):
            continue
        full = os.path.join(dirpath, fn)
        rel = os.path.relpath(full, ROOT).replace("\\", "/")
        if KEY_DIR in rel.lower() or KEY_CN in rel:
            st = os.stat(full)
            hits.append((st.st_mtime, st.st_size, rel))

hits.sort(key=lambda x: -x[0])
print("TOTAL =", len(hits))
print("=" * 100)
for mt, size, rel in hits[:400]:
    print("%s  %9.2fKB  %s" % (time.strftime("%Y-%m-%d %H:%M", time.localtime(mt)), size / 1024.0, rel))

print("=" * 100)
print("--- 按目录汇总（文件数, 最新修改时间, 目录）---")
from collections import defaultdict
agg = defaultdict(list)
for mt, size, rel in hits:
    agg[os.path.dirname(rel)].append(mt)
rows = []
for d, mts in agg.items():
    rows.append((max(mts), len(mts), d))
rows.sort(key=lambda x: -x[0])
for mx, n, d in rows:
    print("%s  %4d files  %s" % (time.strftime("%Y-%m-%d %H:%M", time.localtime(mx)), n, d))
