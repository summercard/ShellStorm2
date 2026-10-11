"""Export the normalized v002 stairwell assemblies from Blender source v009."""

from pathlib import Path

import bpy
from mathutils import Euler, Vector


SOURCE_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SOURCE_DIR.parent / "components"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

EXPORTS = (
    (
        "Stair_Generic_Rotatable_ROOT",
        "env_tower_stairwell_generic_9m_top3d_v002.glb",
        "ENV-TOWER-STAIRWELL-GENERIC-9M",
    ),
    (
        "Stair_Special_Rooftop_ROOT",
        "env_tower_stairwell_rooftop_9m_top3d_v002.glb",
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


def export_stairwell(root_name, filename, asset_id):
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
    root["asset_version"] = "v002"
    root["blender_source_version"] = "v009"
    root["origin_contract"] = "UPPER_DOOR_SOCKET"
    root["upper_floor_z_m"] = 0.0
    root["lower_floor_z_m"] = -9.0
    root["runtime_forward_local"] = [1.0, 0.0, 0.0]

    bpy.ops.object.select_all(action="DESELECT")
    selected = descendants(root)
    for obj in selected:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root

    output_path = OUTPUT_DIR / filename
    bpy.ops.export_scene.gltf(
        filepath=str(output_path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_extras=True,
        export_materials="EXPORT",
        export_image_format="NONE",
        export_cameras=False,
        export_lights=False,
        export_animations=False,
    )

    root.location = original_location
    root.rotation_euler = original_rotation
    root.scale = original_scale
    print(f"EXPORTED {root_name} -> {output_path} objects={len(selected)}")


for export_spec in EXPORTS:
    export_stairwell(*export_spec)

print(f"STAIRWELL_EXPORT_OK count={len(EXPORTS)} output={OUTPUT_DIR}")
