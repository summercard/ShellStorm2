#!/usr/bin/env python3
"""v017-only east wall correction: swap SUPPLY 24H and the standard lift door.

The task deliberately changes only the two east-wall packages and the new
door-access-control package.  Every other pre-existing object is locked by a
repeatable geometry/material/transform signature before the mutation.
"""

from __future__ import annotations

import importlib.util
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
GAME_DOOR = PROJECT / "assets/art/environments/base_facility_3d/components/env_base99_door_lift_2p2x2p5/env_base99_door_lift_2p2x2p5_visual_top3d_v001.glb"
VERIFY = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v017"
REPORT = VERIFY / "east_door_supply_swap_acceptance.json"

if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("This refinement must be run with v017 open.")
if not GAME_DOOR.is_file():
    raise RuntimeError(f"Missing canonical game door GLB: {GAME_DOOR}")

spec = importlib.util.spec_from_file_location(
    "v017_reorg", PROJECT / "scripts/blender/reorganize_base_facility_component_packages_v017.py"
)
reorg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reorg)


def source_output_name(name: str) -> str:
    return reorg.source_output_name(name)


def is_structural_old_door(name: str) -> bool:
    name = source_output_name(name)
    if not name.startswith("东墙人员门_"):
        return False
    structural_tokens = (
        "厚重外门框", "内嵌主门板", "二级装甲板", "装甲分区", "横向拼接缝",
        "门框侧柱", "门框固定螺丝", "顶部横梁", "底部金属门槛", "机械锁定横杆",
        "机械开门手轮", "手轮内轴", "顶部状态灯",
    )
    return any(token in name for token in structural_tokens)


def obj_row(obj):
    return {
        "name": obj.name,
        "type": obj.type,
        "location": [round(float(v), 5) for v in obj.location],
        "rotation_z": round(float(obj.rotation_euler.z), 5),
        "dimensions": [round(float(v), 5) for v in obj.dimensions],
        "collections": sorted(c.name for c in obj.users_collection),
    }


def collection_or_fail(name):
    coll = bpy.data.collections.get(name)
    if coll is None:
        raise RuntimeError(f"Missing collection: {name}")
    return coll


def make_source_package(slug: str, category: str, display_name: str):
    source_root = collection_or_fail("01_制作组件_已统一材质")
    category_root = bpy.data.collections.get(f"v017_源类别_{category}")
    if category_root is None:
        category_root = bpy.data.collections.new(f"v017_源类别_{category}")
        reorg.link_child(source_root, category_root)
    name = f"v017_源资产包_{slug}"
    coll = bpy.data.collections.get(name)
    if coll is None:
        coll = bpy.data.collections.new(name)
        reorg.link_child(category_root, coll)
    coll["源资产包"] = True
    coll["资产包键"] = slug
    coll["资产类别"] = category
    coll["组织版本"] = "v017"
    coll["说明"] = f"{display_name}的可编辑制作源；与输出资产包一一镜像"
    return coll


door_pkg = reorg.package_by_slug("east_personnel_security_door")
supply_pkg = reorg.package_by_slug("east_supply_24h_station")
door_src_pkg = collection_or_fail("v017_源资产包_east_personnel_security_door")
supply_src_pkg = collection_or_fail("v017_源资产包_east_supply_24h_station")

# Lock every pre-existing object not explicitly inside the two user-authorized
# target packages (including their source mirrors).
target_before = set(door_pkg.objects) | set(supply_pkg.objects) | set(door_src_pkg.objects) | set(supply_src_pkg.objects)
locks_before = {obj.name: reorg.signature(obj) for obj in bpy.data.objects if obj not in target_before}
old_door_rows = [obj_row(o) for o in sorted(door_pkg.objects, key=lambda o: o.name)]
old_supply_rows = [obj_row(o) for o in sorted(supply_pkg.objects, key=lambda o: o.name)]

# The old door volume is noncanonical.  Retain access-control pieces, but
# remove only its explicitly listed structural geometry and its old lamp.
access_output = []
for obj in list(door_pkg.objects):
    if obj.name == "东墙人员门_状态照明" or is_structural_old_door(obj.name):
        bpy.data.objects.remove(obj, do_unlink=True)
    else:
        access_output.append(obj)
for obj in list(door_src_pkg.objects):
    if is_structural_old_door(obj.name):
        bpy.data.objects.remove(obj, do_unlink=True)

# Find matching editable sources for all retained peripheral/control pieces.
access_output_names = {obj.name for obj in access_output}
access_source = [
    obj for obj in list(door_src_pkg.objects)
    if source_output_name(obj.name) in access_output_names
]

# The reference correction is an actual position swap between the two current
# anchors, not a redesign of either silhouette.
door_old_anchor = Vector((14.22, -2.50, 0.0))
supply_old_anchor = Vector((13.52, 1.55, 0.0))
supply_delta = door_old_anchor - supply_old_anchor
access_delta = supply_old_anchor - door_old_anchor
for obj in list(supply_pkg.objects):
    obj.location += supply_delta
for obj in list(supply_src_pkg.objects):
    obj.location += supply_delta

# Door-side peripherals become their own independently maintained package and
# travel with the new door anchor.  They are intentionally not part of the
# canonical visual lift-door package.
access_pkg = bpy.data.collections.get("73_东墙门禁外围控制_资产包")
if access_pkg is None:
    access_pkg = reorg.new_package(
        "east_personnel_security_door", 73, "东墙门禁外围控制", "east_door_access_control", "east_facilities"
    )
access_pkg["本批次范围"] = "v017东墙门与SUPPLY24H位置互换；门禁外围内容从门体独立拆包"
access_pkg["宿主资产包"] = "east_personnel_security_door"
access_pkg["资产包类型"] = "门禁外围控制（独立维护）"
access_src_pkg = make_source_package("east_door_access_control", "east_facilities", "东墙门禁外围控制")
for obj in access_output:
    obj.location += access_delta
    reorg.move_object(obj, access_pkg)
for obj in access_source:
    obj.location += access_delta
    reorg.move_object(obj, access_src_pkg)

# Reuse the exact game asset rather than approximate it with new geometry.
before_import = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(GAME_DOOR))
imported = [obj for obj in bpy.data.objects if obj not in before_import and obj.type == "MESH"]
if len(imported) != 2:
    raise RuntimeError(f"Expected the game door GLB to create 2 mesh objects, got {len(imported)}")
main_mat = bpy.data.materials.get("02_细腻哑光_青绿大面")
emissive_mat = bpy.data.materials.get("04_柔和自发光_UI灯光")
if main_mat is None or emissive_mat is None:
    raise RuntimeError("Missing shared facility material role(s)")
door_meshes = []
for obj in imported:
    is_emissive = "灯光" in obj.name or "UI" in obj.name
    obj.name = "东墙标准滑升门_状态灯_柔和自发光" if is_emissive else "东墙标准滑升门_主体_金属哑光反光"
    # glTF imports default to quaternion rotation mode; set the mode before
    # assigning Euler coordinates or Blender keeps the previous quaternion.
    obj.rotation_mode = "XYZ"
    obj.rotation_euler = (0.0, 0.0, -math.pi / 2.0)
    obj.location = supply_old_anchor
    obj.data.materials.clear()
    obj.data.materials.append(emissive_mat if is_emissive else main_mat)
    reorg.move_object(obj, door_pkg)
    door_meshes.append(obj)

# A point state light is direct door equipment, so both output and source
# mirrors live under the same door package rather than a global-light folder.
lamp_data = bpy.data.lights.new("东墙滑升门_状态照明_灯光数据", type="POINT")
lamp_data.color = (0.05, 0.62, 1.0)
lamp_data.energy = 52.0
lamp_data.shadow_soft_size = 0.28
lamp = bpy.data.objects.new("东墙滑升门_状态照明", lamp_data)
lamp.location = (13.36, 1.55, 2.28)
door_pkg.objects.link(lamp)
lamp_source = lamp.copy()
lamp_source.data = lamp.data.copy()
lamp_source.name = "东墙滑升门_状态照明__源"
lamp_source.hide_render = True
lamp_source.hide_viewport = True
door_src_pkg.objects.link(lamp_source)

# Source mirrors must remain editable and independent from game-output meshes.
for obj in door_meshes:
    source = obj.copy()
    source.data = obj.data.copy()
    source.name = f"{obj.name}__源"
    source.hide_render = True
    source.hide_viewport = True
    door_src_pkg.objects.link(source)

door_pkg["本批次范围"] = "v017东墙门与SUPPLY24H位置互换；门体复用ENV-BASE99-DOOR-LIFT-22X25"
door_pkg["游戏资产ID"] = "ENV-BASE99-DOOR-LIFT-22X25"
door_pkg["逻辑ID"] = "base99_door_lift_2p2x2p5"
door_pkg["门体规格_m"] = "2.2 × 0.325 × 2.5（局部X/Y/Z；中心底部原点）"
door_pkg["布局锚点_m"] = [round(float(v), 4) for v in supply_old_anchor]
supply_pkg["本批次范围"] = "v017东墙门与SUPPLY24H位置互换；设备形体不重制"
supply_pkg["布局锚点_m"] = [round(float(v), 4) for v in door_old_anchor]

bpy.context.view_layer.update()
door_center, door_dimensions = reorg.bbox(door_meshes)
expected_door_dimensions = [0.325, 2.2, 2.5]  # after -90° Z scene orientation.
if any(abs(actual - expected) > 0.001 for actual, expected in zip(door_dimensions, expected_door_dimensions)):
    raise RuntimeError(f"Door visual bounds do not match canonical game spec: {door_dimensions}")
if any(abs(actual - expected) > 0.001 for actual, expected in zip(door_center, [13.52, 1.55, 1.25])):
    raise RuntimeError(f"Door visual center incorrect: {door_center}")
body = bpy.data.objects.get("SUPPLY24H_主体外壳")
if body is None or (Vector(body.location).xy - door_old_anchor.xy).length > 0.001:
    raise RuntimeError(f"SUPPLY 24H was not moved to the old door anchor: {body.location if body else None}")

# Rebuild every manifest and then enrich the task-specific contracts.
reorg.write_catalog(reorg.packages())
for slug, additions in {
    "east_personnel_security_door": {
        "task": "v017 east-wall door / SUPPLY 24H swap",
        "game_asset_contract": {
            "asset_id": "ENV-BASE99-DOOR-LIFT-22X25",
            "logic_id": "base99_door_lift_2p2x2p5",
            "source_glb": str(GAME_DOOR.relative_to(PROJECT)),
            "local_dimensions_m": [2.2, 0.325, 2.5],
            "scene_dimensions_m": expected_door_dimensions,
            "scene_anchor_m": [13.52, 1.55, 0.0],
            "scene_forward": "world -X (game local -Y after -90° Z)",
            "origin": "center-bottom",
            "runtime_motion": "vertical_lift",
            "collision_in_visual_glb": False,
        },
        "door_only": True,
        "access_control_package": "east_door_access_control",
    },
    "east_door_access_control": {
        "task": "v017 east-wall door / SUPPLY 24H swap",
        "attachment_to": "east_personnel_security_door",
        "scene_anchor_m": [13.52, 1.55, 0.0],
        "independent_asset_boundary": "door-adjacent access peripherals only; lift-door geometry excluded",
    },
    "east_supply_24h_station": {
        "task": "v017 east-wall door / SUPPLY 24H swap",
        "anchor_before_m": [13.52, 1.55, 0.0],
        "anchor_after_m": [14.22, -2.5, 0.0],
        "geometry_rebuilt": False,
    },
}.items():
    path = reorg.PACKAGE_ROOT / "east_facilities" / slug / "asset_manifest.json"
    manifest = json.loads(path.read_text(encoding="utf-8"))
    manifest.update(additions)
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

catalog = json.loads(reorg.CATALOG.read_text(encoding="utf-8"))
catalog["source"] = "v017 east-wall door / SUPPLY 24H swap"
catalog["scope"] = "Only east_personnel_security_door, east_supply_24h_station, and new east_door_access_control were modified; all other pre-existing objects are signature-locked."
catalog["package_count"] = len(reorg.packages())
reorg.CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

# Validate the scope lock after all collection/material/mesh mutations.
locks_after = {obj.name: reorg.signature(obj) for obj in bpy.data.objects if obj.name in locks_before}
lock_mismatches = {
    name: {"before": locks_before[name], "after": locks_after.get(name)}
    for name in locks_before if locks_before[name] != locks_after.get(name)
}
if lock_mismatches:
    raise RuntimeError(f"Unexpected locked-object changes: {sorted(lock_mismatches)[:8]}")

out_pkgs = reorg.packages()
empty_packages = [c.get("资产包键") for c in out_pkgs if not c.objects]
owners = {}
for coll in out_pkgs:
    for obj in coll.objects:
        owners.setdefault(obj.name, []).append(coll.get("资产包键"))
multi_owner = {name: keys for name, keys in owners.items() if len(keys) != 1}
source_mirror_ok = all(
    bpy.data.collections.get(f"v017_源资产包_{slug}") is not None
    and bpy.data.collections[f"v017_源资产包_{slug}"].objects
    for slug in ("east_personnel_security_door", "east_supply_24h_station", "east_door_access_control")
)
report = {
    "status": "pass",
    "blend": str(BLEND.relative_to(PROJECT)),
    "reference_image": "/var/folders/ms/hcx6wtnj0cvb4xbkxcd0b7bm0000gn/T/codex-clipboard-a9b4364e-8133-4dce-93af-02ce477c1b62.png",
    "allowed_packages": ["east_personnel_security_door", "east_supply_24h_station", "east_door_access_control"],
    "lock": {"locked_count": len(locks_before), "locked_match": not lock_mismatches, "mismatches": lock_mismatches},
    "package_count_before": len(out_pkgs) - 1,
    "package_count_after": len(out_pkgs),
    "empty_packages": empty_packages,
    "multi_owner": multi_owner,
    "source_mirror_ok": source_mirror_ok,
    "door": {
        "game_asset_id": "ENV-BASE99-DOOR-LIFT-22X25",
        "game_source_glb": str(GAME_DOOR.relative_to(PROJECT)),
        "asset_local_dimensions_m": [2.2, 0.325, 2.5],
        "scene_visual_center_m": door_center,
        "scene_visual_dimensions_m": door_dimensions,
        "scene_anchor_m": [13.52, 1.55, 0.0],
        "style": "canonical game lift door reused without free-form redesign",
    },
    "supply_24h": {"anchor_before_m": [13.52, 1.55, 0.0], "anchor_after_m": [14.22, -2.5, 0.0], "body": obj_row(body)},
    "old_door_objects_before": old_door_rows,
    "old_supply_objects_before": old_supply_rows,
    "new_door_package_objects": [obj_row(o) for o in sorted(door_pkg.objects, key=lambda o: o.name)],
    "new_access_package_objects": [obj_row(o) for o in sorted(access_pkg.objects, key=lambda o: o.name)],
}
VERIFY.mkdir(parents=True, exist_ok=True)
REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

bpy.context.scene["v017_iteration"] = "east_door_supply_swap"
bpy.context.scene["v017_iteration_scope"] = "east wall door + supply station + independent door access package"
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
print(json.dumps({
    "status": "pass", "door_dimensions": door_dimensions, "door_center": door_center,
    "supply_location": [round(float(v), 4) for v in body.location], "package_count": len(out_pkgs),
    "lock_count": len(locks_before), "access_objects": len(access_pkg.objects),
}, ensure_ascii=False))
