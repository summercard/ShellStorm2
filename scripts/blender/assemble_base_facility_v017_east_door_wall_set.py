#!/usr/bin/env python3
"""Restore the v017 east door as the canonical wall-door component set.

The revision corrects the previous free-standing placement.  It keeps the
three independently importable assets (wall module, lift door, access control)
but records them as one explicit assembly contract.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import bpy
from mathutils import Vector

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
PACKAGE_ROOT = PROJECT / "source/art/blender/base_facility_layout/component_packages_v017"
VERIFY = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v017"
REPORT = VERIFY / "east_door_wall_set_acceptance.json"
ASSEMBLY = PACKAGE_ROOT / "component_sets/east_door_wall_set/assembly_manifest.json"
WALL_GLB = PROJECT / "assets/art/environments/base_facility_3d/components/env_base99_wall_door_5x9/env_base99_wall_door_5x9_visual_top3d_v001.glb"
DOOR_GLB = PROJECT / "assets/art/environments/base_facility_3d/components/env_base99_door_lift_2p2x2p5/env_base99_door_lift_2p2x2p5_visual_top3d_v001.glb"
if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("must run with v017 open")
if not WALL_GLB.is_file() or not DOOR_GLB.is_file():
    raise RuntimeError("canonical wall-door game assets are missing")

spec = importlib.util.spec_from_file_location("v017_reorg", PROJECT / "scripts/blender/reorganize_base_facility_component_packages_v017.py")
reorg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reorg)


def coll(name):
    value = bpy.data.collections.get(name)
    if value is None:
        raise RuntimeError(f"missing collection: {name}")
    return value


def source_package(slug, category, display):
    root = coll("01_制作组件_已统一材质")
    category_root = bpy.data.collections.get(f"v017_源类别_{category}")
    if category_root is None:
        category_root = bpy.data.collections.new(f"v017_源类别_{category}")
        reorg.link_child(root, category_root)
    name = f"v017_源资产包_{slug}"
    package = bpy.data.collections.get(name)
    if package is None:
        package = bpy.data.collections.new(name)
        reorg.link_child(category_root, package)
    package["源资产包"] = True
    package["资产包键"] = slug
    package["资产类别"] = category
    package["组织版本"] = "v017"
    package["说明"] = f"{display}可编辑制作源，镜像独立输出资产包"
    return package


door_pkg = reorg.package_by_slug("east_personnel_security_door")
access_pkg = reorg.package_by_slug("east_door_access_control")
supply_pkg = reorg.package_by_slug("east_supply_24h_station")
door_src = coll("v017_源资产包_east_personnel_security_door")
access_src = coll("v017_源资产包_east_door_access_control")
supply_src = coll("v017_源资产包_east_supply_24h_station")
wall_system_pkg = reorg.package_by_slug("retained_wall_system")

wall_anchor = bpy.data.objects.get("保留东墙_02")
wall_root = bpy.data.objects.get("ENV-BASE99-WALL-DOOR-5X9_输出根节点.002")
wall_mesh = bpy.data.objects.get("带门墙体_主体_金属哑光反光.002")
if not all((wall_anchor, wall_root, wall_mesh)):
    raise RuntimeError("east wall-door module hierarchy missing")

# Scope lock: the three authorized asset packages and exactly this east wall
# module are mutable; all remaining v017 objects must stay bit-for-bit stable.
allowed = set(door_pkg.objects) | set(access_pkg.objects) | set(supply_pkg.objects)
allowed |= set(door_src.objects) | set(access_src.objects) | set(supply_src.objects)
allowed |= {wall_anchor, wall_root, wall_mesh}
locked_before = {o.name: reorg.signature(o) for o in bpy.data.objects if o not in allowed}

# Vending station must not occupy a functional doorway: restore it to the
# adjacent east-facility anchor used before the mistaken swap.
supply_delta = Vector((-0.70, 4.05, 0.0))
for obj in list(supply_pkg.objects) + list(supply_src.objects):
    obj.location += supply_delta

# Door and access assembly both return to the east-wall opening.  Door source
# and output share the same delta so their editable world references agree.
door_delta = Vector((1.48, -4.05, 0.0))
for obj in list(door_pkg.objects) + list(door_src.objects) + list(access_pkg.objects) + list(access_src.objects):
    obj.location += door_delta

# Split the existing east door-wall module away from the broad retained-wall
# group into its own future-importable package without changing geometry.
wall_pkg = bpy.data.collections.get("12_东墙带门墙模块_资产包")
if wall_pkg is None:
    wall_pkg = reorg.new_package("retained_wall_system", 12, "东墙带门墙模块", "east_door_wall_module", "architecture")
for obj in (wall_anchor, wall_root, wall_mesh):
    reorg.move_object(obj, wall_pkg)
wall_src = source_package("east_door_wall_module", "architecture", "东墙带门墙模块")
if not wall_src.objects:
    source_anchor = wall_anchor.copy()
    source_anchor.name = "保留东墙_02__源"
    source_anchor.parent = None
    source_anchor.matrix_world = wall_anchor.matrix_world.copy()
    source_anchor.hide_viewport = True
    source_anchor.hide_render = True
    wall_src.objects.link(source_anchor)
    source_root = wall_root.copy()
    source_root.name = "ENV-BASE99-WALL-DOOR-5X9_输出根节点.002__源"
    source_root.parent = source_anchor
    source_root.matrix_world = wall_root.matrix_world.copy()
    source_root.hide_viewport = True
    source_root.hide_render = True
    wall_src.objects.link(source_root)
    source_mesh = wall_mesh.copy()
    source_mesh.data = wall_mesh.data.copy()
    source_mesh.name = "带门墙体_主体_金属哑光反光.002__源"
    source_mesh.parent = source_root
    source_mesh.matrix_world = wall_mesh.matrix_world.copy()
    source_mesh.hide_viewport = True
    source_mesh.hide_render = True
    wall_src.objects.link(source_mesh)

# Keep the existing folder boundaries, and make their assembly relation
# explicit in both Blender metadata and the disk-level assembly manifest.
assembly_key = "base99_east_door_wall_set"
for package, role in ((wall_pkg, "door_wall_module"), (door_pkg, "lift_door"), (access_pkg, "door_access_control")):
    package["组件组键"] = assembly_key
    package["组件组角色"] = role
    package["组件组锚点_m"] = [15.0, -2.5, 0.0]
wall_pkg["本批次范围"] = "v017东墙带门墙模块从保留墙体系统拆出；与标准滑升门和门禁外围组成组件组"
wall_pkg["游戏资产ID"] = "ENV-BASE99-WALL-DOOR-5X9"
wall_pkg["逻辑ID"] = "base99_wall_door_5x9"
wall_pkg["门洞接口规格_m"] = "2.2 × 2.5；中心 (15, -2.5, 0)；朝向 -90°"
door_pkg["本批次范围"] = "v017标准滑升门嵌入东墙带门墙模块门洞；不再独立悬置"
door_pkg["宿主门墙资产包"] = "east_door_wall_module"
access_pkg["本批次范围"] = "v017门禁外围控制跟随东墙标准门组件组定位"
access_pkg["宿主门墙资产包"] = "east_door_wall_module"
supply_pkg["本批次范围"] = "v017恢复至东墙门洞相邻的补给机设施位，避免占用门洞"

bpy.context.view_layer.update()
door_meshes = [bpy.data.objects[n] for n in ("东墙标准滑升门_主体_金属哑光反光", "东墙标准滑升门_状态灯_柔和自发光")]
door_center, door_dims = reorg.bbox(door_meshes)
wall_center, wall_dims = reorg.bbox([wall_mesh])
if door_center != [15.0, -2.5, 1.25] or door_dims != [0.325, 2.2, 2.5]:
    raise RuntimeError(f"door is not aligned to wall opening: {door_center} {door_dims}")
if wall_center != [15.0, -2.5, 4.5] or wall_dims != [1.1712, 5.0, 9.0]:
    raise RuntimeError(f"wall module contract mismatch: {wall_center} {wall_dims}")
body = bpy.data.objects.get("SUPPLY24H_主体外壳")
if body is None or (Vector(body.location) - Vector((13.52, 1.55, 1.78))).length > 0.001:
    raise RuntimeError(f"SUPPLY24H must be adjacent, not in door opening: {body.location if body else None}")

reorg.write_catalog(reorg.packages())
manifest_updates = {
    "architecture/east_door_wall_module": {
        "component_set": assembly_key,
        "component_set_role": "door_wall_module",
        "game_asset_contract": {
            "asset_id": "ENV-BASE99-WALL-DOOR-5X9", "logic_id": "base99_wall_door_5x9",
            "source_glb": str(WALL_GLB.relative_to(PROJECT)), "local_dimensions_m": [5.0, 1.1712, 9.0],
            "scene_anchor_m": [15.0, -2.5, 0.0], "scene_rotation_z_degrees": -90,
            "opening_contract_m": [2.2, 2.5], "origin": "bottom_center", "collision_owner": "DungeonRoom3D + RoomDoor3D",
        },
        "dependent_assets": ["east_personnel_security_door", "east_door_access_control"],
    },
    "east_facilities/east_personnel_security_door": {
        "component_set": assembly_key, "component_set_role": "lift_door", "host_wall_asset": "east_door_wall_module",
        "game_asset_contract": {
            "asset_id": "ENV-BASE99-DOOR-LIFT-22X25", "logic_id": "base99_door_lift_2p2x2p5",
            "source_glb": str(DOOR_GLB.relative_to(PROJECT)), "local_dimensions_m": [2.2, 0.325, 2.5],
            "scene_dimensions_m": [0.325, 2.2, 2.5], "scene_anchor_m": [15.0, -2.5, 0.0],
            "scene_forward": "world -X (game local -Y after -90° Z)", "origin": "center-bottom",
            "runtime_motion": "vertical_lift", "collision_in_visual_glb": False,
        },
        "door_only": True, "access_control_package": "east_door_access_control",
    },
    "east_facilities/east_door_access_control": {
        "component_set": assembly_key, "component_set_role": "door_access_control", "attachment_to": "east_personnel_security_door",
        "host_wall_asset": "east_door_wall_module", "scene_anchor_m": [15.0, -2.5, 0.0],
        "independent_asset_boundary": "door-adjacent access peripherals only; lift-door and wall geometry excluded",
    },
    "east_facilities/east_supply_24h_station": {
        "component_set": None, "anchor_after_m": [13.52, 1.55, 0.0],
        "geometry_rebuilt": False, "doorway_clear": True,
    },
}
for relative, additions in manifest_updates.items():
    path = PACKAGE_ROOT / relative / "asset_manifest.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    data.update(additions)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

ASSEMBLY.parent.mkdir(parents=True, exist_ok=True)
ASSEMBLY.write_text(json.dumps({
    "assembly_id": assembly_key,
    "display_name": "基地99层东墙带门组件组",
    "version": "v017",
    "anchor_m": [15.0, -2.5, 0.0], "wall_forward": "world -X", "opening_m": [2.2, 2.5],
    "members": [
        {"role": "door_wall_module", "asset_slug": "east_door_wall_module", "asset_id": "ENV-BASE99-WALL-DOOR-5X9"},
        {"role": "lift_door", "asset_slug": "east_personnel_security_door", "asset_id": "ENV-BASE99-DOOR-LIFT-22X25"},
        {"role": "door_access_control", "asset_slug": "east_door_access_control", "asset_id": "ENV-BASE99-ART-LAYOUT-3D"},
    ],
    "non_members": [{"asset_slug": "east_supply_24h_station", "reason": "adjacent facility; must not occupy the door opening"}],
    "runtime_contract": "Wall visual is owned by DungeonRoom3D; lift door visual is owned by RoomDoor3D; visual GLBs contain no runtime collision.",
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

catalog = json.loads(reorg.CATALOG.read_text(encoding="utf-8"))
catalog["source"] = "v017 east wall-door component-set correction"
catalog["scope"] = "Only east door wall module, its lift-door/access set, and adjacent SUPPLY 24H were adjusted; all other objects are locked."
catalog["package_count"] = len(reorg.packages())
catalog["component_sets"] = [{"assembly_id": assembly_key, "manifest": str(ASSEMBLY.relative_to(PROJECT)), "members": ["east_door_wall_module", "east_personnel_security_door", "east_door_access_control"]}]
reorg.CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

locked_after = {o.name: reorg.signature(o) for o in bpy.data.objects if o.name in locked_before}
mismatches = {name: {"before": locked_before[name], "after": locked_after.get(name)} for name in locked_before if locked_before[name] != locked_after.get(name)}
if mismatches:
    raise RuntimeError(f"outside-scope changes detected: {sorted(mismatches)[:10]}")

packages = reorg.packages()
owners = {}
for package in packages:
    for obj in package.objects:
        owners.setdefault(obj.name, []).append(package.get("资产包键"))
bad_owners = {name: names for name, names in owners.items() if len(names) != 1}
if bad_owners:
    raise RuntimeError(f"multi-package objects: {bad_owners}")
report = {
    "status": "pass", "blend": str(BLEND.relative_to(PROJECT)), "component_set": assembly_key,
    "lock": {"locked_count": len(locked_before), "locked_match": True, "mismatches": {}},
    "package_count": len(packages),
    "wall_module": {"center_m": wall_center, "dimensions_m": wall_dims, "objects": [o.name for o in wall_pkg.objects], "source_count": len(wall_src.objects)},
    "door": {"center_m": door_center, "dimensions_m": door_dims, "objects": [o.name for o in door_pkg.objects], "source_count": len(door_src.objects)},
    "access_control": {"object_count": len(access_pkg.objects), "source_count": len(access_src.objects)},
    "supply_24h": {"body_location_m": [round(float(v), 4) for v in body.location], "source_count": len(supply_src.objects)},
    "assembly_manifest": str(ASSEMBLY.relative_to(PROJECT)), "empty_packages": [p.get("资产包键") for p in packages if not p.objects], "multi_owner": bad_owners,
}
REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
bpy.context.scene["v017_iteration"] = "east_wall_door_component_set"
bpy.context.scene["v017_east_door_component_set"] = assembly_key
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
print(json.dumps(report, ensure_ascii=False))
