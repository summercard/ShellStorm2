#!/usr/bin/env python3
"""Read-only validation of the v017 west third-bay runtime door assembly."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import bpy

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
PACKAGES = PROJECT / "source/art/blender/base_facility_layout/component_packages_v017"
ASSEMBLY = PACKAGES / "component_sets/west_door_wall_set/assembly_manifest.json"
REPORT = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v017/west_door_wall_set_package_validation.json"
VALIDATOR = PROJECT / ".codex/skills/blender-game-prop-standard/scripts/validate_game_prop.py"
PALETTE = PROJECT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("must run with v017 open")

spec = importlib.util.spec_from_file_location("v017_reorg", PROJECT / "scripts/blender/reorganize_base_facility_component_packages_v017.py")
reorg = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(reorg)
validator_spec = importlib.util.spec_from_file_location("game_prop_validator", VALIDATOR)
validator = importlib.util.module_from_spec(validator_spec)
assert validator_spec.loader is not None
validator_spec.loader.exec_module(validator)

errors = []
wall = reorg.package_by_slug("west_door_wall_module")
leaf = reorg.package_by_slug("west_door_lift_instance")
wall_source = bpy.data.collections.get("v017_源资产包_west_door_wall_module")
leaf_source = bpy.data.collections.get("v017_源资产包_west_door_lift_instance")
if wall_source is None or leaf_source is None:
    errors.append("missing source mirror package")
if len(wall.objects) != 3 or len(wall_source.objects) != 3:
    errors.append("west wall package/source must each contain exactly anchor, root and wall mesh")
if len(leaf.objects) != 4 or len(leaf_source.objects) != 4:
    errors.append("west leaf placement/source must each contain root, body, emissive mesh and local lamp")

west_wall = bpy.data.objects.get("西墙带门墙体_主体_金属哑光反光")
west_leaf = bpy.data.objects.get("西墙标准滑升门_主体_金属哑光反光")
west_emit = bpy.data.objects.get("西墙标准滑升门_状态灯_柔和自发光")
if west_wall is None or west_leaf is None or west_emit is None:
    errors.append("missing expected west visual meshes")
else:
    center, dimensions = reorg.bbox((west_wall,))
    if center != [-15.0, 2.5, 4.5] or dimensions != [1.051, 5.0, 9.0]:
        errors.append(f"west wall visual envelope mismatch {center} {dimensions}")
    leaf_center, leaf_dimensions = reorg.bbox((west_leaf, west_emit))
    if leaf_center != [-15.0, 2.5, 1.27] or leaf_dimensions != [0.898, 2.04, 2.34]:
        errors.append(f"west door leaf envelope mismatch {leaf_center} {leaf_dimensions}")
    root = bpy.data.objects.get("ENV-BASE99-WALL-DOOR-5X9_WEST_输出根节点")
    leaf_root = bpy.data.objects.get("ENV-BASE99-DOOR-LIFT-22X25_WEST_输出根节点")
    if root is None or [round(float(v), 4) for v in root.matrix_world.translation] != [-15.0, 2.5, 0.0] or round(float(root.matrix_world.to_euler().z), 6) != 1.570796:
        errors.append("west wall root is not on Blender third-from-north bay")
    if leaf_root is None or [round(float(v), 4) for v in leaf_root.matrix_world.translation] != [-15.0, 2.5, 0.0] or round(float(leaf_root.matrix_world.to_euler().z), 6) != 1.570796:
        errors.append("west door leaf root does not align to wall root")
    # The source geometry must be symmetric around its local thickness centre:
    # this detects a one-sided portal/leaf or a detached front-only frame.
    for label, obj, expected_half_depth in (
        ("wall", west_wall, 0.5255),
        ("door", west_leaf, 0.4375),
    ):
        local_y = [vertex.co.y for vertex in obj.data.vertices]
        if round(min(local_y), 4) != -expected_half_depth or round(max(local_y), 4) != expected_half_depth:
            errors.append(f"{label} is not double-sided around local wall centre")
    if abs(center[0] - leaf_center[0]) > 0.0001 or abs(center[1] - leaf_center[1]) > 0.0001:
        errors.append("wall portal and door slab have different world centres")

if bpy.data.objects["保留西墙_02"].location.y != -2.5:
    errors.append("fourth bay anchor changed unexpectedly")
plain = bpy.data.objects.get("普通墙体_主体_金属哑光反光.017")
plain_center, _ = reorg.bbox((plain,)) if plain else ([0, 0, 0], [0, 0, 0])
if plain_center[1] != -2.5:
    errors.append("plain wall did not replace old fourth door bay")
if any("门禁" in obj.name or "ACCESS" in obj.name for obj in leaf.objects):
    errors.append("east-only access control leaked into west runtime pair")
if "西墙滑升门_状态照明" not in leaf.objects:
    errors.append("west local door light is not owned by the emitting door placement")
lamp = bpy.data.objects.get("西墙滑升门_状态照明")
if lamp is None or [round(float(v), 4) for v in lamp.location] != [-15.0, 2.5, 2.05]:
    errors.append("west local door light is not centred for the double-sided leaf")

wall_manifest = json.loads((PACKAGES / "architecture/west_door_wall_module/asset_manifest.json").read_text(encoding="utf-8"))
leaf_manifest = json.loads((PACKAGES / "west_facilities/west_door_lift_instance/asset_manifest.json").read_text(encoding="utf-8"))
if wall_manifest.get("asset_id") != "ENV-BASE99-WALL-DOOR-5X9" or leaf_manifest.get("asset_id") != "ENV-BASE99-DOOR-LIFT-22X25":
    errors.append("manifest AssetID does not match game runtime component")
for manifest in (wall_manifest, leaf_manifest):
    for path_key in ("runtime_prefab", "runtime_visual_glb"):
        if not (PROJECT / str(manifest.get(path_key, ""))).is_file():
            errors.append(f"missing runtime path {path_key}")
assembly = json.loads(ASSEMBLY.read_text(encoding="utf-8"))
members = assembly.get("members", [])
if [member.get("asset_id") for member in members] != ["ENV-BASE99-WALL-DOOR-5X9", "ENV-BASE99-DOOR-LIFT-22X25"]:
    errors.append("assembly member AssetID order mismatches game component pair")
placement = assembly.get("runtime_placement", {})
if placement.get("godot_position_m") != [-15.0, -9.0, 2.5] or placement.get("blender_position_m") != [-15.0, 2.5, 0.0]:
    errors.append("runtime/Blender placement contract mismatch")
interface = assembly.get("interface_contract", {})
if "symmetric" not in str(interface.get("portal", "")) or "symmetric" not in str(interface.get("door_leaf", "")):
    errors.append("assembly does not declare the required double-sided portal and leaf contract")

meshes = [obj for collection in (wall, leaf, wall_source, leaf_source) for obj in collection.objects if obj.type == "MESH"]
uv_reports = [validator.audit_palette_uv(obj) for obj in meshes]
materials = validator.material_audit(meshes, PALETTE)
if any(report["missing_palette_uv"] or report["valid_island_polygon_count"] != report["polygon_count"] or report["extra_uv_layers"] for report in uv_reports):
    errors.append("PaletteUV per-face contract failed in west packages")
if materials["bad_uv_map_nodes"] or materials["missing_uv_map_nodes"] or materials["bad_image_interpolation"] or materials["non_shared_palette_images"] or materials["packed_palette_images"]:
    errors.append("shared palette/material contract failed in west packages")
owners = {obj.name: [collection.get("资产包键") for collection in obj.users_collection if collection.get("资产包")] for obj in bpy.data.objects}
multiple = {name: values for name, values in owners.items() if len(values) > 1}
if multiple:
    errors.append("multi-package output object ownership")

result = {
    "status": "pass" if not errors else "fail",
    "game_runtime": {"wall": "ENV-BASE99-WALL-DOOR-5X9", "door": "ENV-BASE99-DOOR-LIFT-22X25", "position_m": [-15.0, -9.0, 2.5], "rotation_y_rad": 1.57079632679},
    "blender_placement": {"position_m": [-15.0, 2.5, 0.0], "rotation_z_rad": 1.57079632679, "north_to_south_index": 3},
    "double_sided_visual_contract": {"wall_max_depth_m": 1.051, "door_max_depth_m": 0.898, "wall_core_depth_m": 0.36, "door_slab_depth_m": 0.62},
    "package_count": len(reorg.packages()),
    "wall_package_objects": len(wall.objects),
    "leaf_instance_objects": len(leaf.objects),
    "mesh_count": len(meshes),
    "polygon_count": sum(report["polygon_count"] for report in uv_reports),
    "valid_palette_faces": sum(report["valid_island_polygon_count"] for report in uv_reports),
    "used_materials": materials["used_materials"],
    "multi_package_objects": multiple,
    "errors": errors,
    "runtime_note": "No runtime GLB or PackedScene changed; manifests map these Blender placements to the two existing replaceable game component paths.",
}
REPORT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(result, ensure_ascii=False))
if errors:
    raise SystemExit(1)
