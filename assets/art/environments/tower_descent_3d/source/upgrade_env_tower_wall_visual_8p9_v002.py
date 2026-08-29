"""Create the native 8.9 m tower wall visual and a versioned Blender source.

Run with env_tower_descent_kit_top3d_v007.blend open in Blender background mode.
The lower interface remains at Z=0. Only the existing top bevel cluster moves
down by 0.1 m, so the visual top becomes Z=8.9 while the 9 m gameplay
collision remains owned by Godot.
"""

from pathlib import Path

import bpy


SOURCE_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SOURCE_DIR.parents[4]
OUTPUT_BLEND = SOURCE_DIR / "env_tower_descent_kit_top3d_v008.blend"
OUTPUT_GLB = (
    PROJECT_DIR
    / "assets/art/environments/tower_descent_3d/components"
    / "env_tower_wall_solid_5m_top3d_v002.glb"
)
WALL_OBJECT_NAME = "MOD_WALL_SOLID_5M_U01"
WALL_COLLECTION_NAME = "10B_MOD_WALL_SOLID_5M_U01"
EXPECTED_SOURCE_HEIGHT = 9.0
VISUAL_HEIGHT = 8.9
TOP_CLEARANCE = EXPECTED_SOURCE_HEIGHT - VISUAL_HEIGHT


wall = bpy.data.objects.get(WALL_OBJECT_NAME)
if wall is None or wall.type != "MESH":
    raise RuntimeError(f"Missing mesh object: {WALL_OBJECT_NAME}")

z_values = [vertex.co.z for vertex in wall.data.vertices]
source_min = min(z_values)
source_max = max(z_values)
if abs(source_min) > 1.0e-6 or abs(source_max - EXPECTED_SOURCE_HEIGHT) > 1.0e-6:
    raise RuntimeError(
        f"Unexpected wall source bounds: min={source_min:.6f} max={source_max:.6f}"
    )

# The wall only has a lower and upper bevel cluster. Move the upper cluster as
# geometry instead of scaling the object, preserving the bottom origin and the
# bevel thickness.
for vertex in wall.data.vertices:
    if vertex.co.z > EXPECTED_SOURCE_HEIGHT * 0.5:
        vertex.co.z -= TOP_CLEARANCE
wall.data.update()

wall["dimensions_m"] = [5.0, 0.3, VISUAL_HEIGHT]
wall["logical_height_m"] = EXPECTED_SOURCE_HEIGHT
wall["visual_height_m"] = VISUAL_HEIGHT
wall["visual_top_clearance_m"] = TOP_CLEARANCE
wall["origin_contract"] = "BOTTOM_CENTER"

scene = bpy.context.scene
scene["asset_version"] = "v008"
scene["tower_wall_visual_height_m"] = VISUAL_HEIGHT
scene["tower_wall_logical_height_m"] = EXPECTED_SOURCE_HEIGHT
scene["tower_wall_visual_top_clearance_m"] = TOP_CLEARANCE
scene["derived_from"] = str(
    SOURCE_DIR / "env_tower_descent_kit_top3d_v007.blend"
)

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))

collection = bpy.data.collections.get(WALL_COLLECTION_NAME)
if collection is None:
    raise RuntimeError(f"Missing wall collection: {WALL_COLLECTION_NAME}")


def collect_objects(source_collection):
    result = list(source_collection.objects)
    for child_collection in source_collection.children:
        result.extend(collect_objects(child_collection))
    return result


bpy.ops.object.select_all(action="DESELECT")
selected = []
for obj in collect_objects(collection):
    if obj.type not in {"MESH", "EMPTY"}:
        continue
    obj.hide_set(False)
    obj.hide_viewport = False
    obj.hide_render = False
    obj.select_set(True)
    selected.append(obj)
bpy.context.view_layer.objects.active = wall

OUTPUT_GLB.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=str(OUTPUT_GLB),
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

final_z = [vertex.co.z for vertex in wall.data.vertices]
print(
    "TOWER_WALL_NATIVE_8P9_EXPORT_OK "
    f"bounds=({min(final_z):.3f},{max(final_z):.3f}) "
    f"blend={OUTPUT_BLEND} glb={OUTPUT_GLB} objects={len(selected)}"
)
