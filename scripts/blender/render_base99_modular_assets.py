import bpy
from pathlib import Path
from mathutils import Vector


OUTPUT_DIR = Path(
    "/Users/summercards/ShellStorm2/assets/art/environments/base_facility_3d/"
    "source/env_base99_modular_room/previews"
)
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

PREVIEW_COLORS = {
    "01_精工金属_紫色骨架": (0.16, 0.07, 0.28, 1.0),
    "02_细腻哑光_青绿大面": (0.035, 0.30, 0.33, 1.0),
    "03_清漆反光_紫粉点缀": (0.72, 0.08, 0.42, 1.0),
    "04_柔和自发光_UI灯光": (0.00, 0.92, 1.00, 1.0),
}


def look_at(camera, target):
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()


def object_world_points(obj):
    return [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]


def bounds(objects):
    points = [point for obj in objects for point in object_world_points(obj)]
    minimum = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    maximum = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return minimum, maximum


scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "MATERIAL"
scene.display.shading.show_shadows = True
scene.display.shading.show_cavity = True
scene.display.shading.cavity_type = "BOTH"
scene.display.shading.background_type = "WORLD"
scene.display.shading.show_specular_highlight = True
scene.world.color = (0.025, 0.035, 0.065)
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.render.resolution_percentage = 100
for material_name, color in PREVIEW_COLORS.items():
    material = bpy.data.materials.get(material_name)
    if material:
        material.diffuse_color = color

camera = bpy.data.objects.get("基地99层模块总览_相机")
if camera is None:
    camera_data = bpy.data.cameras.new("基地99层模块总览_相机")
    camera = bpy.data.objects.new("基地99层模块总览_相机", camera_data)
    bpy.context.scene.collection.objects.link(camera)
scene.camera = camera
camera.data.lens = 55.0

output_master = bpy.data.collections["02_游戏输出_整合模型"]
roots = sorted(
    [obj for obj in output_master.all_objects if obj.type == "EMPTY" and obj.get("asset_id")],
    key=lambda obj: obj.get("asset_id"),
)

for root in roots:
    root.hide_render = False
camera.location = (84.0, -118.0, 82.0)
look_at(camera, Vector((0.0, -3.0, 4.0)))
scene.render.resolution_x = 1400
scene.render.resolution_y = 1000
scene.render.filepath = str(OUTPUT_DIR / "env_base99_modular_room_assets_clean_v001_overview.png")
bpy.ops.render.render(write_still=True)

for root in roots:
    for other in roots:
        other.hide_render = other != root
        for child in other.children_recursive:
            child.hide_render = other != root
    module_meshes = [child for child in root.children_recursive if child.type == "MESH"]
    minimum, maximum = bounds(module_meshes)
    center = (minimum + maximum) * 0.5
    dimensions = maximum - minimum
    radius = max(dimensions.x, dimensions.y, dimensions.z, 2.0)
    camera.location = center + Vector((radius * 0.92, -radius * 1.65, radius * 0.78))
    look_at(camera, center + Vector((0.0, 0.0, dimensions.z * 0.05)))
    camera.data.lens = 58.0
    scene.render.resolution_x = 900
    scene.render.resolution_y = 700
    slug = str(root.get("asset_id")).lower().replace("-", "_")
    scene.render.filepath = str(OUTPUT_DIR / f"{slug}_preview.png")
    bpy.ops.render.render(write_still=True)

for root in roots:
    root.hide_render = False
    for child in root.children_recursive:
        child.hide_render = False
print(f"BASE99_PREVIEWS_WRITTEN:{OUTPUT_DIR}")
