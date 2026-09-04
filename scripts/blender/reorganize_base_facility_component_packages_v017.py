#!/usr/bin/env python3
"""Collection-only v017 asset-package reorganization from locked v016."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import bpy
from mathutils import Vector

PROJECT = Path("/Users/summercards/ShellStorm2")
INPUT = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v016.blend"
OUTPUT = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
PACKAGE_ROOT = PROJECT / "source/art/blender/base_facility_layout/component_packages_v017"
VERIFY = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v017"
CATALOG = VERIFY / "base_facility_component_catalog_v017.json"
TREE = VERIFY / "base_facility_component_tree_v017.txt"
REPORT = VERIFY / "base_facility_reorganization_v016_v017.json"


def packages():
    return [c for c in bpy.data.collections if c.get("资产包")]


def package_by_slug(slug):
    return next(c for c in packages() if c.get("资产包键") == slug)


def collection_parent(coll):
    return next((candidate for candidate in bpy.data.collections if coll.name in candidate.children), None)


def link_child(parent, child):
    if child.name not in parent.children:
        parent.children.link(child)


def new_package(template_slug, number, display_name, slug, category):
    template = package_by_slug(template_slug)
    parent = collection_parent(template)
    coll = bpy.data.collections.new(f"{number:02d}_{display_name}_资产包")
    link_child(parent, coll)
    coll["资产包"] = True
    coll["资产包键"] = slug
    coll["资产类别"] = category
    coll["源场景资产ID"] = "ENV-BASE99-ART-LAYOUT-3D"
    coll["组织版本"] = "v017"
    coll["当前状态"] = "独立资产包_归类完成_待独立导出"
    coll["本批次范围"] = "v017仅Collection与磁盘manifest归类，不改几何"
    coll["未来导出目录"] = str((PACKAGE_ROOT / category / slug).relative_to(PROJECT))
    return coll


def move_object(obj, target):
    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    target.objects.link(obj)


def mesh_digest(obj):
    if obj.type != "MESH":
        return None
    coords = tuple(round(float(c), 6) for v in obj.data.vertices for c in v.co)
    return {
        "vertices": len(obj.data.vertices),
        "edges": len(obj.data.edges),
        "polygons": len(obj.data.polygons),
        "coordinates": hashlib.sha256(repr(coords).encode()).hexdigest(),
        "materials": [m.name if m else None for m in obj.data.materials],
        "face_materials": hashlib.sha256(bytes(p.material_index % 256 for p in obj.data.polygons)).hexdigest(),
    }


def signature(obj):
    animation = []
    if obj.animation_data and obj.animation_data.action:
        for fc in obj.animation_data.action.fcurves:
            animation.append((fc.data_path, fc.array_index, tuple((round(k.co.x, 4), round(k.co.y, 6)) for k in fc.keyframe_points)))
    return {
        "type": obj.type,
        "parent": obj.parent.name if obj.parent else None,
        "location": [round(float(c), 7) for c in obj.location],
        "rotation_mode": obj.rotation_mode,
        "rotation_euler": [round(float(c), 7) for c in obj.rotation_euler],
        "rotation_quaternion": [round(float(c), 7) for c in obj.rotation_quaternion],
        "scale": [round(float(c), 7) for c in obj.scale],
        "delta_location": [round(float(c), 7) for c in obj.delta_location],
        "delta_rotation_euler": [round(float(c), 7) for c in obj.delta_rotation_euler],
        "delta_scale": [round(float(c), 7) for c in obj.delta_scale],
        "mesh": mesh_digest(obj),
        "modifiers": [(m.name, m.type, tuple(sorted((k, repr(v)) for k, v in m.items()))) for m in obj.modifiers],
        "animation": animation,
    }


def bbox(objects):
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box] if objects else []
    if not points:
        return [0, 0, 0], [0, 0, 0]
    lo = [min(p[i] for p in points) for i in range(3)]
    hi = [max(p[i] for p in points) for i in range(3)]
    return [round((lo[i] + hi[i]) / 2, 4) for i in range(3)], [round(hi[i] - lo[i], 4) for i in range(3)]


def remove_empty_collections(names):
    removed = []
    for name in names:
        coll = bpy.data.collections.get(name)
        if coll and not coll.objects and not coll.children:
            bpy.data.collections.remove(coll)
            removed.append(name)
    return removed


def remove_empty_tree(coll):
    """Prune empty descendants bottom-up and return removed collection names."""
    removed = []
    for child in list(coll.children):
        removed.extend(remove_empty_tree(child))
        if not child.objects and not child.children:
            removed.append(child.name)
            bpy.data.collections.remove(child)
    return removed


def assign_legacy_outputs(targets):
    """Move legacy v012-v014 visual and collision objects to one facility package."""
    legacy_collections = {
        "91_二楼后墙线管与壁灯_资产包_v012": targets["loft_backwall_services"],
        "92_二楼后墙功能面板与装饰_资产包_v012": targets["loft_backwall_function_panel_system"],
        "97_西北L梯结构深化_资产包_v014": targets["northwest_l_stair"],
        "98_东侧上行楼梯结构深化_资产包_v014": targets["east_upper_transition_stair"],
        "99_梯下绿色软垫长凳_资产包_v014": targets["understair_green_bench"],
        "100_梯下公告留言板_资产包_v014": targets["understair_bulletin_board"],
        "101_梯下立式设备柜_资产包_v014": targets["understair_equipment_cabinet"],
        "102_梯下层架与收纳_资产包_v014": targets["understair_storage_shelf"],
        "103_梯下暖光与生活点缀_资产包_v014": targets["understair_lighting_living_support"],
    }
    moved = []
    for legacy_name, target in legacy_collections.items():
        coll = bpy.data.collections.get(legacy_name)
        if not coll:
            continue
        for obj in list(coll.objects):
            move_object(obj, target)
            moved.append((obj.name, target.get("资产包键")))

    # v012 neon package has three independently maintained signs.
    neon = bpy.data.collections.get("93_二楼标识霓虹深化_资产包_v012")
    if neon:
        for obj in list(neon.objects):
            if obj.name.startswith("EXPLORE_"):
                target = targets["loft_explore_poster"]
            elif obj.name.startswith("GOOD_VIBES_"):
                target = targets["loft_good_vibes_neon"]
            else:
                target = targets["loft_stay_curious_neon"]
            move_object(obj, target)
            moved.append((obj.name, target.get("资产包键")))

    # Stair local details have one exact visual host per prefix.
    stair_details = bpy.data.collections.get("94_楼梯墙侧导向细节_资产包_v012")
    if stair_details:
        for obj in list(stair_details.objects):
            target = targets["east_upper_transition_stair"] if obj.name.startswith("东侧") else targets["northwest_l_stair"]
            move_object(obj, target)
            moved.append((obj.name, target.get("资产包键")))

    collision_map = {
        "03_东侧上行楼梯简化碰撞_v014": targets["east_upper_transition_stair"],
        "03_西北L梯简化碰撞_v014": targets["northwest_l_stair"],
        "03_梯下绿色软垫长凳简化碰撞_v014": targets["understair_green_bench"],
        "03_梯下公告留言板_资产包_v014": targets["understair_bulletin_board"],
        "03_梯下立式设备柜简化碰撞_v014": targets["understair_equipment_cabinet"],
        "03_梯下层架与收纳简化碰撞_v014": targets["understair_storage_shelf"],
        "03_梯下生活角边柜简化碰撞_v014": targets["understair_lighting_living_support"],
    }
    for legacy_name, target in collision_map.items():
        coll = bpy.data.collections.get(legacy_name)
        if not coll:
            continue
        for obj in list(coll.objects):
            move_object(obj, target)
            moved.append((obj.name, target.get("资产包键")))
    return moved


def split_existing_wall_utility(targets):
    old = package_by_slug("loft_wall_utility_decor")
    moved = []
    for obj in list(old.objects):
        if obj.name.startswith("EXPLORE"):
            target = targets["loft_explore_poster"]
        elif obj.name.startswith("工具洞洞板"):
            target = targets["loft_tool_pegboard"]
        else:
            target = targets["loft_backwall_services"]
        move_object(obj, target)
        moved.append((obj.name, target.get("资产包键")))
    bpy.data.collections.remove(old)
    return moved


def source_output_name(source_name):
    if "__源_" in source_name:
        return source_name.replace("__源_", "_")
    if source_name.endswith("__源"):
        return source_name[:-3]
    if source_name.endswith("_源组件"):
        return source_name[:-4]
    if source_name.endswith("__"):
        return source_name[:-2]
    return source_name


def organize_sources(output_packages):
    source_root = bpy.data.collections["01_制作组件_已统一材质"]
    mirror = bpy.data.collections.get("v017_全部制作源_按独立设施归类") or bpy.data.collections.new("v017_全部制作源_按独立设施归类")
    link_child(source_root, mirror)
    category_roots = {}
    source_packages = {}
    mapped, unresolved, ignored = [], [], []
    all_sources = [obj for obj in list(source_root.all_objects) if obj is not None]
    output_by_data = {}
    for pkg in output_packages:
        for out_obj in pkg.objects:
            if out_obj.data is not None:
                output_by_data.setdefault(out_obj.data.as_pointer(), []).append((out_obj, pkg))
    prefix_fallbacks = {
        "东侧楼梯v014_": "east_upper_transition_stair",
        "西北L梯v014_": "northwest_l_stair",
        "梯下公告板v014_": "understair_bulletin_board",
        "梯下层架v014_": "understair_storage_shelf",
        "梯下暖灯v014_": "understair_lighting_living_support",
        "梯下生活角v014_": "understair_lighting_living_support",
        "梯下设备柜v014_": "understair_equipment_cabinet",
        "梯下长凳v014_": "understair_green_bench",
        "东墙配电箱标签": "east_power_distribution",
        "分类垃圾箱标签_FLAMMABLE": "east_flammable_bin",
        "分类垃圾箱标签_RECYCLE": "east_recycle_bin",
        "分类垃圾箱标签_WASTE": "east_waste_bin",
        "床头灯_灯罩": "loft_bedside_lamp",
        "自动贩卖机_": "east_supply_24h_station",
        "阁楼急救包十字": "loft_medical_cabinet",
        "阁楼补给标签_BATTERY": "loft_battery_cabinet",
        "阁楼补给标签_FOOD": "loft_food_cabinet",
        "阁楼补给标签_MEDICAL": "loft_medical_cabinet",
    }
    for src in all_sources:
        output_name = source_output_name(src.name)
        out = bpy.data.objects.get(output_name)
        owners = [c for c in out.users_collection if c in output_packages] if out else []
        if len(owners) == 1:
            pkg = owners[0]
        else:
            data_matches = output_by_data.get(src.data.as_pointer(), []) if src.data is not None else []
            unique_packages = {pkg for _, pkg in data_matches}
            if len(unique_packages) == 1:
                pkg = next(iter(unique_packages))
            else:
                pkg = None
            fallback_slug = next((slug for prefix, slug in prefix_fallbacks.items() if src.name.startswith(prefix)), None)
            if pkg is None and fallback_slug:
                pkg = next((c for c in output_packages if c.get("资产包键") == fallback_slug), None)
            if pkg is None:
                unresolved.append(src.name)
                continue
        category = pkg.get("资产类别", "uncategorized")
        slug = pkg.get("资产包键", pkg.name)
        category_coll = category_roots.get(category)
        if category_coll is None:
            category_coll = bpy.data.collections.get(f"v017_源类别_{category}") or bpy.data.collections.new(f"v017_源类别_{category}")
            link_child(mirror, category_coll)
            category_roots[category] = category_coll
        source_pkg = source_packages.get(slug)
        if source_pkg is None:
            source_pkg = bpy.data.collections.get(f"v017_源资产包_{slug}") or bpy.data.collections.new(f"v017_源资产包_{slug}")
            link_child(category_coll, source_pkg)
            source_pkg["对应成品资产包键"] = slug
            source_pkg["资产类别"] = category
            source_packages[slug] = source_pkg
        move_object(src, source_pkg)
        mapped.append((src.name, slug))
    # Remove now-empty v016 source mirror and any emptied root-adjacent staging collections.
    old_mirror = bpy.data.collections.get("v016_新增制作源_按设施归类")
    if old_mirror:
        remove_empty_tree(old_mirror)
        if not old_mirror.objects and not old_mirror.children:
            bpy.data.collections.remove(old_mirror)
    return mapped, unresolved, ignored, len(source_packages)


def write_catalog(output_packages):
    VERIFY.mkdir(parents=True, exist_ok=True)
    entries = []
    for pkg in sorted(output_packages, key=lambda c: (c.get("资产类别", ""), c.get("资产包键", ""))):
        slug = pkg.get("资产包键", pkg.name)
        category = pkg.get("资产类别", "uncategorized")
        folder = PACKAGE_ROOT / category / slug
        folder.mkdir(parents=True, exist_ok=True)
        objs = sorted(pkg.objects, key=lambda o: o.name)
        center, size = bbox(objs)
        collision_names = [o.name for o in objs if o.name.startswith("COLLISION_")]
        entry = {
            "asset_id": "ENV-BASE99-ART-LAYOUT-3D",
            "package_id": f"ENV-BASE99-ART-LAYOUT-3D::{slug}",
            "display_name": pkg.name,
            "asset_slug": slug,
            "category": category,
            "version": "v017",
            "source_blend": str(OUTPUT.relative_to(PROJECT)),
            "object_count": len(objs),
            "mesh_count": sum(o.type == "MESH" for o in objs),
            "light_count": sum(o.type == "LIGHT" for o in objs),
            "object_names": [o.name for o in objs],
            "world_center_m": center,
            "bounding_size_m": size,
            "forward_axis": "Blender +Y north",
            "editable_source_folder": f"01_制作组件_已统一材质/v017_全部制作源_按独立设施归类/v017_源类别_{category}/v017_源资产包_{slug}",
            "collider_names": collision_names,
            "expected_export": f"{slug}_visual_top3d_v001.glb",
            "collision_status": "source collider attached" if collision_names else "not_authored_in_this_collection_only_pass",
            "export_status": "not_exported",
        }
        (folder / "asset_manifest.json").write_text(json.dumps(entry, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        entries.append(entry)
    catalog = {
        "schema": "shellstorm2.base_facility.component_catalog.v3",
        "organization_version": "v017",
        "source": "v016",
        "scope": "Collection and manifest organization only; objects, transforms, meshes, materials and animation locked",
        "package_count": len(entries),
        "floor_tile_package_count": sum(e["category"] == "floor" for e in entries),
        "packages": entries,
    }
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    TREE.write_text("基地场景独立资产包树 v017\n" + "\n".join(f"{e['category']}/{e['asset_slug']} objects={e['object_count']} colliders={len(e['collider_names'])}" for e in entries) + "\n", encoding="utf-8")
    (PACKAGE_ROOT / "README.md").write_text(
        "# Base Facility component packages v017\n\n"
        "Mirror of the v017 Blender hierarchy. Each output object has one facility package; editable sources mirror the same facility package.\n",
        encoding="utf-8",
    )
    return catalog


def main():
    if Path(bpy.data.filepath).resolve() != INPUT.resolve():
        raise RuntimeError("must start from v016")
    if OUTPUT.exists():
        raise RuntimeError(f"target already exists: {OUTPUT}")
    before = {obj.name: signature(obj) for obj in bpy.data.objects}

    # New independent facility packages; no geometry is created or altered.
    targets = {
        "loft_explore_poster": new_package("loft_good_vibes_neon", 48, "EXPLORE独立海报", "loft_explore_poster", "loft"),
        "loft_tool_pegboard": new_package("loft_good_vibes_neon", 49, "工具洞洞板与固定工具", "loft_tool_pegboard", "loft"),
        "loft_backwall_services": new_package("loft_good_vibes_neon", 50, "二楼后墙服务管线与应急盒", "loft_backwall_services", "loft"),
        "loft_backwall_function_panel_system": new_package("loft_good_vibes_neon", 51, "二楼后墙功能面板系统", "loft_backwall_function_panel_system", "loft"),
        "loft_good_vibes_neon": package_by_slug("loft_good_vibes_neon"),
        "loft_stay_curious_neon": new_package("loft_good_vibes_neon", 52, "STAY_CURIOUS楼梯墙标识", "loft_stay_curious_neon", "loft"),
        "northwest_l_stair": package_by_slug("northwest_l_stair"),
        "east_upper_transition_stair": package_by_slug("east_upper_transition_stair"),
        "understair_green_bench": new_package("main_door_low_storage_cabinet", 57, "梯下绿色软垫长凳", "understair_green_bench", "underloft"),
        "understair_bulletin_board": new_package("main_door_low_storage_cabinet", 58, "梯下公告留言板", "understair_bulletin_board", "underloft"),
        "understair_equipment_cabinet": new_package("main_door_low_storage_cabinet", 59, "梯下立式设备柜", "understair_equipment_cabinet", "underloft"),
        "understair_storage_shelf": new_package("main_door_low_storage_cabinet", 60, "梯下层架与收纳", "understair_storage_shelf", "underloft"),
        "understair_lighting_living_support": new_package("main_door_low_storage_cabinet", 61, "梯下暖光与生活点缀", "understair_lighting_living_support", "underloft"),
    }
    moved_legacy = assign_legacy_outputs(targets)
    moved_existing = split_existing_wall_utility(targets)

    # Remove now-empty legacy display collections; their objects have a new, unique package owner.
    legacy_names = [
        "91_二楼后墙线管与壁灯_资产包_v012", "92_二楼后墙功能面板与装饰_资产包_v012", "93_二楼标识霓虹深化_资产包_v012", "94_楼梯墙侧导向细节_资产包_v012",
        "97_西北L梯结构深化_资产包_v014", "98_东侧上行楼梯结构深化_资产包_v014", "99_梯下绿色软垫长凳_资产包_v014", "100_梯下公告留言板_资产包_v014",
        "101_梯下立式设备柜_资产包_v014", "102_梯下层架与收纳_资产包_v014", "103_梯下暖光与生活点缀_资产包_v014",
        "03_东侧上行楼梯简化碰撞_v014", "03_西北L梯简化碰撞_v014", "03_梯下绿色软垫长凳简化碰撞_v014", "03_梯下公告留言板_资产包_v014",
        "03_梯下立式设备柜简化碰撞_v014", "03_梯下层架与收纳简化碰撞_v014", "03_梯下生活角边柜简化碰撞_v014",
    ]
    removed_collections = remove_empty_collections(legacy_names)

    current_packages = packages()
    mapped_sources, unresolved_sources, ignored_sources, source_package_count = organize_sources(set(current_packages))

    after = {name: signature(bpy.data.objects[name]) for name in before if name in bpy.data.objects}
    changed = sorted(name for name in before if name in after and before[name] != after[name])
    removed = sorted(set(before) - set(after))
    if changed or removed:
        raise RuntimeError(f"collection-only lock failed: changed={changed[:8]} removed={removed[:8]}")

    catalog = write_catalog(current_packages)
    bpy.context.scene["v017_scope"] = "仅Collection、资产包与源组件镜像归类"
    bpy.context.scene["v017_locked_v016_object_count"] = len(before)
    bpy.context.scene["v017_package_count"] = catalog["package_count"]
    bpy.context.scene["v017_source_package_count"] = source_package_count
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))

    REPORT.write_text(json.dumps({
        "input": str(INPUT.relative_to(PROJECT)),
        "output": str(OUTPUT.relative_to(PROJECT)),
        "policy": "collection and manifest changes only; v016 object signatures immutable",
        "locked_object_count": len(before),
        "locked_match": before == after,
        "locked_changed": changed,
        "locked_removed": removed,
        "moved_legacy_object_count": len(moved_legacy),
        "moved_existing_wall_utility_object_count": len(moved_existing),
        "organized_editable_source_count": len(mapped_sources),
        "unresolved_editable_source_count": len(unresolved_sources),
        "ignored_non_source_objects_in_source_tree": len(ignored_sources),
        "source_package_count": source_package_count,
        "removed_empty_legacy_collections": removed_collections,
        "asset_package_count": catalog["package_count"],
        "floor_tile_package_count": catalog["floor_tile_package_count"],
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"BASE_FACILITY_V017_REORGANIZED locked={len(before)} packages={catalog['package_count']} legacy={len(moved_legacy)} source={len(mapped_sources)}")


if __name__ == "__main__":
    main()
