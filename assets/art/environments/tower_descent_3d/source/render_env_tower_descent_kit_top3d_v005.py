"""Render review images for the v005 full-footprint tower enclosure."""

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


def set_role_hidden(role, hidden):
    for obj in bpy.data.objects:
        if obj.get("asset_role") == role:
            obj.hide_render = hidden


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


camera_data = bpy.data.cameras.new("CAM_V005_QA_Data")
camera = bpy.data.objects.new("CAM_V005_QA", camera_data)
bpy.data.collections["90_LIGHTS_CAMERAS"].objects.link(camera)

# Facility plan: the external walls and the floor now share one 335.410 m edge.
set_collection_visibility(
    {
        "03_FLOOR_FACILITY_ZNEG009",
        "90_LIGHTS_CAMERAS",
    }
)
set_role_hidden("EMPTY_EXPANSION_FIELD", False)
aim_camera(camera, (0.0, 0.0, 430.0), (0.0, 0.0, -9.0), 365.0)
render(OUTPUT_DIR / "tower_blender_full_floor_enclosure_plan_v005.png")

# Rooftop review: the old 111.803 m parapet is gone and the new parapet follows
# the full map boundary while the special stair structure remains central.
set_collection_visibility(
    {
        "01_FLOOR_ROOFTOP_Z000",
        "02A_STAIR_SPECIAL_ROOFTOP_TO_FACILITY",
        "90_LIGHTS_CAMERAS",
    }
)
set_role_hidden("EMPTY_EXPANSION_FIELD", False)
aim_camera(camera, (330.0, -410.0, 290.0), (0.0, 0.0, -4.0), 390.0)
render(OUTPUT_DIR / "tower_blender_rooftop_full_boundary_v005.png")

# Exterior stack: two nine-metre facade bands and the rooftop parapet form one
# continuous building footprint around all three floors.
set_collection_visibility(
    {
        "01_FLOOR_ROOFTOP_Z000",
        "02_STAIRWELLS",
        "03_FLOOR_FACILITY_ZNEG009",
        "05_FLOOR_COMBAT_ZNEG018",
        "90_LIGHTS_CAMERAS",
    }
)
set_role_hidden("EMPTY_EXPANSION_FIELD", False)
aim_camera(camera, (390.0, -470.0, 280.0), (0.0, 0.0, -9.0), 405.0)
render(OUTPUT_DIR / "tower_blender_full_building_shell_v005.png")

# Close core review confirms that the manually edited stairs and room core did
# not scale or drift when the true exterior shell moved outward.
set_collection_visibility(
    {
        "02_STAIRWELLS",
        "03_FLOOR_FACILITY_ZNEG009",
        "90_LIGHTS_CAMERAS",
    }
)
set_role_hidden("EMPTY_EXPANSION_FIELD", True)
for obj in bpy.data.objects:
    if obj.get("asset_role") == "FULL_FOOTPRINT_EXTERIOR_WALL":
        obj.hide_render = True
aim_camera(camera, (120.0, -155.0, 110.0), (0.0, 0.0, -9.0), 120.0)
render(OUTPUT_DIR / "tower_blender_core_inside_full_floor_v005.png")
