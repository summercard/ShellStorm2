import bpy, math, sys
from mathutils import Vector

OUT = r"I:/工作项目/shellstrom2/ShellStorm2/_scratch/task14"
C = r"I:/工作项目/shellstrom2/ShellStorm2/assets/art/environments/tower_zones/rooftop/components"
MODULES = [
    (C + r"\env_rooftop_ref_parapet_top3d.glb", "intact"),
    (C + r"\env_rooftop_ref_parapet_dmg_a_top3d.glb", "dmg_a"),
    (C + r"\env_rooftop_ref_parapet_dmg_b_top3d.glb", "dmg_b"),
    (C + r"\env_rooftop_ref_parapet_dmg_c_top3d.glb", "dmg_c"),
]

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def import_module(path, x_offset):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    roots = [o for o in bpy.data.objects if o not in before and o.parent is None]
    for root in roots:
        root.location.x += x_offset
    return roots

def make_camera(target, azimuth_deg, elevation_deg, distance, ortho_scale):
    data = bpy.data.cameras.new("cam")
    data.type = "ORTHO"
    data.ortho_scale = ortho_scale
    cam = bpy.data.objects.new("cam", data)
    bpy.context.scene.collection.objects.link(cam)
    az = math.radians(azimuth_deg); el = math.radians(elevation_deg)
    direction = Vector((math.cos(az) * math.cos(el), math.sin(az) * math.cos(el), math.sin(el)))
    cam.location = target + direction * distance
    cam.rotation_euler = (target - cam.location).normalized().to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam

def setup_render(w, h):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = w
    scene.render.resolution_y = h
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "SINGLE"
    shading.single_color = (0.66, 0.66, 0.63)
    shading.show_cavity = True
    shading.cavity_type = "BOTH"
    shading.show_shadows = True
    shading.show_object_outline = True

# ---- A: 三个破损变体并排 ----
reset()
setup_render(1500, 620)
for index, (path, _name) in enumerate(MODULES[1:]):
    import_module(path, index * 5.6)
make_camera(Vector((5.6, 0.0, 0.9)), -62.0, 16.0, 30.0, 17.5)
bpy.context.scene.render.filepath = OUT + r"\variants_row.png"
bpy.ops.render.render(write_still=True)
print("RENDER variants_row.png")

# ---- B: 完好 + 三种破损首尾相接（间距严格 = 模块长 5.0m）----
reset()
setup_render(1500, 620)
for index, (path, _name) in enumerate(MODULES):
    import_module(path, index * 5.0)
make_camera(Vector((7.5, 0.0, 0.9)), -78.0, 9.0, 30.0, 21.5)
bpy.context.scene.render.filepath = OUT + r"\variants_butted.png"
bpy.ops.render.render(write_still=True)
print("RENDER variants_butted.png")
