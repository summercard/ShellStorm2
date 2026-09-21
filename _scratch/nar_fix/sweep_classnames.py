# -*- coding: utf-8 -*-
"""扫描 res:// 下所有 .gd, 找出重复的 class_name 声明 (类名抢注隐患).
只读, 不改任何文件.
"""
import os
import re
import collections

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"
SKIP_DIRS = {".godot", ".git", "app_userdata", "Godot"}

CLASS_RE = re.compile(r'^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)', re.M)

groups = collections.defaultdict(list)

for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
    for fn in filenames:
        if not fn.endswith(".gd"):
            continue
        full = os.path.join(dirpath, fn)
        try:
            with open(full, "rb") as f:
                raw = f.read()
        except OSError:
            continue
        text = raw.decode("utf-8", "replace")
        m = CLASS_RE.search(text)
        if m:
            rel = os.path.relpath(full, ROOT).replace("\\", "/")
            groups[m.group(1)].append(rel)

dups = {k: v for k, v in groups.items() if len(v) > 1}

print("CLASS_NAME_SWEEP total_classes=%d duplicate_groups=%d" % (len(groups), len(dups)))
if not dups:
    print("CLASS_NAME_SWEEP_OK 无重复类名")
else:
    for name in sorted(dups):
        print("DUPLICATE class_name=%s count=%d" % (name, len(dups[name])))
        for rel in sorted(dups[name]):
            print("    - res://%s" % rel)
