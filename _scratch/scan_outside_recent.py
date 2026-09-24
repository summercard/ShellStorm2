# -*- coding: utf-8 -*-
"""工作区之外：附近目录里最近 3 天新增/修改的 .blend（判断主人是否把新文件放在了别处）。"""
import os, time

NOW = time.time()
CUT = NOW - 3 * 86400

ROOTS = [
    r"I:\工作项目",
    os.path.expanduser(r"~\Desktop"),
    os.path.expanduser(r"~\Downloads"),
    os.path.expanduser(r"~\Documents"),
]

SKIP = {".git", ".godot", "node_modules", ".import", "__pycache__", "$RECYCLE.BIN", "System Volume Information"}

found = []
for root in ROOTS:
    if not os.path.isdir(root):
        continue
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP]
        for fn in filenames:
            if not fn.lower().endswith(".blend"):
                continue
            full = os.path.join(dirpath, fn)
            try:
                st = os.stat(full)
            except OSError:
                continue
            if max(st.st_mtime, st.st_ctime) >= CUT:
                found.append((max(st.st_mtime, st.st_ctime), st.st_mtime, st.st_ctime, st.st_size, full))

found.sort(key=lambda x: -x[0])
print("近 3 天内新增或修改的 .blend（工作区之外也含）: %d 个" % len(found))
for t, m, c, s, p in found[:40]:
    print("  最新活动 %s | 创建 %s | 修改 %s | %8.1fKB | %s" % (
        time.strftime("%Y-%m-%d %H:%M", time.localtime(t)),
        time.strftime("%m-%d %H:%M", time.localtime(c)),
        time.strftime("%m-%d %H:%M", time.localtime(m)), s/1024.0, p))
