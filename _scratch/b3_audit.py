# -*- coding: utf-8 -*-
"""B3 预检：把 443 个欠账按「稳定路径」归组，列出每组候选版本 + 谁被引用。

目的：确认 collapse（保留最高版本）选的版本 == 当前实际被引用的版本。
不等就是「静默换内容」，必须先定代。
"""
import collections
import os
import re
import sys

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(PROJECT)

ROOT = "assets/art/environments/base_facility_3d"
VER_ANY = re.compile(r"_v(\d{3})(?=[._]|$)")
VER_DIR = re.compile(r"^v\d{3}$")
RUN = re.compile(r"_v\d{3}\.(?:glb|tscn)(?:\.(?:import|uid))?$")


def stable(rel):
    parts = [p for p in rel.split("/") if not VER_DIR.match(p)]
    return "/".join(VER_ANY.sub("", p) for p in parts)


def ver(rel):
    m = VER_ANY.findall(rel)
    return m[-1] if m else ""


# --- 1) 归组
groups = collections.defaultdict(list)
for dp, dn, fn in os.walk(ROOT):
    rel = os.path.relpath(dp, ROOT).replace(os.sep, "/")
    if rel.split("/")[0] not in ("components", "runtime"):
        continue
    for f in fn:
        if not RUN.search(f):
            continue
        r = rel + "/" + f
        groups[stable(r)].append(r)

# --- 2) 全仓引用索引：扫文本文件里出现的 base_facility_3d 路径
TEXT_EXT = (".gd", ".tscn", ".py", ".mjs", ".json", ".md", ".tres", ".cfg", ".txt")
SKIP_DIRS = {".git", ".godot", "outputs", "_scratch", "node_modules"}
refs = collections.Counter()
ref_where = collections.defaultdict(list)
for dp, dn, fn in os.walk("."):
    dn[:] = [d for d in dn if d not in SKIP_DIRS]
    p = dp.replace(os.sep, "/")
    if "/source/" in p + "/":
        continue
    for f in fn:
        if not f.endswith(TEXT_EXT):
            continue
        fp = os.path.join(dp, f)
        try:
            text = open(fp, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        for m in re.finditer(re.escape(ROOT) + r"/[A-Za-z0-9_/.\-]+", text):
            frag = m.group(0)
            if RUN.search(frag.split("/")[-1]) or VER_ANY.search(frag):
                key = frag.replace(ROOT + "/", "")
                if os.path.isfile(os.path.join(ROOT, key)) or True:
                    refs[key] += 1
                    if len(ref_where[key]) < 4:
                        ref_where[key].append(fp.replace("./", "", 1))

# --- 3) 输出
multi = {k: v for k, v in groups.items() if len(v) > 1}
single = {k: v for k, v in groups.items() if len(v) == 1}
print("稳定目标总数 %d；其中多候选（需定代）%d 组，单候选 %d 组"
      % (len(groups), len(multi), len(single)))
print()
print("=" * 78)
print("多候选组（collapse 会保留最高版本；★ = 该版本当前被引用）")
print("=" * 78)
mismatch = []
for target in sorted(multi):
    srcs = sorted(multi[target])
    vers = [ver(s) for s in srcs]
    keep = max(vers)
    kept_src = srcs[vers.index(keep)]
    marked = []
    for s, v in zip(srcs, vers):
        used = refs.get(s, 0)
        tag = "★引用%d" % used if used else "  未引用"
        if used:
            marked.append(v)
        print("  [%s] %-6s %s" % (tag, v, s))
    print("  -> 保留 %s : %s" % (keep, kept_src))
    used_versions = set(marked)
    if used_versions and keep not in used_versions:
        mismatch.append((target, keep, sorted(used_versions)))
        print("  !! 不一致：被引用的是 %s，却保留 %s" % (sorted(used_versions), keep))
    print()

print("=" * 78)
if mismatch:
    print("发现 %d 处「保留版本 != 被引用版本」——必须先定代：" % len(mismatch))
    for t, keep, used in mismatch:
        print("  %s\n     保留=%s  被引用=%s" % (t, keep, used))
else:
    print("未发现不一致（所有多候选组的最高版本都是被引用的那版）")
