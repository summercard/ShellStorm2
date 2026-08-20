"""Render bright workbench previews for the three Base99 height-v002 modules."""

import bpy
from pathlib import Path
from mathutils import Vector


OUTPUT_DIR = Path("/Users/summercards/ShellStorm2/assets/art/environments/base_facility_3d/source/env_base99_modular_room/previews")
TARGET_IDS = {
    "ENV-BASE99-MEZZANINE-20X10-Z5",
    "ENV-BASE99-STAIR-L-Z5",
    "ENV-BASE99-STAIR-EXTERIOR-H4",
}
COLORS = {
    "01_精工金属_紫色骨架": (0.24, 0.08, 0.40, 1.0),
    "02_细腻哑光_青绿大面": (0.04, 0.42, 0.48, 1.0),
    "03_清漆反光_紫粉点缀": (0.88, 0.10, 0.50, 1.0),
    "04_柔和自发光_UI灯光": (0.00, 0.96, 1.00, 1.0),
}


def look_at(camera, target):
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()


def meshes(root):
    return [obj for obj in root.children_recursive if obj.type == "MESH"]


def bounds(objects):
    points = [obj.matrix_world @ corner.co for obj in objects for corner in obj.data.vertices]
    minimum = Vector(tuple(min(point[i] for point in points) for i in range(3)))
    maximum = Vector(tuple(max(point[i] for point in points) for i in range(3)))
    return minimum, maximum


def set_root_visible(root, visible):
    root.hide_render = not visible
    for child in root.children_recursive:
        child.hide_render = not visible


scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.studio_light = "paint.sl"
scene.display.shading.color_type = "MATERIAL"
scene.display.shading.show_shadows = True
scene.display.shading.show_cavity = True
scene.display.shading.cavity_type = "BOTH"
scene.display.shading.background_type = "VIEWPORT"
scene.display.shading.background_color = (0.018, 0.028, 0.052)
scene.display.shading.show_specular_highlight = True
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.render.resolution_percentage = 100
for name, color in COLORS.items():
    mat = bpy.data.materials.get(name)
    if mat:
        mat.diffuse_color = color

roots = [obj for obj in scene.objects if obj.type == "EMPTY" and obj.get("asset_id")]
targets = [obj for obj in roots if str(obj.get("asset_id")) in TARGET_IDS and "输出根节点" in obj.name]
if len(targets) != 3:
    raise RuntimeError("expected three v002 output roots, found %d" % len(targets))

camera = scene.objects.get("基地99层高度V002验收相机")
if camera is None:
    camera_data = bpy.data.cameras.new("基地99层高度V002验收相机")
    camera = bpy.data.objects.new("基地99层高度V002验收相机", camera_data)
    scene.collection.objects.link(camera)
scene.camera = camera
camera.data.lens = 58.0
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

for root in roots:
    set_root_visible(root, root in targets)
all_min, all_max = bounds([obj for root in targets for obj in meshes(root)])
all_center = (all_min + all_max) * 0.5
all_dim = all_max - all_min
radius = max(all_dim.x, all_dim.y, all_dim.z)
camera.location = all_center + Vector((radius * 0.82, -radius * 1.34, radius * 0.68))
look_at(camera, all_center + Vector((0, 0, all_dim.z * 0.05)))
scene.render.resolution_x = 1400
scene.render.resolution_y = 1000
scene.render.filepath = str(OUTPUT_DIR / "env_base99_height5_assets_v002_overview.png")
bpy.ops.render.render(write_still=True)

for target in targets:
    for root in roots:
        set_root_visible(root, root == target)
    minimum, maximum = bounds(meshes(target))
    center = (minimum + maximum) * 0.5
    dimensions = maximum - minimum
    radius = max(dimensions.x, dimensions.y, dimensions.z, 2.0)
    camera.location = center + Vector((radius * 0.90, -radius * 1.55, radius * 0.72))
    look_at(camera, center)
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 760
    slug = str(target.get("asset_id")).lower().replace("-", "_")
    scene.render.filepath = str(OUTPUT_DIR / (slug + "_preview.png"))
    bpy.ops.render.render(write_still=True)

print("BASE99_HEIGHT5_PREVIEWS_WRITTEN=" + str(OUTPUT_DIR))
