"""Render review images for the v006 five-metre modular tower source."""

from pathlib import Path

import bpy
from mathutils import Vector


PROJECT_ROOT = Path("/Users/summercards/ShellStorm2")
OUTPUT_DIR = (
    PROJECT_ROOT
    / "outputs/019facd3-bb17-7462-8504-0210c0919463/previews"
)
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.render.resolution_x = 1400
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.display.shading.light = "STUDIO"
scene.display.shading.studio_light = "paint.sl"
scene.display.shading.color_type = "MATERIAL"
scene.display.shading.show_shadows = False
scene.display.shading.show_cavity = True
scene.display.shading.cavity_type = "WORLD"
scene.display.shading.show_specular_highlight = True
scene.display.shading.background_type = "VIEWPORT"
scene.display.shading.background_color = (0.025, 0.032, 0.043)


def descendants(collection):
    result = {collection.name}
    for child in collection.children:
        result |= descendants(child)
    return result


def set_collection_visibility(root_names):
    visible_names = set()
    for name in root_names:
        collection = bpy.data.collections.get(name)
        if collection is not None:
            visible_names |= descendants(collection)
    for collection in bpy.data.collections:
        collection.hide_render = collection.name not in visible_names


def aim_camera(camera, location, target, ortho_scale):
    camera.location = location
    camera.rotation_euler = (
        Vector(target) - Vector(location)
    ).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = ortho_scale
    scene.camera = camera


def render(path):
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    print(f"RENDERED={path}")


def preview_linked(master_name, new_name, location, collection):
    master = bpy.data.objects[master_name]
    obj = master.copy()
    obj.data = master.data
    obj.name = new_name
    obj.location = location
    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.hide_viewport = False
    obj.hide_render = False
    collection.objects.link(obj)
    return obj


def preview_door(location, collection):
    source_root = bpy.data.objects["MOD_WALL_DOOR_5M_U01_ROOT"]
    root = bpy.data.objects.new("QA_MOD_WALL_DOOR_5M_U01_ROOT", None)
    collection.objects.link(root)
    root.location = location
    for source in source_root.children:
        if source.type != "MESH":
            continue
        child = source.copy()
        child.data = source.data
        child.name = f"QA_{source.name}"
        child.hide_viewport = False
        child.hide_render = False
        collection.objects.link(child)
        child.parent = root
        child.matrix_parent_inverse.identity()
        child.matrix_local = source.matrix_local.copy()
    return root


camera_data = bpy.data.cameras.new("CAM_V006_QA_Data")
camera = bpy.data.objects.new("CAM_V006_QA", camera_data)
bpy.data.collections["90_LIGHTS_CAMERAS"].objects.link(camera)

# Full rooftop: visible 5 m tile seams, four un-applied parapet arrays, and a
# grid-aligned stair void.
set_collection_visibility(
    {
        "01_FLOOR_ROOFTOP_Z000",
        "02A_STAIR_SPECIAL_ROOFTOP_TO_FACILITY",
        "90_LIGHTS_CAMERAS",
    }
)
aim_camera(camera, (330.0, -410.0, 300.0), (0.0, 0.0, -3.0), 390.0)
render(OUTPUT_DIR / "tower_blender_full_5m_rooftop_v006.png")

# Facility core: the 65 m base zone is enclosed by solid 5 m wall modules and
# two door modules aligned with the two stair assemblies.
set_collection_visibility(
    {
        "02_STAIRWELLS",
        "03_FLOOR_FACILITY_ZNEG009",
        "90_LIGHTS_CAMERAS",
    }
)
for name in ("03B_TILE_GRID_5M", "03C_OUTER_WALL_GRID_5M"):
    collection = bpy.data.collections.get(name)
    if collection:
        collection.hide_render = name == "03C_OUTER_WALL_GRID_5M"
aim_camera(camera, (95.0, -125.0, 115.0), (0.0, 0.0, -7.0), 105.0)
render(OUTPUT_DIR / "tower_blender_facility_modular_core_v006.png")

# Combat plan: every internal partition is a replaceable 5 m wall or door bay.
set_collection_visibility(
    {
        "05_FLOOR_COMBAT_ZNEG018",
        "90_LIGHTS_CAMERAS",
    }
)
outer_collection = bpy.data.collections.get("05C_OUTER_WALL_GRID_5M")
if outer_collection:
    outer_collection.hide_render = True
aim_camera(camera, (0.0, 0.0, 155.0), (0.0, 0.0, -18.0), 86.0)
render(OUTPUT_DIR / "tower_blender_combat_modular_layout_v006.png")

# Component review: display one copy of each hidden module master without
# changing the saved source scene.
preview_collection = bpy.data.collections.new("99_QA_MODULE_PREVIEW")
scene.collection.children.link(preview_collection)
preview_linked(
    "MOD_FLOOR_TILE_5M_U01",
    "QA_MOD_FLOOR_TILE_5M_U01",
    (-14.0, 0.0, 0.0),
    preview_collection,
)
preview_linked(
    "MOD_WALL_SOLID_5M_U01",
    "QA_MOD_WALL_SOLID_5M_U01",
    (-4.0, 0.0, 0.0),
    preview_collection,
)
preview_linked(
    "MOD_WALL_PARAPET_5M_U01",
    "QA_MOD_WALL_PARAPET_5M_U01",
    (6.0, 0.0, 0.0),
    preview_collection,
)
preview_door((16.0, 0.0, 0.0), preview_collection)
set_collection_visibility(
    {
        "99_QA_MODULE_PREVIEW",
        "90_LIGHTS_CAMERAS",
    }
)
aim_camera(camera, (32.0, -42.0, 25.0), (2.0, 0.0, 3.5), 43.0)
render(OUTPUT_DIR / "tower_blender_5m_module_library_v006.png")
