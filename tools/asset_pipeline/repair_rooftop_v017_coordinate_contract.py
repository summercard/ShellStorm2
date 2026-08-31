#!/usr/bin/env python3
"""One-time v017 coordinate-contract repair without regenerating GLBs.

Run the Blender section with Blender's bundled Python, then run this file with
the project Python to patch the already-imported Godot wrapper scene.  The two
operations deliberately do not export assets and do not invoke Godot import.
"""

from __future__ import annotations

import re
import sys
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "assets/art/environments/rooftop_shelter_3d/source/env_rooftop_shelter_90x80m_top3d_v017.blend"
TSCN_PATH = ROOT / "assets/art/environments/rooftop_shelter_3d/runtime/env_rooftop_shelter_90x80m_facilities_root_top3d_v017.tscn"
ASSET_MANIFEST_PATH = ROOT / "assets/art/environments/rooftop_shelter_3d/reports/asset_manifest_v017.json"
COLLISION_MANIFEST_PATH = ROOT / "assets/art/environments/rooftop_shelter_3d/reports/collision_manifest_v017.json"
BLENDER_BASIS_MARKER = "Godot (X, Z, -Y); runtime output mirrored on Blender Y"


def _flip_vector3_z(line: str) -> str:
    match = re.fullmatch(r"(\s*position = Vector3\()([^,]+),([^,]+),\s*([^)]+)(\)\s*)", line)
    if match is None:
        raise RuntimeError(f"Unexpected Vector3 position syntax: {line!r}")
    z_text = match.group(4).strip()
    z_value = float(z_text)
    return f"{match.group(1)}{match.group(2)},{match.group(3)}, {-z_value:.5f}{match.group(5)}"


def patch_godot_wrapper() -> None:
    lines = TSCN_PATH.read_text(encoding="utf-8").splitlines(keepends=True)
    platform_position = next((line for index, line in enumerate(lines) if 'name="05_抬高木平台"' in line for line in lines[index + 1:index + 4] if line.lstrip().startswith("position = Vector3(")), None)
    if platform_position is not None and float(platform_position.rstrip(").\n").split(",")[-1]) > 0.0:
        print("Godot wrapper already uses the repaired coordinate basis")
        return
    changed_components = 0
    changed_shapes = 0
    current_node = ""
    current_type = ""
    result: list[str] = []

    for line in lines:
        node_match = re.match(r'\[node name="([^"]+)" type="([^"]+)"', line)
        if node_match:
            current_node, current_type = node_match.groups()
        if line.lstrip().startswith("position = Vector3("):
            if current_type == "CollisionShape3D":
                result.append(_flip_vector3_z(line.rstrip("\n")) + "\n")
                changed_shapes += 1
                continue
            if current_type == "Node3D" and current_node != "布局_可手动编辑":
                # Only editable direct component nodes have a position directly
                # after their declaration.  Group nodes have no position.
                result.append(_flip_vector3_z(line.rstrip("\n")) + "\n")
                changed_components += 1
                continue
        result.append(line)

    if changed_components != 68:
        raise RuntimeError(f"Expected 68 editable component positions, patched {changed_components}")
    if changed_shapes != 82:
        raise RuntimeError(f"Expected 82 collision-shape positions, patched {changed_shapes}")
    TSCN_PATH.write_text("".join(result), encoding="utf-8")
    print(f"Patched Godot wrapper: {changed_components} components, {changed_shapes} collision shapes")


def patch_blend() -> None:
    import bpy  # Available only under Blender's Python runtime.

    scene = bpy.context.scene
    if scene.get("coordinate_basis_repair") == BLENDER_BASIS_MARKER:
        print("Blender scene already uses the repaired coordinate basis")
        return

    output = bpy.data.collections.get("02_游戏输出_独立模块")
    collision = bpy.data.collections.get("03_阻挡代理_不导出")
    if output is None or collision is None:
        raise RuntimeError("Expected rooftop output and collision collections were not found")

    objects = set()
    for collection in output.children:
        if collection.name == "远景荒废城市_低对比":
            continue
        objects.update(collection.all_objects)
    objects.update(collision.all_objects)

    for obj in objects:
        matrix = obj.matrix_world.copy()
        matrix.translation.y = -matrix.translation.y
        obj.matrix_world = matrix

    scene["coordinate_basis_repair"] = BLENDER_BASIS_MARKER
    scene["source_roof_world_rect"] = "Rect2(-50, -45, 90, 80)"
    scene["godot_rooftop_world_rect"] = "Rect2(-50, -35, 90, 80)"
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    print(f"Patched Blender scene: mirrored {len(objects)} runtime-output objects on Y")


def patch_reports() -> None:
    """Keep the v017 ledger in the repaired Blender coordinate basis."""
    asset_manifest = json.loads(ASSET_MANIFEST_PATH.read_text(encoding="utf-8"))
    if asset_manifest.get("coordinate_source") == "Blender X/Y/Z-up metres; runtime output mirrored on Blender Y":
        print("v017 ledgers already use the repaired coordinate basis")
        return
    for component in asset_manifest["editable_components"]:
        pivot = component["pivot"]
        pivot[1] = -pivot[1]
        min_x, min_y, min_z, max_x, max_y, max_z = component["bounds_world"]
        component["bounds_world"] = [min_x, -max_y, min_z, max_x, -min_y, max_z]
    asset_manifest["coordinate_source"] = "Blender X/Y/Z-up metres; runtime output mirrored on Blender Y"
    asset_manifest["runtime_coordinate_mapping"] = "Godot (X, Z, -Y)"
    ASSET_MANIFEST_PATH.write_text(json.dumps(asset_manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    collision_manifest = json.loads(COLLISION_MANIFEST_PATH.read_text(encoding="utf-8"))
    for component in collision_manifest["components"]:
        for shape in component["shapes"]:
            shape["center"][1] = -shape["center"][1]
    collision_manifest["coordinate_source"] = "Blender X/Y/Z-up metres; runtime output mirrored on Blender Y"
    collision_manifest["runtime_coordinate_mapping"] = "Godot (X, Z, -Y)"
    COLLISION_MANIFEST_PATH.write_text(json.dumps(collision_manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Patched v017 asset and collision ledgers")


if __name__ == "__main__":
    if "--blender" in sys.argv:
        patch_blend()
    elif "--reports" in sys.argv:
        patch_reports()
    else:
        patch_godot_wrapper()
        patch_reports()
