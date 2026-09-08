import bpy
from mathutils import Vector
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "source/art/blender/base_facility_layout/component_packages/architecture/base_corner_l_5m/preview_base_corner_l_5m_v024.png"


def aim_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


for collection in bpy.data.collections:
    collection.hide_render = collection.name in {"01_制作组件_已统一材质", "03_碰撞代理_Godot规格"}

bpy.ops.mesh.primitive_plane_add(size=24, location=(2.0, 2.0, -0.02))
ground = bpy.context.object
ground.name = "PREVIEW_Ground"
ground_material = bpy.data.materials.new("PREVIEW_GroundMaterial")
ground_material.diffuse_color = (0.035, 0.05, 0.075, 1.0)
ground.data.materials.append(ground_material)

bpy.ops.object.camera_add(location=(9.5, 11.0, 8.2))
camera = bpy.context.object
aim_at(camera, (2.0, 2.3, 3.8))
camera.data.lens = 52
bpy.context.scene.camera = camera

for name, location, energy, color, size in (
    ("Key", (3.0, 4.0, 11.0), 1150.0, (0.55, 0.78, 1.0), 5.0),
    ("Fill", (-4.0, 1.0, 6.0), 750.0, (0.35, 0.55, 1.0), 4.0),
    ("Rim", (7.0, 3.0, 7.0), 900.0, (1.0, 0.38, 0.17), 3.0),
):
    light_data = bpy.data.lights.new(name, "AREA")
    light_data.energy = energy
    light_data.color = color
    light_data.shape = "DISK"
    light_data.size = size
    light = bpy.data.objects.new(name, light_data)
    bpy.context.scene.collection.objects.link(light)
    light.location = location
    aim_at(light, (2.0, 2.3, 4.0))

world = bpy.context.scene.world or bpy.data.worlds.new("PreviewWorld")
bpy.context.scene.world = world
world.use_nodes = True
background = next((node for node in world.node_tree.nodes if node.type == "BACKGROUND"), None)
if background is None:
    background = world.node_tree.nodes.new("ShaderNodeBackground")
    output = next((node for node in world.node_tree.nodes if node.type == "OUTPUT_WORLD"), None)
    if output is None:
        output = world.node_tree.nodes.new("ShaderNodeOutputWorld")
    world.node_tree.links.new(background.outputs["Background"], output.inputs["Surface"])
background.inputs["Color"].default_value = (0.008, 0.012, 0.025, 1.0)
background.inputs["Strength"].default_value = 0.18

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 640
scene.render.resolution_y = 640
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(OUTPUT)
scene.render.film_transparent = False
scene.view_settings.look = "Medium High Contrast"
bpy.ops.render.render(write_still=True)
print(f"BASE_CORNER_L_PREVIEW={OUTPUT}")
