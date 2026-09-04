#!/usr/bin/env python3
"""Additive-only completion pass on the user's Base 99 v015 scene."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector

PROJECT = Path("/Users/summercards/ShellStorm2")
INPUT_BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v015.blend"
OUTPUT_BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v016.blend"
PACKAGE_ROOT = PROJECT / "source/art/blender/base_facility_layout/component_packages_v016"
VERIFY = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v016"
CATALOG = VERIFY / "base_facility_component_catalog_v016.json"
TREE = VERIFY / "base_facility_component_tree_v016.txt"
LOCK_REPORT = VERIFY / "base_facility_locked_scope_v015_v016.json"

spec = importlib.util.spec_from_file_location("base_v011", PROJECT / "scripts/blender/build_base_facility_runtime_layout_hq_v011.py")
v011 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v011)
base = v011.base


def setup():
    base.SOURCE = bpy.data.collections["01_制作组件_已统一材质"]
    base.SOURCE.hide_viewport = False
    base.SOURCE.hide_render = True
    root = next(c for c in bpy.data.collections if c.name.startswith("02_游戏输出_独立资产包"))
    base.OUTPUT = root
    base.MATS.clear()
    base.MATS.update({
        "metal": bpy.data.materials["01_精工金属_紫色骨架"],
        "matte": bpy.data.materials["02_细腻哑光_青绿大面"],
        "gloss": bpy.data.materials["03_清漆反光_紫粉点缀"],
        "emit": bpy.data.materials["04_柔和自发光_UI灯光"],
    })
    return root


def packages(root):
    result = []
    def walk(coll):
        if coll.get("资产包"):
            result.append(coll)
        for child in coll.children:
            walk(child)
    walk(root)
    return result


def find_package(root, slug):
    return next(c for c in packages(root) if c.get("资产包键") == slug)


def mark(obj):
    obj["v016_scope"] = "additive_facility_finish_only"
    obj["source_baseline"] = "user_v015_locked"
    return obj


def box(n, l, s, role, color, coll, bevel=.025, rot=(0, 0, 0)):
    return mark(v011.box(n, l, s, role, color, coll, bevel, rot=rot))


def cyl(n, l, rad, depth, role, color, coll, verts=16, rot=(0, 0, 0)):
    return mark(v011.cyl(n, l, rad, depth, role, color, coll, verts, rot))


def beam(n, a, b, thick, role, color, coll):
    return mark(v011.beam(n, a, b, thick, role, color, coll))


def torus(n, l, major, minor, role, color, coll, rot=(0, 0, 0)):
    return mark(v011.torus(n, l, major, minor, role, color, coll, rot))


def original_signature(obj):
    mesh = None
    if obj.type == "MESH":
        coords = tuple(round(float(c), 6) for v in obj.data.vertices for c in v.co)
        mesh = {
            "vertices": len(obj.data.vertices),
            "edges": len(obj.data.edges),
            "polygons": len(obj.data.polygons),
            "coordinates": hashlib.sha256(repr(coords).encode()).hexdigest(),
            "materials": [m.name if m else None for m in obj.data.materials],
            "face_materials": hashlib.sha256(bytes(p.material_index % 256 for p in obj.data.polygons)).hexdigest(),
        }
    modifiers = [(m.name, m.type, tuple(sorted((k, repr(v)) for k, v in m.items()))) for m in obj.modifiers]
    animation = []
    if obj.animation_data and obj.animation_data.action:
        for fc in obj.animation_data.action.fcurves:
            animation.append((fc.data_path, fc.array_index, tuple((round(k.co.x, 4), round(k.co.y, 6)) for k in fc.keyframe_points)))
    return {
        "type": obj.type,
        "parent": obj.parent.name if obj.parent else None,
        # Local transforms are the authored truth.  Hidden source objects in the
        # 4.5-authored baseline report an identity matrix_world until Blender 4.2
        # refreshes its dependency graph, so matrix_world is not a stable lock key.
        "location": [round(float(c), 7) for c in obj.location],
        "rotation_mode": obj.rotation_mode,
        "rotation_euler": [round(float(c), 7) for c in obj.rotation_euler],
        "rotation_quaternion": [round(float(c), 7) for c in obj.rotation_quaternion],
        "scale": [round(float(c), 7) for c in obj.scale],
        "delta_location": [round(float(c), 7) for c in obj.delta_location],
        "delta_rotation_euler": [round(float(c), 7) for c in obj.delta_rotation_euler],
        "delta_scale": [round(float(c), 7) for c in obj.delta_scale],
        "mesh": mesh,
        "modifiers": modifiers,
        "animation": animation,
    }


def capture_originals():
    return {obj.name: original_signature(obj) for obj in bpy.data.objects}


def add_bed_finish(root):
    coll = find_package(root, "loft_bed_and_bedding")
    # Soft border and restrained folded foot blanket, attached without changing the authored bed.
    box("v016_床罩脚端折叠毯", (2.02, 11.25, 7.18), (.48, 1.72, .15), "matte", "teal", coll, .07)
    for py in (10.48, 12.02):
        box(f"v016_折叠毯包边_{py}", (2.02, py, 7.24), (.46, .035, .035), "matte", "light_gray", coll, .008)
    for idx, py in enumerate((10.78, 11.62)):
        # Four piping segments make the pillows read as sewn soft assets in the reference camera.
        for zoff in (-.085, .085):
            box(f"v016_枕头{idx+1:02d}_横向缝线_{zoff}", (-1.45, py - .34, 7.19 + zoff), (.72, .018, .018), "matte", "mid_gray", coll, .004)
        for xoff in (-.39, .39):
            box(f"v016_枕头{idx+1:02d}_侧向缝线_{xoff}", (-1.45 + xoff, py - .34, 7.19), (.018, .018, .16), "matte", "mid_gray", coll, .004)
    # Low, tidy slippers remain under the bed edge and do not reduce circulation.
    for idx, x in enumerate((-.25, .25)):
        box(f"v016_床边拖鞋_{idx+1:02d}", (x, 9.94, 6.16), (.38, .62, .10), "matte", "dark_gray", coll, .09, rot=(0, 0, -.05 if idx else .06))
        box(f"v016_床边拖鞋内衬_{idx+1:02d}", (x, 9.90, 6.22), (.25, .38, .035), "matte", "warm_gray", coll, .04, rot=(0, 0, -.05 if idx else .06))


def add_curtain_finish(root):
    coll = find_package(root, "loft_striped_privacy_curtain")
    for idx, py in enumerate((11.05, 11.40, 11.76, 12.11, 12.47, 12.82, 13.18, 13.53)):
        torus(f"v016_隔断帘金属吊环_{idx+1:02d}", (3.55, py, 8.63), .09, .018, "metal", "light_gray", coll, (math.pi / 2, 0, 0))
        box(f"v016_隔断帘底部配重片_{idx+1:02d}", (3.55, py, 6.68), (.085, .27, .055), "metal", "dark_gray", coll, .012)
    # Small wall hook and loose tie, kept within the divider envelope.
    beam("v016_隔断帘收束带", (3.49, 13.42, 7.55), (3.44, 13.62, 7.55), .026, "matte", "orange", coll)
    cyl("v016_隔断帘墙面挂钩", (3.43, 13.68, 7.55), .035, .11, "metal", "light_gray", coll, 12, (math.pi / 2, 0, 0))


def add_sofa_finish(root):
    coll = find_package(root, "loft_lounge_sofa")
    # Dark piping emphasizes the three-seat Q-style modular silhouette.
    for idx, px in enumerate((4.94, 6.25, 7.56)):
        for xoff in (-.53, .53):
            box(f"v016_沙发座垫{idx+1:02d}_侧缝_{xoff}", (px + xoff, 11.51, 6.84), (.018, .74, .025), "matte", "dark_gray", coll, .004)
        for xoff in (-.53, .53):
            box(f"v016_沙发靠垫{idx+1:02d}_侧缝_{xoff}", (px + xoff, 12.57, 7.34), (.018, .025, .86), "matte", "dark_gray", coll, .004, rot=(-.10, 0, 0))
    # One folded throw adds life without changing furniture placement.
    box("v016_沙发扶手折叠毯", (8.18, 12.14, 7.39), (.44, 1.08, .10), "matte", "purple", coll, .06, rot=(0, -.08, 0))
    for y in (11.82, 12.15, 12.48):
        box(f"v016_沙发折叠毯细纹_{y}", (8.13, y, 7.455), (.35, .018, .015), "matte", "magenta", coll, .003)


def add_coffee_table_finish(root):
    coll = find_package(root, "loft_coffee_table")
    box("v016_茶几下层置物板", (6.20, 9.38, 6.36), (2.38, .88, .09), "matte", "dark_gray", coll, .045)
    box("v016_茶几下层收纳盒", (5.72, 9.38, 6.48), (.66, .52, .20), "matte", "teal", coll, .055)
    for idx, x in enumerate((6.55, 6.80)):
        cyl(f"v016_茶几杯垫_{idx+1:02d}", (x, 9.45, 6.86), .12, .018, "gloss", "orange", coll, 20)


def add_workstation_finish(root):
    coll = find_package(root, "loft_computer_workstation")
    # Articulated warm task lamp, consistent with the reference workstation silhouette.
    cyl("v016_工位任务灯底座", (8.96, 13.25, 7.02), .16, .055, "metal", "dark_gray", coll, 18)
    beam("v016_工位任务灯下臂", (8.96, 13.25, 7.06), (8.78, 13.36, 7.48), .035, "metal", "light_gray", coll)
    beam("v016_工位任务灯上臂", (8.78, 13.36, 7.48), (8.95, 13.28, 7.78), .035, "metal", "light_gray", coll)
    box("v016_工位任务灯灯头_自发光", (9.04, 13.19, 7.81), (.34, .20, .13), "emit", "orange", coll, .065, rot=(0, -.22, 0))
    box("v016_工位鼠标垫", (11.16, 13.14, 6.985), (.58, .48, .025), "matte", "purple", coll, .045)
    for idx, x in enumerate((9.70, 11.17)):
        for side in (-1, 1):
            cyl(f"v016_显示器{idx+1:02d}_状态点_{side}_自发光", (x + side * .47, 13.895, 7.33), .025, .018, "emit", "cyan", coll, 10, (math.pi / 2, 0, 0))
        beam(f"v016_显示器{idx+1:02d}_下行电缆", (x, 14.08, 7.20), (x, 14.08, 6.84), .018, "metal", "dark_gray", coll)
    # Cable tray is attached behind the desk, clear of the chair and path.
    box("v016_工位后置线缆托盘", (10.45, 14.12, 6.62), (2.35, .18, .16), "metal", "dark_gray", coll, .035)
    for i, color in enumerate(("cyan", "orange", "green")):
        beam(f"v016_工位托盘线束_{i+1:02d}", (9.50, 14.01, 6.63 + i * .035), (11.42, 14.01, 6.63 + i * .035), .014, "metal", color, coll)


def add_storage_icons(root):
    specs = (
        ("loft_medical_cabinet", -3.25, "MEDICAL", "red"),
        ("loft_battery_cabinet", -1.95, "BATTERY", "teal"),
        ("loft_food_cabinet", -.65, "FOOD", "orange"),
    )
    for slug, x, label, color in specs:
        coll = find_package(root, slug)
        if label == "MEDICAL":
            box("v016_MEDICAL箱_十字横", (x, 13.405, 6.31), (.34, .025, .09), "matte", "light_gray", coll, .018)
            box("v016_MEDICAL箱_十字竖", (x, 13.404, 6.31), (.09, .025, .34), "matte", "light_gray", coll, .018)
        elif label == "BATTERY":
            box("v016_BATTERY箱_电池轮廓", (x, 13.405, 6.31), (.38, .025, .24), "metal", "light_gray", coll, .035)
            box("v016_BATTERY箱_电池正极", (x + .23, 13.404, 6.31), (.08, .026, .10), "metal", "light_gray", coll, .018)
            for idx, bx in enumerate((x - .11, x, x + .11)):
                box(f"v016_BATTERY箱_电量格_{idx+1:02d}_自发光", (bx, 13.385, 6.31), (.07, .015, .13), "emit", "cyan", coll, .012)
        else:
            cyl("v016_FOOD箱_餐盘图标", (x, 13.405, 6.28), .18, .025, "matte", "light_gray", coll, 20, (math.pi / 2, 0, 0))
            box("v016_FOOD箱_餐盘高光_自发光", (x, 13.38, 6.35), (.20, .012, .035), "emit", color, coll, .006)


def add_stair_interface_fasteners(root):
    west = find_package(root, "northwest_l_stair")
    east = find_package(root, "east_upper_transition_stair")
    # Bolts sit on existing seam plates. No authored stair object is transformed.
    for idx, (x, y) in enumerate(((-4.90, 13.15), (-4.90, 14.45), (-4.74, 13.15), (-4.74, 14.45))):
        cyl(f"v016_西梯顶层接缝螺栓_{idx+1:02d}", (x, y, 6.142), .028, .022, "metal", "orange", west, 10)
    for idx, (x, y) in enumerate(((12.62, 10.20), (13.94, 10.20), (12.48, 14.34), (14.08, 14.34))):
        z = 6.12 if idx < 2 else 8.77
        cyl(f"v016_东梯接口螺栓_{idx+1:02d}", (x, y, z), .030, .022, "metal", "orange", east, 10)
    # Two restrained chevrons at the east stair entrance improve route readability.
    for idx, x in enumerate((12.95, 13.40)):
        beam(f"v016_东梯入口导向左_{idx+1:02d}", (x - .12, 10.12, 6.125), (x, 10.02, 6.125), .025, "matte", "orange", east)
        beam(f"v016_东梯入口导向右_{idx+1:02d}", (x, 10.02, 6.125), (x + .12, 10.12, 6.125), .025, "matte", "orange", east)


def organize_v016_sources(root):
    """Mirror every new editable source into its facility-specific source folder."""
    source_root = base.SOURCE
    mirror_root = bpy.data.collections.get("v016_新增制作源_按设施归类") or bpy.data.collections.new("v016_新增制作源_按设施归类")
    if mirror_root.name not in source_root.children:
        source_root.children.link(mirror_root)
    mirror_root["组织版本"] = "v016"
    mirror_root["用途"] = "按独立设施镜像归类的可编辑源组件"
    organized = 0
    for pkg in packages(root):
        outputs = [obj for obj in pkg.objects if obj.get("v016_scope")]
        if not outputs:
            continue
        slug = pkg.get("资产包键", pkg.name)
        category = pkg.get("资产类别", "uncategorized")
        category_coll = bpy.data.collections.get(f"v016_源类别_{category}") or bpy.data.collections.new(f"v016_源类别_{category}")
        if category_coll.name not in mirror_root.children:
            mirror_root.children.link(category_coll)
        source_pkg_name = f"v016_源资产包_{slug}"
        source_pkg = bpy.data.collections.get(source_pkg_name) or bpy.data.collections.new(source_pkg_name)
        if source_pkg.name not in category_coll.children:
            category_coll.children.link(source_pkg)
        source_pkg["对应成品资产包键"] = slug
        source_pkg["资产类别"] = category
        for out in outputs:
            src = bpy.data.objects.get(out.name + "__源")
            if src is None:
                continue
            for owner in list(src.users_collection):
                owner.objects.unlink(src)
            source_pkg.objects.link(src)
            src["v016_scope"] = "additive_facility_finish_only"
            src["source_baseline"] = "user_v015_locked"
            src["对应成品资产包键"] = slug
            organized += 1
    return organized


def bbox(objects):
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box] if objects else []
    if not points:
        return [0, 0, 0], [0, 0, 0]
    lo = [min(p[i] for p in points) for i in range(3)]
    hi = [max(p[i] for p in points) for i in range(3)]
    return [round((lo[i] + hi[i]) / 2, 4) for i in range(3)], [round(hi[i] - lo[i], 4) for i in range(3)]


def write_catalog(root):
    VERIFY.mkdir(parents=True, exist_ok=True)
    entries = []
    for pkg in sorted(packages(root), key=lambda c: c.name):
        slug = pkg.get("资产包键", pkg.name)
        category = pkg.get("资产类别", "uncategorized")
        folder = PACKAGE_ROOT / category / slug
        folder.mkdir(parents=True, exist_ok=True)
        objs = sorted(pkg.objects, key=lambda o: o.name)
        center, size = bbox(objs)
        entry = {
            "asset_id": "ENV-BASE99-ART-LAYOUT-3D",
            "package_id": f"ENV-BASE99-ART-LAYOUT-3D::{slug}",
            "display_name": pkg.name,
            "asset_slug": slug,
            "category": category,
            "version": "v016",
            "source_blend": str(OUTPUT_BLEND.relative_to(PROJECT)),
            "object_count": len(objs),
            "mesh_count": sum(o.type == "MESH" for o in objs),
            "light_count": sum(o.type == "LIGHT" for o in objs),
            "object_names": [o.name for o in objs],
            "world_center_m": center,
            "bounding_size_m": size,
            "forward_axis": "Blender +Y north",
            "baseline_policy": "all v015 objects locked; v016 is additive only",
            "v016_added_object_count": sum(bool(o.get("v016_scope")) for o in objs),
            "editable_source_folder": f"01_制作组件_已统一材质/v016_新增制作源_按设施归类/v016_源类别_{category}/v016_源资产包_{slug}",
            "expected_export": f"{slug}_visual_top3d_v001.glb",
            "collision_status": "not_authored_in_this_partial_blender_pass",
            "export_status": "not_exported",
        }
        (folder / "asset_manifest.json").write_text(json.dumps(entry, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        entries.append(entry)
    doc = {
        "schema": "shellstorm2.base_facility.component_catalog.v2",
        "organization_version": "v016",
        "source_asset_id": "ENV-BASE99-ART-LAYOUT-3D",
        "scope": "additive facility completion on user-authored v015 baseline",
        "baseline_object_policy": "all 5870 v015 objects locked",
        "package_count": len(entries),
        "floor_tile_package_count": sum(e["category"] == "floor" for e in entries),
        "packages": entries,
    }
    CATALOG.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    TREE.write_text("基地场景独立资产包树 v016\n" + "\n".join(f"{e['category']}/{e['asset_slug']} objects={e['object_count']} added_v016={e['v016_added_object_count']}" for e in entries) + "\n", encoding="utf-8")
    (PACKAGE_ROOT / "README.md").write_text(
        "# Base Facility component packages v016\n\n"
        "This package mirror is generated from the user-authored v015 Blender baseline. "
        "Every original v015 object is locked; v016 only adds facility-attached finishing details.\n",
        encoding="utf-8",
    )
    return doc


def render(camera_name, filename, x=1672, y=941):
    scene = bpy.context.scene
    scene.camera = bpy.data.objects[camera_name]
    scene.render.filepath = str(VERIFY / filename)
    scene.render.resolution_x = x
    scene.render.resolution_y = y
    scene.render.resolution_percentage = 100
    bpy.ops.render.render(write_still=True)


def main():
    if Path(bpy.data.filepath).resolve() != INPUT_BLEND.resolve():
        raise RuntimeError("must start from user v015")
    if OUTPUT_BLEND.exists():
        raise RuntimeError(f"target already exists: {OUTPUT_BLEND}")
    root = setup()
    before = capture_originals()
    add_bed_finish(root)
    add_curtain_finish(root)
    add_sofa_finish(root)
    add_coffee_table_finish(root)
    add_workstation_finish(root)
    add_storage_icons(root)
    add_stair_interface_fasteners(root)
    organized_sources = organize_v016_sources(root)
    after = {name: original_signature(bpy.data.objects[name]) for name in before if name in bpy.data.objects}
    changed = sorted(name for name in before if name in after and before[name] != after[name])
    removed = sorted(set(before) - set(after))
    if changed or removed:
        debug = {}
        for name in changed[:20]:
            debug[name] = {
                key: {"before": before[name][key], "after": after[name][key]}
                for key in before[name]
                if before[name][key] != after[name][key]
            }
        print("V015_LOCK_DEBUG=" + json.dumps(debug, ensure_ascii=False, sort_keys=True))
        raise RuntimeError(f"v015 lock violation changed={changed[:8]} removed={removed[:8]}")
    added = sorted(obj.name for obj in bpy.data.objects if obj.name not in before)
    doc = write_catalog(root)
    before_hash = hashlib.sha256(json.dumps(before, sort_keys=True).encode()).hexdigest()
    after_hash = hashlib.sha256(json.dumps(after, sort_keys=True).encode()).hexdigest()
    LOCK_REPORT.write_text(json.dumps({
        "input": str(INPUT_BLEND.relative_to(PROJECT)),
        "output": str(OUTPUT_BLEND.relative_to(PROJECT)),
        "policy": "all existing v015 objects are immutable; additions only",
        "locked_object_count_v015": len(before),
        "locked_object_count_v016": len(after),
        "locked_match": before == after,
        "locked_changed": changed,
        "locked_removed": removed,
        "locked_signature_v015": before_hash,
        "locked_signature_v016": after_hash,
        "v016_added_object_count_including_sources": len(added),
        "v016_added_names": added,
        "v016_organized_source_count": organized_sources,
        "package_count": doc["package_count"],
        "floor_tile_package_count": doc["floor_tile_package_count"],
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    bpy.context.scene["v016_scope"] = "基于用户v015的纯新增设施细节补完"
    bpy.context.scene["v016_lock_policy"] = "v015全部5870对象不可修改"
    bpy.context.scene["v016_added_object_count_including_sources"] = len(added)
    bpy.context.scene["v016_package_count"] = doc["package_count"]
    bpy.context.scene["v016_organized_source_count"] = organized_sources
    base.SOURCE.hide_viewport = True
    base.SOURCE.hide_render = True
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    render("基地二楼_参考图高还原验收相机_v011", "base_facility_runtime_layout_hq_v016_reference_match.png")
    render("基地二楼_设施细节验收相机_v011", "base_facility_runtime_layout_hq_v016_loft_detail.png")
    render("楼梯下设施_高还原验收相机_v014", "base_facility_runtime_layout_hq_v016_stair_detail.png", 1600, 1000)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    print(f"BASE_FACILITY_V016_BUILT locked={len(before)} added={len(added)} packages={doc['package_count']}")


if __name__ == "__main__":
    main()
