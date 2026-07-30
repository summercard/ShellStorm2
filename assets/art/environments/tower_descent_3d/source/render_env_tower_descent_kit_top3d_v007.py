"""Render PH49 base and stacked-floor review previews from v007."""

from pathlib import Path

import bpy
from mathutils import Vector


SOURCE_DIR = Path(__file__).resolve().parent
SOURCE_BLEND = SOURCE_DIR / "env_tower_descent_kit_top3d_v007.blend"
OUTPUT_DIR = (
    Path("/Users/summercards/ShellStorm2")
    / "outputs/019fb2a5-6bc8-7d10-a214-90288a5f7e80/previews"
)
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

if Path(bpy.data.filepath).resolve() != SOURCE_BLEND.resolve():
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE_BLEND))

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 1100
scene.render.resolution_y = 720
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.render.image_settings.color_mode = "RGBA"
scene.world.color = (0.007, 0.012, 0.018)


def look_at(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def ensure_camera():
    camera = bpy.data.objects.get("PH49_ReviewCamera")
    if camera is None:
        data = bpy.data.cameras.new("PH49_ReviewCamera_Data")
        camera = bpy.data.objects.new("PH49_ReviewCamera", data)
        scene.collection.objects.link(camera)
    camera.data.lens = 52
    camera.data.sensor_width = 36
    scene.camera = camera
    return camera


def ensure_light(name, light_type, energy, color):
    light = bpy.data.objects.get(name)
    if light is None:
        data = bpy.data.lights.new(name=f"{name}_Data", type=light_type)
        light = bpy.data.objects.new(name, data)
        scene.collection.objects.link(light)
    light.data.energy = energy
    light.data.color = color
    return light


sun = ensure_light("PH49_ReviewSun", "SUN", 1.25, (0.78, 0.88, 1.0))
sun.rotation_euler = (0.65, -0.35, -0.55)
area = ensure_light("PH49_ReviewArea", "AREA", 900.0, (0.24, 0.78, 1.0))
area.data.shape = "DISK"
area.data.size = 90.0
area.location = (10.0, -15.0, 68.0)
look_at(area, (2.5, 2.5, -18.0))
camera = ensure_camera()

runtime_children = {
    name: bpy.data.collections.get(name)
    for name in (
        "20A_LEVEL_GUIDES_250M",
        "20B_BASE_99_30M",
        "20C_ROOMS_98_95",
        "20D_STANDALONE_ELEVATORS",
        "20E_DOOR_CONTRACT_V002",
    )
}
stair_collection = bpy.data.collections.get("02_STAIRWELLS")
if stair_collection is not None:
    stair_collection.hide_render = True


def set_visible(names):
    for name, collection in runtime_children.items():
        if collection is not None:
            collection.hide_render = name not in names


set_visible({"20B_BASE_99_30M", "20D_STANDALONE_ELEVATORS", "20E_DOOR_CONTRACT_V002"})
for obj in bpy.data.objects:
    if (
        obj.get("asset_role") == "STANDALONE_ELEVATOR_FACILITY"
        and int(obj.get("floor_number", 0)) != 99
    ):
        obj.hide_render = True
camera.location = (62.0, -70.0, 58.0)
look_at(camera, (2.5, 2.5, -9.0))
scene.render.filepath = str(OUTPUT_DIR / "env_tower_descent_v007_base99.png")
bpy.ops.render.render(write_still=True)

for obj in bpy.data.objects:
    if obj.get("asset_role") == "STANDALONE_ELEVATOR_FACILITY":
        obj.hide_render = False
set_visible({"20C_ROOMS_98_95", "20D_STANDALONE_ELEVATORS", "20E_DOOR_CONTRACT_V002"})
camera.location = (185.0, -205.0, 145.0)
look_at(camera, (2.5, -2.5, -29.0))
camera.data.lens = 58
scene.render.filepath = str(OUTPUT_DIR / "env_tower_descent_v007_floors98_95.png")
bpy.ops.render.render(write_still=True)

print(f"RENDER_V007_OK output={OUTPUT_DIR}")
