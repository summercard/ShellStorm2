#!/usr/bin/env python3
"""Clone the approved west double-sided door set into the east door-wall set.

The data blocks are copied, never linked: east and west remain independently
managed asset packages, while the symmetric geometry automatically preserves the
opposite east-facing wall orientation.  East-only access-control dressing is
outside scope and remains untouched.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import bpy

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
PACKAGES = PROJECT / "source/art/blender/base_facility_layout/component_packages_v017"
VERIFY = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v017"
REPORT = VERIFY / "east_door_wall_copied_from_west_acceptance.json"
ASSEMBLY = PACKAGES / "component_sets/east_door_wall_set/assembly_manifest.json"
if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("must run with v017 open")

spec = importlib.util.spec_from_file_location(
    "v017_reorg", PROJECT / "scripts/blender/reorganize_base_facility_component_packages_v017.py"
)
reorg = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(reorg)

east_wall_package = reorg.package_by_slug("east_door_wall_module")
east_door_package = reorg.package_by_slug("east_personnel_security_door")
east_wall_source_package = bpy.data.collections["v017_源资产包_east_door_wall_module"]
east_door_source_package = bpy.data.collections["v017_源资产包_east_personnel_security_door"]

east_wall = bpy.data.objects["带门墙体_主体_金属哑光反光.002"]
east_wall_source = bpy.data.objects["带门墙体_主体_金属哑光反光.002__源"]
east_door = bpy.data.objects["东墙标准滑升门_主体_金属哑光反光"]
east_door_source = bpy.data.objects["东墙标准滑升门_主体_金属哑光反光__源"]
east_emissive = bpy.data.objects["东墙标准滑升门_状态灯_柔和自发光"]
east_emissive_source = bpy.data.objects["东墙标准滑升门_状态灯_柔和自发光__源"]
east_lamp = bpy.data.objects["东墙滑升门_状态照明"]
east_lamp_source = bpy.data.objects["东墙滑升门_状态照明__源"]

west_wall = bpy.data.objects["西墙带门墙体_主体_金属哑光反光"]
west_door = bpy.data.objects["西墙标准滑升门_主体_金属哑光反光"]
west_emissive = bpy.data.objects["西墙标准滑升门_状态灯_柔和自发光"]
west_lamp = bpy.data.objects["西墙滑升门_状态照明"]
east_access = bpy.data.objects["东墙人员门_门侧控制面板"]

allowed = set(east_wall_package.objects) | set(east_door_package.objects) | set(east_wall_source_package.objects) | set(east_door_source_package.objects)
locked_before = {obj.name: reorg.signature(obj) for obj in bpy.data.objects if obj not in allowed}
access_before = reorg.signature(east_access)

for target, source, mesh_name in (
    (east_wall, west_wall, "东墙带门墙体_主体_复用西侧双面对齐网格"),
    (east_wall_source, west_wall, "东墙带门墙体_主体_复用西侧双面对齐网格__源"),
    (east_door, west_door, "东墙标准滑升门_复用西侧双面加厚主体网格"),
    (east_door_source, west_door, "东墙标准滑升门_复用西侧双面加厚主体网格__源"),
    (east_emissive, west_emissive, "东墙标准滑升门_复用西侧双面状态灯网格"),
    (east_emissive_source, west_emissive, "东墙标准滑升门_复用西侧双面状态灯网格__源"),
):
    target.data = source.data.copy()
    target.data.name = mesh_name

# The source meshes are copied from the west source too, so each east package
# mirrors its exact output data without sharing editable datablocks with west.
for target, source in ((east_wall_source, east_wall), (east_door_source, east_door), (east_emissive_source, east_emissive)):
    target.data = source.data.copy()
    target.data.name = f"{source.data.name}__源"

for lamp in (east_lamp, east_lamp_source):
    lamp.location = (15.0, 2.5, 2.05)
    lamp.data.energy = west_lamp.data.energy
    lamp.data.color = west_lamp.data.color
    lamp["归属发光设施"] = "east_personnel_security_door"
    lamp["参考版本"] = "v017_east_copies_west_double_sided_003"

for obj in (east_wall, east_wall_source):
    obj["高还原结构"] = "复用 west_door_wall_module 的双面闭合八角门框；360mm墙芯与东侧墙中线对齐"
    obj["门框归属"] = "east_door_wall_module（墙体所有；与西侧同构但不共享网格数据）"
    obj["参考版本"] = "v017_east_copies_west_double_sided_003"
for obj in (east_door, east_door_source, east_emissive, east_emissive_source):
    obj["高还原结构"] = "复用 west_door_lift_instance 的620mm双面加厚滑升门；两面同构"
    obj["参考版本"] = "v017_east_copies_west_double_sided_003"

bpy.context.view_layer.update()
east_wall_center, east_wall_dims = reorg.bbox((east_wall,))
east_door_center, east_door_dims = reorg.bbox((east_door, east_emissive))
if east_wall_center != [15.0, 2.5, 4.5] or east_wall_dims != [1.051, 5.0, 9.0]:
    raise RuntimeError(f"east wall mismatch: {east_wall_center} {east_wall_dims}")
if east_door_center != [15.0, 2.5, 1.27] or east_door_dims != [0.898, 2.04, 2.34]:
    raise RuntimeError(f"east door mismatch: {east_door_center} {east_door_dims}")
for label, obj, half_depth in (("wall", east_wall, 0.5255), ("door", east_door, 0.4375)):
    depth = [vertex.co.y for vertex in obj.data.vertices]
    if round(min(depth), 4) != -half_depth or round(max(depth), 4) != half_depth:
        raise RuntimeError(f"east {label} lost its symmetric double-sided mesh")
for obj in (east_wall, east_wall_source, east_door, east_door_source, east_emissive, east_emissive_source):
    uv = obj.data.uv_layers.get("PaletteUV")
    if [layer.name for layer in obj.data.uv_layers] != ["PaletteUV"] or obj.data.uv_layers.active != uv or not uv.active_render:
        raise RuntimeError(f"PaletteUV contract failed: {obj.name}")
if reorg.signature(east_access) != access_before:
    raise RuntimeError("east-only access-control asset changed")

for package, revision in (
    (east_wall_package, "v017_east_copies_west_double_sided_003"),
    (east_door_package, "v017_east_copies_west_double_sided_003"),
):
    category = str(package["资产类别"])
    slug = str(package["资产包键"])
    manifest_path = PACKAGES / category / slug / "asset_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest.update({
        "visual_revision": revision,
        "visual_source": "west double-sided approved set copied as independent east mesh data",
        "double_sided_design": True,
    })
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

assembly = json.loads(ASSEMBLY.read_text(encoding="utf-8"))
assembly["visual_revision"] = "v017_east_copies_west_double_sided_003"
assembly["visual_source"] = "west_door_wall_module + west_door_lift_instance geometry copied as independent east package meshes"
assembly["double_sided_design"] = True
ASSEMBLY.write_text(json.dumps(assembly, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

# Keep the catalog contemporary without rewriting unrelated package manifests.
catalog = json.loads(reorg.CATALOG.read_text(encoding="utf-8"))
for package in (east_wall_package, east_door_package):
    slug = str(package["资产包键"])
    entry = next(candidate for candidate in catalog["packages"] if candidate["asset_slug"] == slug)
    visual = [obj for obj in package.objects if obj.type == "MESH"]
    center, dimensions = reorg.bbox(visual)
    entry.update({
        "object_count": len(package.objects),
        "mesh_count": len(visual),
        "light_count": sum(obj.type == "LIGHT" for obj in package.objects),
        "object_names": sorted(obj.name for obj in package.objects),
        "world_center_m": center,
        "bounding_size_m": dimensions,
        "visual_revision": "v017_east_copies_west_double_sided_003",
        "double_sided_design": True,
    })
catalog["source"] = "v017 east door wall receives independent copy of west double-sided approved set"
catalog["scope"] = "Only east_door_wall_module and east_personnel_security_door geometry/source mirrors were revised; east access-control and all other objects remain signature locked."
reorg.CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

locked_after = {obj.name: reorg.signature(obj) for obj in bpy.data.objects if obj.name in locked_before}
mismatches = {name: {"before": locked_before[name], "after": locked_after.get(name)} for name in locked_before if locked_before[name] != locked_after.get(name)}
if mismatches:
    raise RuntimeError(f"outside-scope changes: {list(mismatches)[:8]}")

report = {
    "status": "pass",
    "revision": "v017_east_copies_west_double_sided_003",
    "source": "approved west double-sided wall and door mesh data copied independently",
    "scope": "east_door_wall_module + east_personnel_security_door and source mirrors only",
    "locked_outside_scope": len(locked_before),
    "locked_mismatches": mismatches,
    "east_access_control_unchanged": True,
    "wall": {"center_m": east_wall_center, "envelope_m": east_wall_dims, "core_depth_m": 0.36},
    "door": {"center_m": east_door_center, "envelope_m": east_door_dims, "slab_depth_m": 0.62},
    "double_sided": True,
    "independent_mesh_data": all(target.data != source.data for target, source in ((east_wall, west_wall), (east_door, west_door), (east_emissive, west_emissive))),
}
REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
bpy.context.scene["v017_iteration"] = "east_copies_west_double_sided_003"
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
print(json.dumps(report, ensure_ascii=False))
