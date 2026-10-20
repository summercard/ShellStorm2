"""颗粒度审计 —— 把「0.1m 颗粒」变成可量化、可门禁的指标。

为什么需要这个工具
------------------
v003 的验收靠的是「近景渲染看着还行」，结果是：三栋主体楼做到 2k–6.7k 面，
轿车 176 面、路灯 96 面、空调外机 44 面 —— 目视远景分不出来，近景一放大就是
几个盒子拼的。凡是不能量化的验收标准，最后一定退化成「我觉得还行」。

指标口径（改过一版，记下来免得再走弯路）
----------------------------------------
第一版用「面数 / 表面积」做面密度，跑出来所有组件都失真：项目里的零件是一个个
独立闭合盒叠出来的，内部重叠面全部计入 `calc_area()`（药店 4145 面算出 2180 m²，
而它外表面只有约 600 m²）。**内部面积不可度量，所以不能用面积归一化**。

改成按**尺寸**归一化，这也正是业主的原话「0.1 米颗粒度」：

1. **island scale**：把网格按顶点连通拆成独立零件，取每个零件 AABB 最大边长 `s`。
   - `fine_count`：`s ≤ 0.20m` 的零件个数 —— 这就是「0.1m 级零件」的直接计数。
   - `p50`：零件尺寸中位数 —— 用来识别「整根杆当一根圆柱」「整车当两个盒子」。

2. **零件密度按包围盒最大边长 L 折算**（不用面积）：
   - `islands ≥ max(12, 8 × L)`：每米尺寸至少 8 个零件。
   - `fine_count ≥ max(6, 4 × L)`：每米尺寸至少 4 个 0.1m 级零件。
   L=4.7 的轿车 → 至少 38 个零件、其中 19 个是 0.1m 级；L=7 的路灯 → 56 / 28。

3. `p90`：90% 零件尺寸上限，用于识别「全是大块」。

用法
----
    blender --background <blend> --python audit_granularity.py -- \
        --collection-prefix 资产包_ --json out.json [--min-faces 60]

输出每个组件的 `islands / fine_count / p50 / p90` 与判定。只读，不修改 blend。
"""

import argparse
import json
import os
import sys

import bpy
import bmesh
from mathutils import Vector


# 门槛：写在文件顶部，改门槛必须同时改这里，避免每次临时放宽
THRESHOLDS = {
    "islands_per_m": 8.0,     # 每米包围盒最大边长对应的最少零件数
    "fine_per_m": 4.0,        # 每米对应的最少 0.1m 级零件数（s <= 0.20m）
    "fine_abs_min": 6,        # 0.1m 级零件的绝对下限
    "islands_abs_min": 12,    # 零件总数绝对下限
    "p50_max": 0.90,          # 中位零件尺寸上限（仅对道具类判定，见 PROP_MAX_DIM）
}

# 包围盒最大边长小于此值的算「道具」，否则算「建筑体量」。
# 建筑允许有整面墙这种大零件，所以不判 p50，只判零件数与细颗粒数。
PROP_MAX_DIM = 6.0

# 这些组件本身就是「单一大面」，不该按零件尺寸要求（地面/墙/顶棚/水洼/贴花）
FLAT_SLUG_PREFIX = (
    "wet_", "puddle_", "sidewalk_tile", "road_paint", "street_pavement",
    "cavern_", "ceiling_truss", "tunnel_portal",
)


def collect_meshes(prefix):
    """按资产包 collection 归组 mesh：{slug: [obj, ...]}"""
    out = {}
    for coll in bpy.data.collections:
        if not coll.name.startswith(prefix):
            continue
        slug = coll.name[len(prefix):]
        objs = [o for o in coll.all_objects if o.type == "MESH"]
        if objs:
            out.setdefault(slug, []).extend(objs)
    return out


def island_stats(objs):
    """把一个资产包内所有 mesh 拆成零件，返回 (island_sizes, polys, area)"""
    sizes = []
    total_polys = 0
    area = 0.0
    for obj in objs:
        me = obj.data
        if not me.polygons:
            continue
        bm = bmesh.new()
        bm.from_mesh(me)
        bm.faces.ensure_lookup_table()
        total_polys += len(bm.faces)
        for f in bm.faces:
            area += f.calc_area()
        # 拆连通岛：按顶点连通做并查集（比 bmesh.ops.split_by_connectivity 轻，
        # 不需要真的切网格，也就不会破坏原数据）
        parent = list(range(len(bm.verts)))
        bm.verts.ensure_lookup_table()

        def find(a):
            while parent[a] != a:
                parent[a] = parent[parent[a]]
                a = parent[a]
            return a

        def union(a, b):
            ra, rb = find(a), find(b)
            if ra != rb:
                parent[rb] = ra

        for e in bm.edges:
            union(e.verts[0].index, e.verts[1].index)
        groups = {}
        for v in bm.verts:
            groups.setdefault(find(v.index), []).append(v.co)
        for coords in groups.values():
            xs = [c.x for c in coords]
            ys = [c.y for c in coords]
            zs = [c.z for c in coords]
            sizes.append(max(max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)))
        bm.free()
    return sizes, total_polys, area


def pct(sorted_vals, q):
    if not sorted_vals:
        return 0.0
    i = min(len(sorted_vals) - 1, int(round(q * (len(sorted_vals) - 1))))
    return sorted_vals[i]


def main():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--collection-prefix", default="资产包_")
    ap.add_argument("--json", default="")
    ap.add_argument("--min-faces", type=int, default=60,
                    help="面数低于此值的组件不参与颗粒度判定（地面贴花等）")
    args = ap.parse_args(argv)

    groups = collect_meshes(args.collection_prefix)
    rows = []
    for slug, objs in sorted(groups.items()):
        sizes, polys, area = island_stats(objs)
        if not sizes:
            continue
        s = sorted(sizes)
        n = len(s)
        # 组件包围盒最大边长：用 mesh 顶点总包围盒近似
        lo = [1e9, 1e9, 1e9]
        hi = [-1e9, -1e9, -1e9]
        for obj in objs:
            for v in obj.data.vertices:
                for k in range(3):
                    lo[k] = min(lo[k], v.co[k])
                    hi[k] = max(hi[k], v.co[k])
        L = max(hi[k] - lo[k] for k in range(3))
        fine = len([v for v in s if v <= 0.20])
        row = {
            "slug": slug,
            "islands": n,
            "fine_count": fine,
            "polys": polys,
            "bbox_max_m": round(L, 2),
            "p10": round(pct(s, 0.10), 3),
            "p50": round(pct(s, 0.50), 3),
            "p90": round(pct(s, 0.90), 3),
            "islands_per_m": round(n / L, 2) if L > 1e-6 else 0.0,
            "fine_per_m": round(fine / L, 2) if L > 1e-6 else 0.0,
            "exempt_flat": slug.startswith(FLAT_SLUG_PREFIX),
        }
        fails = []
        if row["exempt_flat"] or polys < args.min_faces:
            row["skipped"] = True
        else:
            need_isl = max(THRESHOLDS["islands_abs_min"],
                           int(round(THRESHOLDS["islands_per_m"] * L)))
            need_fine = max(THRESHOLDS["fine_abs_min"],
                            int(round(THRESHOLDS["fine_per_m"] * L)))
            if n < need_isl:
                fails.append("islands=%d<%d" % (n, need_isl))
            if fine < need_fine:
                fails.append("fine=%d<%d" % (fine, need_fine))
            if L <= PROP_MAX_DIM and row["p50"] > THRESHOLDS["p50_max"]:
                fails.append("p50=%.2f>%.2f" % (row["p50"], THRESHOLDS["p50_max"]))
        row["fails"] = fails
        rows.append(row)

    judged = [r for r in rows if not r.get("skipped")]
    failed = [r for r in judged if r["fails"]]
    out = {
        "passed": not failed,
        "thresholds": THRESHOLDS,
        "prop_max_dim": PROP_MAX_DIM,
        "component_count": len(rows),
        "judged_count": len(judged),
        "failed_count": len(failed),
        "components": rows,
    }
    print("GRANULARITY_PASSED" if out["passed"] else "GRANULARITY_FAILED",
          "judged=%d failed=%d" % (len(judged), len(failed)))
    print("%-40s %5s %5s %5s %5s %6s %6s %s"
          % ("slug", "isl", "fine", "need", "polys", "L", "p50", "fails"))
    for r in sorted(rows, key=lambda x: x["fine_per_m"]):
        flag = "FAIL" if r["fails"] else ("  - " if r.get("skipped") else " ok ")
        need = max(THRESHOLDS["fine_abs_min"],
                   int(round(THRESHOLDS["fine_per_m"] * r["bbox_max_m"])))
        print("%s %-38s %5d %5d %5d %6d %6.1f %6.2f  %s"
              % (flag, r["slug"][:38], r["islands"], r["fine_count"], need,
                 r["polys"], r["bbox_max_m"], r["p50"], " ".join(r["fails"])))
    if args.json:
        os.makedirs(os.path.dirname(os.path.abspath(args.json)), exist_ok=True)
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(out, f, ensure_ascii=False, indent=2)
        print("JSON", args.json)


main()
