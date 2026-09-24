# -*- coding: utf-8 -*-
"""全工作区扫描：最近修改的 .blend，以及一切名字含 expedition / 远征 的 blend。"""
import os, time

WS = r"I:\工作项目\shellstrom2"          # 工作区根
PROJ = os.path.join(WS, "ShellStorm2")

recent = []          # (mtime, size, path)
exp_all = []
for base in (WS,):
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in (".git", ".godot", "node_modules", ".import", "__pycache__")]
        for fn in filenames:
            if not fn.lower().endswith(".blend"):
                continue
            full = os.path.join(dirpath, fn)
            try:
                st = os.stat(full)
            except OSError:
                continue
            rel = os.path.relpath(full, WS)
            tag = "PROJ" if full.startswith(PROJ) else "WS-ROOT"
            recent.append((st.st_mtime, st.st_size, tag, rel))
            if "expedition" in full.lower() or "远征" in full:
                exp_all.append((st.st_mtime, st.st_size, tag, rel))

recent.sort(key=lambda x: -x[0])
print("### 全工作区最近修改的 .blend（前 40） ###")
for mt, size, tag, rel in recent[:40]:
    print("%s %9.1fKB [%s] %s" % (time.strftime("%Y-%m-%d %H:%M", time.localtime(mt)), size/1024.0, tag, rel))

print()
print("### 命中 expedition / 远征 的 blend 总数 = %d ###" % len(exp_all))
print("### 其中非 component_packages 的（真正的源文件级） ###")
for mt, size, tag, rel in sorted(exp_all, key=lambda x: -x[0]):
    if "component_packages" not in rel:
        print("%s %9.1fKB [%s] %s" % (time.strftime("%Y-%m-%d %H:%M", time.localtime(mt)), size/1024.0, tag, rel))

print()
print("### 注意：命中但不在 ShellStorm2 子目录下的 ###")
n = 0
for mt, size, tag, rel in sorted(exp_all, key=lambda x: -x[0]):
    if tag != "PROJ":
        print("%s %9.1fKB %s" % (time.strftime("%Y-%m-%d %H:%M", time.localtime(mt)), size/1024.0, rel))
        n += 1
if n == 0:
    print("（无）")
