"""Export the two user-authored v006 stairwell assemblies for Godot.

The Blender review file stores each stairwell at its real floor position.
Runtime assets instead use a normalized contract:

- the upper-door socket is the local origin;
- Blender Z=0 is the upper floor and Z=-9 is the lower floor;
- local +X points out of the 65 m gameplay core;
- the whole assembly can be rotated around its root in Godot.

Only transforms on the assembly root are normalized temporarily. Child meshes,
hand-edited wall heights, tread placement, materials, and semantic extras are
exported directly from the user's Blender model.
"""

from pathlib import Path

import bpy
from mathutils import Euler, Vector


SOURCE_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SOURCE_DIR.parent / "components"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

EXPORTS = (
    (
        "Stair_Generic_Rotatable_ROOT",
        "env_tower_stairwell_generic_9m_top3d_v001.glb",
        "ENV-TOWER-STAIRWELL-GENERIC-9M",
    ),
    (
        "Stair_Special_Rooftop_ROOT",
        "env_tower_stairwell_rooftop_9m_top3d_v001.glb",
        "ENV-TOWER-STAIRWELL-ROOFTOP-9M",
    ),
)


def descendants(root):
    result = [root]
    stack = list(root.children)
    while stack:
        obj = stack.pop()
        result.append(obj)
        stack.extend(obj.children)
    return result


def export_stairwell(root_name: str, filename: str, asset_id: str) -> None:
    root = bpy.data.objects.get(root_name)
    if root is None:
        raise RuntimeError(f"Missing stairwell root: {root_name}")

    original_location = root.location.copy()
    original_rotation = root.rotation_euler.copy()
    original_scale = root.scale.copy()
    root.location = Vector((0.0, 0.0, 0.0))
    root.rotation_euler = Euler((0.0, 0.0, 0.0), "XYZ")
    root.scale = Vector((1.0, 1.0, 1.0))
    root["asset_id"] = asset_id
    root["origin_contract"] = "UPPER_DOOR_SOCKET"
    root["upper_floor_y_m"] = 0.0
    root["lower_floor_y_m"] = -9.0
    root["runtime_forward_local"] = [1.0, 0.0, 0.0]

    bpy.ops.object.select_all(action="DESELECT")
    selected = descendants(root)
    for obj in selected:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root

    if not any(obj.type == "MESH" for obj in selected):
        raise RuntimeError(f"Stairwell has no mesh: {root_name}")

    output_path = OUTPUT_DIR / filename
    bpy.ops.export_scene.gltf(
        filepath=str(output_path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_extras=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_animations=False,
    )

    root.location = original_location
    root.rotation_euler = original_rotation
    root.scale = original_scale
    print(
        "EXPORTED "
        f"{root_name} -> {output_path} "
        f"objects={len(selected)} asset_id={asset_id}"
    )


for export_spec in EXPORTS:
    export_stairwell(*export_spec)

print(f"STAIRWELL_EXPORT_OK count={len(EXPORTS)} output={OUTPUT_DIR}")
