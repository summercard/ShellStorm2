import bpy
import math
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
SOURCE_DIR = os.path.join(ROOT, "assets/art/environments/base_facility_3d/source/wall_height12")
COMPONENT_DIR = os.path.join(ROOT, "assets/art/environments/base_facility_3d/components/env_base99_structural_v021/east_upper_transition_stair")
BLEND_PATH = os.path.join(SOURCE_DIR, "env_base99_east_upper_transition_stair_12m_source_v001.blend")
GLB_PATH = os.path.join(COMPONENT_DIR, "east_upper_transition_stair_visual_top3d_v003.glb")

START_X, END_X = 6.50, 14.85
START_Y, END_Y = 5.00, 12.00
CENTER_Z, WIDTH, STEP_COUNT = -7.50, 2.20, 20


def material(name, color, metallic=0.0, roughness=0.55):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def add_box(name, center_godot, size_godot, mat):
    # Godot (x, y, z) -> Blender (x, -z, y).
    center = (center_godot[0], -center_godot[2], center_godot[1])
    size = (size_godot[0], size_godot[2], size_godot[1])
    bpy.ops.mesh.primitive_cube_add(location=center)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    return obj


def add_rail(name, z_godot, steel):
    run, rise = END_X - START_X, END_Y - START_Y
    length = math.sqrt(run * run + rise * rise)
    rail = add_box(name, ((START_X + END_X) * 0.5, (START_Y + END_Y) * 0.5 + 1.05, z_godot), (length, 0.08, 0.08), steel)
    rail.rotation_euler[1] = -math.atan2(rise, run)


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
steel = material("MAT_BASE99_STAIR_STEEL", (0.12, 0.17, 0.19), 0.65, 0.32)
edge = material("MAT_BASE99_STAIR_EDGE", (0.10, 0.56, 0.63), 0.35, 0.30)
run, rise = END_X - START_X, END_Y - START_Y
tread_run, step_rise = run / STEP_COUNT, rise / STEP_COUNT
for index in range(STEP_COUNT):
    x = START_X + tread_run * (index + 0.5)
    y = START_Y + step_rise * (index + 1)
    tread = add_box(f"Step_{index:02d}", (x, y, CENTER_Z), (tread_run + 0.025, 0.12, WIDTH), steel if index % 2 == 0 else edge)
    tread["walkable_visual"] = True
for side in (-1.0, 1.0):
    z = CENTER_Z + side * (WIDTH * 0.5 - 0.04)
    add_rail("Rail_Left" if side < 0 else "Rail_Right", z, steel)
    for index in range(6):
        t = index / 5.0
        add_box(f"RailPost_{'L' if side < 0 else 'R'}_{index:02d}", (START_X + run * t, START_Y + rise * t + 0.55, z), (0.08, 1.10, 0.08), steel)
add_box("LowerLanding", (START_X - 0.45, START_Y, CENTER_Z), (0.90, 0.16, WIDTH), steel)
add_box("UpperLanding", (END_X - 0.10, END_Y, CENTER_Z), (0.50, 0.16, WIDTH), steel)
os.makedirs(SOURCE_DIR, exist_ok=True)
os.makedirs(COMPONENT_DIR, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
bpy.ops.object.select_all(action="DESELECT")
for obj in bpy.context.scene.objects:
    if obj.type == "MESH":
        obj.select_set(True)
bpy.ops.export_scene.gltf(filepath=GLB_PATH, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
print(f"WROTE {BLEND_PATH}")
print(f"WROTE {GLB_PATH}")
