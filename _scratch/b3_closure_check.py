# -*- coding: utf-8 -*-
"""B3 预检 2：从美术总装递归解析依赖闭包，验证闭包内每条引用都指向
「collapse 会保留的那一版」。任何一条指向被删版本 = 静默换内容/断链。
"""
import collections
import os
import re

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(PROJECT)

ROOT = "assets/art/environments/base_facility_3d"
VER_ANY = re.compile(r"_v(\d{3})(?=[._]|$)")
VER_DIR = re.compile(r"^v\d{3}$")
RUN = re.compile(r"_v\d{3}\.(?:glb|tscn)(?:\.(?:import|uid))?$")


def stable(rel):
    parts = [p for p in rel.split("/") if not VER_DIR.match(p)]
    return "/".join(VER_ANY.sub("", p) for p in parts)


# 稳定目标 -> 候选源（按 collapse 口径）
groups = collections.defaultdict(list)
for dp, dn, fn in os.walk(ROOT):
    rel = os.path.relpath(dp, ROOT).replace(os.sep, "/")
    if rel.split("/")[0] not in ("components", "runtime"):
        continue
    for f in fn:
        if RUN.search(f):
            groups[stable(rel + "/" + f)].append(rel + "/" + f)

kept = {}
for t, srcs in groups.items():
    srcs.sort(key=lambda s: VER_ANY.findall(s)[-1] if VER_ANY.findall(s) else "")
    kept[t] = srcs[-1]

# 稳定目标 -> (被引用但会被删的源)
ref_re = re.compile(r'res://assets/art/([A-Za-z0-9_/.\-]+?\.(?:glb|tscn))')

seen, order = set(), []
queue = ["assets/art/environments/base_facility_3d/runtime/env_base_facility_art_layout_top3d_v001.tscn"]
# 另加几个从测试/代码里直接引用的入口
queue += [
    "assets/art/environments/base_facility_3d/runtime/env_base99_floor_visuals_v021/env_base99_floor_visuals_root_top3d_v004.tscn",
    "assets/art/environments/base_facility_3d/runtime/env_base99_floor_full_replacement_v021/env_base99_floor_full_replacement_v021_root_top3d_v003.tscn",
    "assets/art/environments/base_facility_3d/runtime/env_base99_floor_visuals_v021/loft_floor_finish/loft_floor_finish_root_top3d_v003.tscn",
]
problems, missing, dangling_target = [], [], []

while queue:
    cur = queue.pop(0).replace("assets/art/", "", 1)
    if cur in seen:
        continue
    seen.add(cur)
    # 该文件自己是否「会被删」？
    st = stable(cur)
    if st in kept and kept[st] != cur and os.path.isfile(os.path.join("assets/art", cur)):
        problems.append(("被引用的是将被删除的版本", cur, "保留 " + kept[st]))
    p = os.path.join("assets/art", cur)
    if not os.path.isfile(p):
        missing.append(cur)
        continue
    if not cur.endswith(".tscn"):
        continue
    text = open(p, encoding="utf8", errors="replace").read()
    for m in ref_re.finditer(text):
        ref = m.group(1)
        if ref in seen:
            continue
        queue.append(ref)
        st2 = stable(ref)
        if st2 in kept and kept[st2] != ref:
            if os.path.isfile(os.path.join("assets/art", ref)):
                problems.append(("引用指向将被删除的版本", ref, "保留 " + kept[st2]))
            else:
                dangling_target.append((ref, st2))

print("闭包规模: %d 个 .tscn/.glb" % len(seen))
print()
if problems:
    print("!! 闭包内 %d 条引用指向「将被 collapse 删掉」的版本：" % len(problems))
    for k, a, b in problems:
        print("   %s\n     引用: %s\n     %s" % (k, a, b))
else:
    print("OK：闭包内没有任何引用指向将被删除的版本。")
print()
if dangling_target:
    print("引用指向的带版本路径已不存在（需由 fix_code_refs 改稳定路径）：")
    for ref, st2 in sorted(set(dangling_target)):
        print("   %s -> %s" % (ref, st2))
if missing:
    print()
    print("闭包入口/中间文件在磁盘上不存在（%d）：" % len(set(missing)))
    for m in sorted(set(missing))[:10]:
        print("   ", m)
