# -*- coding: utf-8 -*-
"""按 Windows 创建时间(ctime)/访问时间 判断哪些远征 blend 是「最近引入的新文件」。"""
import os, time

WS = r"I:\工作项目\shellstrom2"
PROJ = os.path.join(WS, "ShellStorm2")

rows = []
for dirpath, dirnames, filenames in os.walk(PROJ):
    dirnames[:] = [d for d in dirnames if d not in (".git", ".godot", "node_modules", ".import", "__pycache__")]
    for fn in filenames:
        if not fn.lower().endswith(".blend"):
            continue
        full = os.path.join(dirpath, fn)
        rel = os.path.relpath(full, PROJ).replace("\\", "/")
        if not ("expedition" in rel.lower() or "远征" in rel):
            continue
        st = os.stat(full)
        rows.append((st.st_ctime, st.st_mtime, st.st_size, rel))

print("== 远征 blend 中，按「创建时间」倒序前 30 ==")
print("(创建时间 = 文件落到本盘的时间；比 mtime 更能反映「何时被引入」)")
for c, m, s, r in sorted(rows, key=lambda x: -x[0])[:30]:
    print("创建 %s | 修改 %s | %8.1fKB | %s" % (
        time.strftime("%Y-%m-%d %H:%M", time.localtime(c)),
        time.strftime("%Y-%m-%d %H:%M", time.localtime(m)), s/1024.0, r))

print()
from collections import Counter
cnt = Counter(time.strftime("%Y-%m-%d", time.localtime(c)) for c, m, s, r in rows)
print("== 按创建日期统计（全量 %d 个远征 blend）==" % len(rows))
for d, n in sorted(cnt.items(), reverse=True):
    print("  %s : %d 个" % (d, n))
