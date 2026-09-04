#!/usr/bin/env python3
"""Correct the v017 west door bay and create runtime-aligned visual placements.

The game uses a generic pair at both east and west entries:
ENV-BASE99-WALL-DOOR-5X9 + ENV-BASE99-DOOR-LIFT-22X25.  The west entry is
the third 5m module from north (Blender Y=+2.5), not the fourth (Y=-2.5).
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import bpy
from mathutils import Matrix

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
PACKAGE_ROOT = PROJECT / "source/art/blender/base_facility_layout/component_packages_v017"
VERIFY = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v017"
REPORT = VERIFY / "west_door_wall_set_relocation_acceptance.json"
ASSEMBLY = PACKAGE_ROOT / "component_sets/west_door_wall_set/assembly_manifest.json"
if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("must run with v017 open")

spec = importlib.util.spec_from_file_location("v017_reorg", PROJECT / "scripts/blender/reorganize_base_facility_component_packages_v017.py")
reorg = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(reorg)

old_catalog = json.loads(reorg.CATALOG.read_text(encoding="utf-8")) if reorg.CATALOG.is_file() else {"packages": []}
old_entries = {entry["asset_slug"]: entry for entry in old_catalog.get("packages", [])}
old_manifests: dict[str, str] = {}
for collection in reorg.packages():
    path = PACKAGE_ROOT / str(collection.get("资产类别")) / str(collection.get("资产包键")) / "asset_manifest.json"
    if path.is_file():
        old_manifests[str(collection.get("资产包键"))] = path.read_text(encoding="utf-8")

retained = reorg.package_by_slug("retained_wall_system")
east_wall = reorg.package_by_slug("east_door_wall_module")
east_door = reorg.package_by_slug("east_personnel_security_door")

door_anchor_old = bpy.data.objects["保留西墙_02"]
door_anchor_target = bpy.data.objects["保留西墙_03"]
door_root = bpy.data.objects["ENV-BASE99-WALL-DOOR-5X9_输出根节点.001"]
door_wall = bpy.data.objects["带门墙体_主体_金属哑光反光.001"]
plain_root = bpy.data.objects["ENV-BASE99-WALL-PLAIN-5X9_输出根节点.017"]
plain_wall = bpy.data.objects["普通墙体_主体_金属哑光反光.017"]
east_wall_mesh = bpy.data.objects["带门墙体_主体_金属哑光反光.002"]
east_door_body = bpy.data.objects["东墙标准滑升门_主体_金属哑光反光"]
east_door_emissive = bpy.data.objects["东墙标准滑升门_状态灯_柔和自发光"]
east_door_lamp = bpy.data.objects["东墙滑升门_状态照明"]

allowed_existing = {door_anchor_target, door_root, door_wall, plain_root, plain_wall}
locked_before = {obj.name: reorg.signature(obj) for obj in bpy.data.objects if obj not in allowed_existing}


def move_to_package(obj, package):
    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    package.objects.link(obj)


def parent_at_anchor(root, anchor):
    root.parent = anchor
    # The output root is intentionally expressed in the wall anchor's local space.
    # Identity parent-inverse makes local zero resolve exactly to the 5m bay anchor.
    root.matrix_parent_inverse = Matrix.Identity(4)
    root.location = (0.0, 0.0, 0.0)
    root.rotation_euler = (0.0, 0.0, 0.0)
    root.scale = (1.0, 1.0, 1.0)


def new_source_package(category, slug, display):
    source_parent = bpy.data.collections.get(f"v017_源类别_{category}")
    if source_parent is None:
        source_root = bpy.data.collections["v017_全部制作源_按独立设施归类"]
        source_parent = bpy.data.collections.new(f"v017_源类别_{category}")
        source_root.children.link(source_parent)
    collection = bpy.data.collections.new(f"v017_源资产包_{slug}")
    source_parent.children.link(collection)
    collection["源资产包"] = True
    collection["源资产包键"] = slug
    collection["显示名"] = display
    return collection


def create_empty(name, collection, location, rotation_z, parent=None):
    obj = bpy.data.objects.new(name, None)
    collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (0.0, 0.0, rotation_z)
    if parent is not None:
        obj.parent = parent
        obj.matrix_parent_inverse = Matrix.Identity(4)
        obj.location = (0.0, 0.0, 0.0)
        obj.rotation_euler = (0.0, 0.0, 0.0)
    return obj


def create_mesh(name, source_obj, collection, parent, location=None, rotation_z=0.0):
    obj = bpy.data.objects.new(name, source_obj.data.copy())
    collection.objects.link(obj)
    obj.parent = parent
    obj.matrix_parent_inverse = parent.matrix_world.inverted()
    obj.location = (0.0, 0.0, 0.0) if location is None else location
    obj.rotation_euler = (0.0, 0.0, 0.0) if location is None else (0.0, 0.0, rotation_z)
    for key, value in source_obj.items():
        obj[key] = value
    return obj


# Existing visual door module is fourth north→south; swap it with the third plain wall.
# The empty anchors are named in south→north order, so Y=+2.5 is 保留西墙_03.
parent_at_anchor(plain_root, door_anchor_old)
parent_at_anchor(door_root, door_anchor_target)
door_root.name = "ENV-BASE99-WALL-DOOR-5X9_WEST_输出根节点"
door_wall.name = "西墙带门墙体_主体_金属哑光反光"
door_wall.data = east_wall_mesh.data.copy()
door_wall.data.name = "西墙带门墙体_主体_复用东侧验收门框网格"
door_wall["高还原结构"] = east_wall_mesh.get("高还原结构", "墙体归属八角门框")
door_wall["门框归属"] = "west_door_wall_module（复用已验收东侧门框结构）"
door_wall["参考版本"] = "v017_west_third_bay_runtime_aligned_001"

west_wall = reorg.new_package("east_door_wall_module", 114, "西墙带门墙模块", "west_door_wall_module", "architecture")
west_wall["运行时资产ID"] = "ENV-BASE99-WALL-DOOR-5X9"
west_wall["运行时角色"] = "facility.west wall_door module / third north-to-south bay"
move_to_package(door_anchor_target, west_wall)
move_to_package(door_root, west_wall)
move_to_package(door_wall, west_wall)
west_wall_source = new_source_package("architecture", "west_door_wall_module", "西墙带门墙模块")
source_anchor = create_empty("西墙带门墙模块_源锚点", west_wall_source, (-15.0, 2.5, 0.0), 1.57079632679)
source_root = create_empty("ENV-BASE99-WALL-DOOR-5X9_WEST_输出根节点__源", west_wall_source, (0.0, 0.0, 0.0), 0.0, source_anchor)
source_wall = create_mesh("西墙带门墙体_主体_金属哑光反光__源", door_wall, west_wall_source, source_root)
source_wall["高还原结构"] = door_wall["高还原结构"]
source_wall["门框归属"] = door_wall["门框归属"]
source_wall["参考版本"] = door_wall["参考版本"]

# The west runtime uses the shared generic lift-door prefab.  This is an explicit
# placement instance, not a second exported gameplay AssetID, and intentionally
# excludes the east-only standalone access-control dressing.
west_leaf = reorg.new_package("east_personnel_security_door", 115, "西侧滑升门运行时实例", "west_door_lift_instance", "west_facilities")
west_leaf["运行时资产ID"] = "ENV-BASE99-DOOR-LIFT-22X25"
west_leaf["运行时角色"] = "facility.west RoomDoor3D visual placement / shared generic asset"
west_leaf["复用来源"] = "east_personnel_security_door 的已验收门扇视觉"
west_leaf_root = create_empty("ENV-BASE99-DOOR-LIFT-22X25_WEST_输出根节点", west_leaf, (-15.0, 2.5, 0.0), 1.57079632679)
west_body = create_mesh("西墙标准滑升门_主体_金属哑光反光", east_door_body, west_leaf, west_leaf_root)
west_emissive = create_mesh("西墙标准滑升门_状态灯_柔和自发光", east_door_emissive, west_leaf, west_leaf_root)
west_body["运行时资产ID"] = "ENV-BASE99-DOOR-LIFT-22X25"
west_body["复用来源"] = "east_personnel_security_door"
west_emissive["运行时资产ID"] = "ENV-BASE99-DOOR-LIFT-22X25"
west_lamp = bpy.data.objects.new("西墙滑升门_状态照明", east_door_lamp.data.copy())
west_leaf.objects.link(west_lamp)
west_lamp.location = (-14.84, 2.50, 2.13)
west_lamp["归属发光设施"] = "west_door_lift_instance"
west_lamp["运行时资产ID"] = "ENV-BASE99-DOOR-LIFT-22X25"
west_leaf_source = new_source_package("west_facilities", "west_door_lift_instance", "西侧滑升门运行时实例")
west_leaf_source_root = create_empty("ENV-BASE99-DOOR-LIFT-22X25_WEST_输出根节点__源", west_leaf_source, (-15.0, 2.5, 0.0), 1.57079632679)
west_body_source = create_mesh("西墙标准滑升门_主体_金属哑光反光__源", west_body, west_leaf_source, west_leaf_source_root)
west_emissive_source = create_mesh("西墙标准滑升门_状态灯_柔和自发光__源", west_emissive, west_leaf_source, west_leaf_source_root)
west_lamp_source = bpy.data.objects.new("西墙滑升门_状态照明__源", west_lamp.data.copy())
west_leaf_source.objects.link(west_lamp_source)
west_lamp_source.location = west_lamp.location
for obj in (west_body_source, west_emissive_source, west_lamp_source):
    obj["归属发光设施"] = "west_door_lift_instance"
    obj["运行时资产ID"] = "ENV-BASE99-DOOR-LIFT-22X25"

bpy.context.view_layer.update()
wall_center, wall_dims = reorg.bbox((door_wall,))
leaf_center, leaf_dims = reorg.bbox((west_body, west_emissive))
if wall_center != [-14.9503, 2.5, 4.5] or wall_dims != [1.2706, 5.0, 9.0]:
    raise RuntimeError(f"west wall visual placement mismatch: {wall_center} {wall_dims}")
if leaf_center != [-15.0, 2.5, 1.25] or leaf_dims != [0.325, 2.2, 2.5]:
    raise RuntimeError(f"west leaf placement mismatch: {leaf_center} {leaf_dims}")
for obj in (door_wall, source_wall, west_body, west_emissive, west_body_source, west_emissive_source):
    uv = obj.data.uv_layers.get("PaletteUV")
    if [layer.name for layer in obj.data.uv_layers] != ["PaletteUV"] or obj.data.uv_layers.active != uv or not uv.active_render:
        raise RuntimeError(f"PaletteUV contract failed: {obj.name}")

# Rebuild new catalog/manifests, then preserve unrelated prior custom metadata.
catalog = reorg.write_catalog(reorg.packages())
for slug, text in old_manifests.items():
    if slug == "retained_wall_system":
        continue
    path = PACKAGE_ROOT / str(reorg.package_by_slug(slug).get("资产类别")) / slug / "asset_manifest.json"
    path.write_text(text, encoding="utf-8")
for entry in catalog["packages"]:
    slug = entry["asset_slug"]
    if slug in old_entries and slug != "retained_wall_system":
        entry.update(old_entries[slug])

runtime_wall = {
    "asset_id": "ENV-BASE99-WALL-DOOR-5X9",
    "runtime_prefab": "assets/art/environments/base_facility_3d/runtime/env_base99_wall_door_5x9/env_base99_wall_door_5x9_root_top3d_v001.tscn",
    "runtime_visual_glb": "assets/art/environments/base_facility_3d/components/env_base99_wall_door_5x9/env_base99_wall_door_5x9_visual_top3d_v001.glb",
    "runtime_component": "wall_door",
    "runtime_owner": "DungeonRoom3D + RoomDoor3D",
    "scene_placement": {"side": "west", "north_to_south_index": 3, "blender_anchor_m": [-15.0, 2.5, 0.0], "rotation_z_rad": 1.57079632679},
    "base_wall_core_dimensions_m": {"depth": 1.1712, "width": 5.0, "height": 9.0},
    "wall_owned_door_frame": "复用 east_door_wall_module 已验收的门框网格；归属 west_door_wall_module。",
    "expected_export": "env_base99_wall_door_5x9_visual_top3d_v001.glb",
    "export_status": "source_ready_reuses_existing_runtime_asset_not_exported_in_this_iteration",
}
runtime_leaf = {
    "asset_id": "ENV-BASE99-DOOR-LIFT-22X25",
    "runtime_prefab": "assets/art/environments/base_facility_3d/runtime/env_base99_door_lift_2p2x2p5/env_base99_door_lift_2p2x2p5_root_top3d_v001.tscn",
    "runtime_visual_glb": "assets/art/environments/base_facility_3d/components/env_base99_door_lift_2p2x2p5/env_base99_door_lift_2p2x2p5_visual_top3d_v001.glb",
    "runtime_component": "door_leaf",
    "runtime_owner": "RoomDoor3D",
    "scene_placement": {"side": "west", "north_to_south_index": 3, "blender_anchor_m": [-15.0, 2.5, 0.0], "rotation_z_rad": 1.57079632679},
    "shared_asset_reuse": "复用 ENV-BASE99-DOOR-LIFT-22X25，不创建第二个运行时 AssetID 或 GLB。",
    "excluded_components": ["east_door_access_control"],
    "expected_export": "env_base99_door_lift_2p2x2p5_visual_top3d_v001.glb",
    "export_status": "source_ready_reuses_existing_runtime_asset_not_exported_in_this_iteration",
}
for slug, custom in (("west_door_wall_module", runtime_wall), ("west_door_lift_instance", runtime_leaf)):
    package = reorg.package_by_slug(slug)
    path = PACKAGE_ROOT / str(package.get("资产类别")) / slug / "asset_manifest.json"
    manifest = json.loads(path.read_text(encoding="utf-8"))
    manifest.update(custom)
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    next(entry for entry in catalog["packages"] if entry["asset_slug"] == slug).update(custom)
catalog["package_count"] = len(reorg.packages())
catalog["source"] = "v017 west third-bay door wall correction and runtime component alignment"
catalog["scope"] = "Only west wall bays 02/03 plus new west runtime visual placement packages were changed; east assets and all other facilities signature locked."
reorg.CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

ASSEMBLY.parent.mkdir(parents=True, exist_ok=True)
assembly = {
    "assembly_id": "base99_west_door_wall_set",
    "display_name": "基地99层西侧第三段带门组件组",
    "version": "v017",
    "coordinate_mapping": "Blender (X,Y,Z) -> Godot (X,Z,Y); horizontal coordinates use equal X/Y-to-X/Z values.",
    "runtime_placement": {"side": "west", "north_to_south_index": 3, "godot_position_m": [-15.0, -9.0, 2.5], "godot_rotation_y_rad": 1.57079632679, "blender_position_m": [-15.0, 2.5, 0.0], "blender_rotation_z_rad": 1.57079632679},
    "members": [
        {"role": "wall_door", "asset_slug": "west_door_wall_module", "asset_id": "ENV-BASE99-WALL-DOOR-5X9", "runtime_prefab": runtime_wall["runtime_prefab"]},
        {"role": "door_leaf_instance", "asset_slug": "west_door_lift_instance", "asset_id": "ENV-BASE99-DOOR-LIFT-22X25", "runtime_prefab": runtime_leaf["runtime_prefab"]},
    ],
    "non_members": [{"asset_slug": "east_door_access_control", "reason": "游戏西侧 RoomDoor3D 组合不包含东侧独立门禁外围摆件。"}],
    "direct_replacement_contract": "导出时分别替换两个既有通用 visual GLB；保持现有 PackedScene 根节点、AssetID、方向、碰撞与 RoomDoor3D/DungeonRoom3D 职责，不新建运行时路径。",
}
ASSEMBLY.write_text(json.dumps(assembly, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

locked_after = {obj.name: reorg.signature(obj) for obj in bpy.data.objects if obj.name in locked_before}
mismatches = {name: {"before": locked_before[name], "after": locked_after.get(name)} for name in locked_before if locked_before[name] != locked_after.get(name)}
if mismatches:
    raise RuntimeError(f"outside-scope mutations: {list(mismatches)[:8]}")

result = {
    "status": "pass",
    "scope": "west wall bay 02/03 swap; west wall/door runtime placement packages only",
    "lock": {"locked_count": len(locked_before), "locked_match": True, "mismatches": {}},
    "game_runtime_position_m": [-15.0, -9.0, 2.5],
    "blender_position_m": [-15.0, 2.5, 0.0],
    "north_to_south_index": 3,
    "wall": {"owner": "west_door_wall_module", "visual_center_m": wall_center, "visual_dimensions_m": wall_dims},
    "door_leaf": {"owner": "west_door_lift_instance", "center_m": leaf_center, "dimensions_m": leaf_dims},
    "runtime_assets": [runtime_wall["asset_id"], runtime_leaf["asset_id"]],
    "excluded": runtime_leaf["excluded_components"],
    "package_count": len(reorg.packages()),
    "runtime_note": "Blender source and replacement mapping completed. Existing runtime GLBs/PackedScenes were intentionally not overwritten in this iteration.",
}
REPORT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
bpy.context.scene["v017_iteration"] = "west_third_bay_door_runtime_alignment_001"
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
print(json.dumps(result, ensure_ascii=False))
