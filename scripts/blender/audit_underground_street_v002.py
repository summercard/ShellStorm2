"""地下街区 v002（编号02）—— 源审计（独立于构建脚本，从落盘 .blend 反查真实状态）。

检查项：
1. 集合四级结构（01 制作组件 / 02 游戏输出 / 03 场景拼装 / 90 展示）
2. 每个末级资产包非空、对象唯一归属（不得同时属于两个包）
3. 磁盘 component_packages 目录数 == catalog 组件数 == Blender 资产包集合数
4. 每包尺寸与 catalog 记录一致（容差 0.01m）
5. 材质数、UV 层名、活动层、色盘外链与未打包
6. 实例总数与 instances.json 一致

输出 qa/source_audit.json；有失败项退出码 1。
"""

from __future__ import annotations

import json
import os
import sys

import bpy

OUT_DIR = os.path.dirname(bpy.data.filepath)
QA = os.path.join(OUT_DIR, "qa")
os.makedirs(QA, exist_ok=True)

PALETTE = os.path.normcase(os.path.normpath(
    r"I:\工作项目\shellstrom2\ShellStorm2\assets\art\shared\palette\设施低亮多巴胺色盘_10x10_512.png"))

CATALOG = json.load(open(os.path.join(OUT_DIR, "component_catalog.json"), encoding="utf-8"))
INSTANCES = json.load(open(os.path.join(OUT_DIR, "component_instances.json"), encoding="utf-8"))
PLAN = json.load(open(os.path.join(OUT_DIR, "component_plan.json"), encoding="utf-8"))

root = bpy.context.scene.collection
top = {c.name: c for c in root.children}

report: dict = {"blend": bpy.data.filepath, "checks": {}, "detail": {}}

# ---- 1. 四级结构
need_prefix = ("01_制作组件", "02_游戏输出", "03_场景拼装", "90_展示")
found = [name for p in need_prefix for name in top if name.startswith(p)]
report["checks"]["four_level_collections"] = len(found) == 4
report["detail"]["top_collections"] = sorted(top)

src_root = next(c for c in root.children if c.name.startswith("01_制作组件"))
pkg_root = next(c for c in root.children if c.name.startswith("02_游戏输出"))
layout_root = next(c for c in root.children if c.name.startswith("03_场景拼装"))

# ---- 2/4. 末级包
pkg_colls = {c.name.replace("资产包_", ""): c for c in pkg_root.children}
src_colls = {c.name.replace("组件源_", ""): c for c in src_root.children}
empty_pkgs = [k for k, c in pkg_colls.items() if not [o for o in c.all_objects if o.type == "MESH"]]
counts: dict[str, int] = {}
for coll in pkg_colls.values():
    for obj in coll.all_objects:
        counts[obj.name] = counts.get(obj.name, 0) + 1
multi = {n: c for n, c in counts.items() if c > 1}

catalog_slugs = [c["slug"] for c in CATALOG["components"]]
disk = sorted(d for d in os.listdir(os.path.join(OUT_DIR, "component_packages"))
              if os.path.isdir(os.path.join(OUT_DIR, "component_packages", d)))
manifest_missing = [d for d in disk
                    if not os.path.isfile(os.path.join(OUT_DIR, "component_packages", d, "asset_manifest.json"))]

report["checks"]["no_empty_package"] = not empty_pkgs
report["checks"]["object_single_owner"] = not multi
report["checks"]["package_collection_count_matches_catalog"] = (
    len(pkg_colls) == len(src_colls) == len(catalog_slugs))
report["checks"]["disk_manifests_match_catalog"] = (sorted(catalog_slugs) == disk and not manifest_missing)
report["detail"]["empty_packages"] = empty_pkgs
report["detail"]["multi_owner_objects"] = multi
report["detail"]["package_count"] = {"collections": len(pkg_colls), "sources": len(src_colls),
                                     "catalog": len(catalog_slugs), "disk": len(disk)}
report["detail"]["missing_manifests"] = manifest_missing

# 尺寸核对
dim_mismatch = []
for entry in CATALOG["components"]:
    slug = entry["slug"]
    coll = pkg_colls.get(slug)
    if coll is None:
        dim_mismatch.append({"slug": slug, "reason": "collection missing"})
        continue
    xs, ys, zs = [], [], []
    for obj in coll.all_objects:
        if obj.type != "MESH" or not obj.data.vertices:
            continue
        for v in obj.data.vertices:
            co = obj.matrix_world @ v.co
            xs.append(co.x)
            ys.append(co.y)
            zs.append(co.z)
    if not xs:
        dim_mismatch.append({"slug": slug, "reason": "no vertices"})
        continue
    dims = [round(max(xs) - min(xs), 3), round(max(ys) - min(ys), 3), round(max(zs) - min(zs), 3)]
    expect = entry["dimensions_m"]
    if any(abs(a - b) > 0.011 for a, b in zip(dims, expect)):
        dim_mismatch.append({"slug": slug, "actual": dims, "expected": expect})
    if abs(min(zs)) > 0.011:
        dim_mismatch.append({"slug": slug, "reason": "base not at z=0", "min_z": round(min(zs), 4)})
report["checks"]["dimensions_and_pivot_match"] = not dim_mismatch
report["detail"]["dimension_mismatches"] = dim_mismatch

# ---- 3. 实例
inst_empties = [o for c in layout_root.children for o in c.all_objects if o.type == "EMPTY"]
report["checks"]["instance_count_matches_json"] = len(inst_empties) == INSTANCES["total_instance_count"] \
    if "total_instance_count" in INSTANCES else len(inst_empties) == len(INSTANCES["instances"])
report["detail"]["instances"] = len(inst_empties)

# ---- 5. 材质 / UV
mats = sorted(m.name for m in bpy.data.materials)
used = sorted({m.name for o in bpy.context.scene.objects if o.type == "MESH" for m in o.data.materials if m})
packed = [i.name for i in bpy.data.images if i.packed_file is not None]
bad_path = []
bad_closest = []
bad_layer = []
extra_uv = []
for m in bpy.data.materials:
    if not m.use_nodes:
        continue
    for n in m.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image is not None:
            if n.interpolation != "Closest":
                bad_closest.append(m.name)
            path = os.path.normcase(os.path.normpath(bpy.path.abspath(n.image.filepath)))
            if path != PALETTE:
                bad_path.append({"material": m.name, "path": path})
for o in bpy.context.scene.objects:
    if o.type != "MESH":
        continue
    uv = o.data.uv_layers
    if "PaletteUV" not in [u.name for u in uv]:
        bad_layer.append({"object": o.name, "reason": "missing PaletteUV"})
        continue
    if uv.active.name != "PaletteUV" or not uv["PaletteUV"].active_render:
        bad_layer.append({"object": o.name, "reason": "not active/active_render"})
    others = [u.name for u in uv if u.name != "PaletteUV"]
    if others:
        extra_uv.append({"object": o.name, "layers": others})

report["checks"]["materials_at_most_12"] = len(used) <= 12
report["checks"]["no_unused_materials"] = len(mats) == len(used)
report["checks"]["palette_external_unpacked"] = not packed and not bad_path
report["checks"]["palette_closest"] = not bad_closest
report["checks"]["palette_uv_active_everywhere"] = not bad_layer and not extra_uv
report["detail"]["materials"] = used
report["detail"]["packed_images"] = packed
report["detail"]["non_palette_images"] = bad_path
report["detail"]["uv_problems"] = bad_layer
report["detail"]["extra_uv"] = extra_uv

# ---- 6. 组件预算
fam = {k: len(v) for k, v in PLAN["families"].items()}
report["checks"]["unique_components_within_50"] = len(catalog_slugs) <= 50
report["checks"]["family_within_3"] = all(n <= 3 for n in fam.values())
report["detail"]["unique_components"] = len(catalog_slugs)
report["detail"]["families"] = fam
report["detail"]["over_budget_families"] = {k: n for k, n in fam.items() if n > 3}

report["passed"] = all(report["checks"].values())
with open(os.path.join(QA, "source_audit.json"), "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)

print("AUDIT_PASSED", report["passed"])
for k, v in report["checks"].items():
    print(("OK   " if v else "FAIL "), k)
sys.exit(0 if report["passed"] else 1)
