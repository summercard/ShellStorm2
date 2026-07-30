"""Render review images for the refined v004 tower scene."""

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
scene.display.shading.show_shadows = True
scene.display.shading.show_cavity = True
scene.display.shading.cavity_type = "WORLD"
scene.display.shading.show_specular_highlight = True
scene.display.shading.background_type = "VIEWPORT"
scene.display.shading.background_color = (0.025, 0.032, 0.043)


def set_collection_visibility(visible):
    for collection in bpy.data.collections:
        if collection.name in {
            "02A_STAIR_SPECIAL_ROOFTOP_TO_FACILITY",
            "02B_STAIR_GENERIC_ROTATABLE",
        }:
            collection.hide_render = "02_STAIRWELLS" not in visible
        else:
            collection.hide_render = collection.name not in visible


def set_outer_fields_hidden(hidden):
    for obj in bpy.data.objects:
        if obj.get("asset_role") == "EMPTY_EXPANSION_FIELD":
            obj.hide_render = hidden


def aim_camera(camera, location, target, ortho_scale):
    camera.location = location
    camera.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = ortho_scale
    scene.camera = camera


def render(path):
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    print(f"RENDERED={path}")


camera_data = bpy.data.cameras.new("CAM_V004_QA_Data")
camera = bpy.data.objects.new("CAM_V004_QA", camera_data)
bpy.data.collections["90_LIGHTS_CAMERAS"].objects.link(camera)

# Overall footprint: empty 335.410m field with the preserved 67.082m core.
set_collection_visibility(
    {
        "03_FLOOR_FACILITY_ZNEG009",
        "90_LIGHTS_CAMERAS",
    }
)
set_outer_fields_hidden(False)
aim_camera(camera, (0.0, 0.0, 420.0), (0.0, 0.0, -9.0), 365.0)
render(OUTPUT_DIR / "tower_blender_map_footprint_v004.png")

# Central three-floor stack and both stair variants.
set_collection_visibility(
    {
        "00_BUILDING_GUIDES",
        "01_FLOOR_ROOFTOP_Z000",
        "02_STAIRWELLS",
        "03_FLOOR_FACILITY_ZNEG009",
        "05_FLOOR_COMBAT_ZNEG018",
        "90_LIGHTS_CAMERAS",
    }
)
set_outer_fields_hidden(True)
aim_camera(camera, (135.0, -175.0, 115.0), (0.0, 0.0, -7.0), 145.0)
render(OUTPUT_DIR / "tower_blender_core_stack_v004.png")

# Plan view of the preserved core, fence openings, and both stair footprints.
set_collection_visibility(
    {
        "02_STAIRWELLS",
        "03_FLOOR_FACILITY_ZNEG009",
        "90_LIGHTS_CAMERAS",
    }
)
set_outer_fields_hidden(True)
aim_camera(camera, (0.0, 0.0, 140.0), (0.0, 0.0, -9.0), 105.0)
render(OUTPUT_DIR / "tower_blender_stair_core_plan_v004.png")

# Low-angle stair review makes the intentional rooftop wall-height override clear.
set_collection_visibility(
    {
        "02_STAIRWELLS",
        "90_LIGHTS_CAMERAS",
    }
)
set_outer_fields_hidden(True)
aim_camera(camera, (105.0, -150.0, 42.0), (0.0, 0.0, -6.0), 125.0)
render(OUTPUT_DIR / "tower_blender_stair_variants_v004.png")
