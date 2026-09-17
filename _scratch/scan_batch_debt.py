#!/usr/bin/env python3
"""出「某套件」的去版本化欠账构成与引用分布。

用法：python3 _scratch/scan_batch_debt.py assets/art/environments/base_facility_3d

输出：
  1) 欠账构成 —— 门禁口径（`components/**` + `runtime/**`，`source/**` 豁免）
     的带版本文件数（按扩展名）与版本目录数；另列 `source/**` 的带版本文件作参考。
  2) 备份/临时残留 —— `.bak_*` 与 `*.import<digits>.tmp`。
  3) 引用分布 —— src/ tests/ tools/ scripts/ scenes/ 下引用该套件**带版本路径**的
     条数与文件数，并单列 src/（硬引用，preload 编译期解析，必须同批改）明细。

判据来源：tools/asset_pipeline/godot_runtime_naming.py 的 LEGACY_VERSIONED。
"""
import collections
import os
import re
import sys

VER_FILE = re.compile(r"_v\d{3}(?=\.[A-Za-z0-9]+$)")
VER_DIR = re.compile(r"^v\d{3}$")
GATED_SUBTREES = ("components", "runtime")
SCAN_DIRS = ("src", "tests", "tools", "scripts", "scenes")
SCAN_EXTS = (".gd", ".tscn", ".py", ".mjs")


def debt(root):
    gated = collections.Counter()
    gated_other = collections.Counter()
    src_side = collections.Counter()
    dirs = []
    residue = []
    for dp, dns, fns in os.walk(root):
        rel = os.path.relpath(dp, root).replace(os.sep, "/")
        top = rel.split("/")[0]
        for d in dns:
            if VER_DIR.match(d):
                dirs.append(rel + "/" + d)
        for f in fns:
            ext = os.path.splitext(f)[1]
            if VER_FILE.search(f):
                if top in GATED_SUBTREES:
                    # 门禁只认 components/ + runtime/ 下的 .glb / .tscn
                    if ext in (".glb", ".tscn"):
                        gated[ext] += 1
                    else:
                        gated_other[ext] += 1
                else:
                    src_side[top + "." + ext.lstrip(".")] += 1
            if ".bak" in f or re.search(r"\.import\d+\.tmp$", f):
                residue.append(rel + "/" + f)
    return gated, gated_other, src_side, dirs, residue


def collisions(root):
    """把「剥掉 _vNNN 后会同名」的文件分成两类。

    A 类（正常）= 剥离后合并，但**原始父目录相同** → 同一 slug 的多版本，
                  策略是「保留在用的那一版」，交给 deversion_batch 的 collapse 规则即可。
    B 类（真冲突）= **原始父目录不同**却映射到同一稳定路径 → 跨目录的两代资产
                  （如 foo_v017/ 与 foo_v020/），剥离后会互相覆盖，必须人工定策略。
    """
    buckets = collections.defaultdict(list)
    for dp, dns, fns in os.walk(root):
        rel = os.path.relpath(dp, root).replace(os.sep, "/")
        top = rel.split("/")[0]
        if top not in GATED_SUBTREES:
            continue
        stable_dir = "/".join(
            (re.sub(r"_v\d{3}$", "", p) if re.match(r"^env_base99_[a-z_]+_v\d{3}$", p) else p)
            for p in rel.split("/")
        )
        for f in fns:
            if not VER_FILE.search(f):
                continue
            stable_key = stable_dir + "/" + VER_FILE.sub("", f, count=1)
            buckets[stable_key].append(rel + "/" + f)

    normal, conflict = {}, {}
    for key, flist in buckets.items():
        if len(flist) < 2:
            continue
        parents = {os.path.dirname(f) for f in flist}
        (normal if len(parents) == 1 else conflict)[key] = sorted(flist)
    return normal, conflict




    hits = collections.Counter()
    detail = collections.defaultdict(list)
    for base in SCAN_DIRS:
        if not os.path.isdir(base):
            continue
        for dp, dns, fns in os.walk(base):
            for f in fns:
                if not f.endswith(SCAN_EXTS):
                    continue
                p = os.path.join(dp, f)
                try:
                    lines = open(p, encoding="utf-8", errors="replace").read().splitlines()
                except OSError:
                    continue
                for i, line in enumerate(lines, 1):
                    if root not in line:
                        continue
                    for m in re.finditer(re.escape(root) + r"/[^\"'\s)]+", line):
                        frag = m.group(0)
                        if VER_FILE.search(frag):
                            hits[p] += 1
                            detail[p].append((i, frag.rsplit("/", 1)[-1]))
                            break
    return hits, detail


def refs(root):
    hits = collections.Counter()
    detail = collections.defaultdict(list)
    for base in SCAN_DIRS:
        if not os.path.isdir(base):
            continue
        for dp, dns, fns in os.walk(base):
            for f in fns:
                if not f.endswith(SCAN_EXTS):
                    continue
                p = os.path.join(dp, f)
                try:
                    lines = open(p, encoding="utf-8", errors="replace").read().splitlines()
                except OSError:
                    continue
                for i, line in enumerate(lines, 1):
                    if root not in line:
                        continue
                    for m in re.finditer(re.escape(root) + r"/[^\"'\s)]+", line):
                        frag = m.group(0)
                        if VER_FILE.search(frag):
                            hits[p] += 1
                            detail[p].append((i, frag.rsplit("/", 1)[-1]))
                            break
    return hits, detail


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    root = sys.argv[1].rstrip("/")

    gated, gated_other, src_side, dirs, residue = debt(root)
    glbs = gated.get(".glb", 0)
    tscns = gated.get(".tscn", 0)
    # 门禁欠账口径：每个 .glb 各带一个 .glb.import，.tscn 自带无 sidecar
    implied = glbs * 2 + tscns

    print("=" * 72)
    print("套件:", root)
    print("-" * 72)
    print("门禁口径欠账（components/ + runtime/ 下的 .glb / .tscn）:")
    print("  .glb     : %d  (+ %d 个 .glb.import)" % (glbs, glbs))
    print("  .tscn    : %d" % tscns)
    print("  折算合计 : %d" % implied)
    if gated_other:
        print("  同子树内其他带版本文件（不计入门禁）:", dict(sorted(gated_other.items())))
    print("版本目录   :", len(dirs))
    for d in sorted(dirs):
        print("    ", d)
    print("source/ 侧（豁免，仅参考）:", dict(sorted(src_side.items())) or "无")
    print()
    print("备份 / 临时残留:", len(residue))
    for r in residue:
        print("    ", r)

    normal, conflict = collisions(root)
    print()
    print("-" * 72)
    print("同名收敛检查（剥掉 _vNNN 后会同路径的文件）:")
    print("  A 类 同目录多版本（正常，保留在用的那版即可）: %d 组" % len(normal))
    print("  B 类 跨目录两代并存（**真冲突，剥离会互相覆盖，须人工定策略**）: %d 组" % len(conflict))
    for key, flist in sorted(conflict.items()):
        print("    → %s" % key)
        for f in flist:
            print("        ", f)

    hits, detail = refs(root)
    print()
    print("-" * 72)
    print("引用本套件「带版本路径」的文件数 / 条数:")
    total = sum(hits.values())
    print("  合计 %d 条 / %d 个文件" % (total, len(hits)))
    for group in ("src", "tests", "tools", "scripts", "scenes"):
        sub = {k: v for k, v in hits.items() if k.replace(os.sep, "/").startswith(group)}
        if sub:
            print("  %-8s %2d 文件 / %2d 条" % (group, len(sub), sum(sub.values())))
    print()
    print("src/ 侧明细（硬引用，preload 编译期解析，必须与本批同批改）:")
    for p in sorted(k for k in hits if k.replace(os.sep, "/").startswith("src")):
        for ln, name in detail[p]:
            print("  %s:%d  %s" % (p.replace(os.sep, "/"), ln, name))
    print("=" * 72)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
