"""Author v002 ladder using the four untouched materials from the base master.

Run: blender --background --python scripts/blender/build_base99_telescopic_ladder_v002.py
Geometry is authored in metres, Z up. The lower carriage has an explicit
Deploy_LowerSection action (2.5 m downward); Godot drives the same named part.
"""

from pathlib import Path
import bpy

PROJECT = Path(__file__).resolve().parents[2]
ROOT = PROJECT / "assets/art/props/base_world_3d"
SOURCE = ROOT / "source/base99_telescopic_ladder/prp_base99_telescopic_ladder_source_v002.blend"
COMPONENT = ROOT / "components/base99_telescopic_ladder"
MATERIAL_MASTER = PROJECT / "source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v026.blend"

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


PALETTE_PATH = (PROJECT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png").resolve()


ROLE_NAMES = (
    "01_精工金属_紫色骨架", "02_细腻哑光_青绿大面",
    "03_清漆反光_紫粉点缀", "04_柔和自发光_UI灯光",
)
with bpy.data.libraries.load(str(MATERIAL_MASTER), link=False) as (source_data, target_data):
    assert all(name in source_data.materials for name in ROLE_NAMES)
    target_data.materials = list(ROLE_NAMES)
FRAME, RUNG, ACCENT, GLOW = (bpy.data.materials[name] for name in ROLE_NAMES)
assert all(
    all(Path(bpy.path.abspath(node.image.filepath)).resolve() == PALETTE_PATH and node.interpolation == "Closest"
        for node in mat.node_tree.nodes if node.type == "TEX_IMAGE")
    for mat in (FRAME, RUNG, ACCENT, GLOW)
)


def box(name, location, scale, mat, parent, tile):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    layer = obj.data.uv_layers.new(name="PaletteUV")
    layer.active = True
    layer.active_render = True
    col, row = tile
    u0, u1 = (col - 1) / 10 + 0.025, col / 10 - 0.025
    v0, v1 = (row - 1) / 10 + 0.025, row / 10 - 0.025
    corners = ((u0, v0), (u1, v0), (u1, v1), (u0, v1))
    for polygon in obj.data.polygons:
        for offset, loop_index in enumerate(polygon.loop_indices):
            layer.data[loop_index].uv = corners[offset % 4]
    obj.parent = parent
    obj.matrix_parent_inverse = parent.matrix_world.inverted()
    return obj


def section(name, bottom, top, width, depth, rung_count, parent):
    half = width / 2
    for side in (-1, 1):
        box(f"{name}_纵梁_{side:+d}", (side * half, depth, (bottom + top) / 2),
            (0.105, 0.12, top - bottom), FRAME, parent, (10, 5))
        box(f"{name}_橡胶端_{side:+d}", (side * half, depth, bottom + 0.035),
            (0.12, 0.15, 0.07), RUNG, parent, (10, 2))
    for i in range(rung_count):
        height = bottom + 0.31 + i * (top - bottom - 0.62) / (rung_count - 1)
        box(f"{name}_踏棍_{i:02d}", (0, depth, height),
            (width - 0.07, 0.16, 0.055), RUNG, parent, (6, 5))
    for height in (bottom + 0.16, top - 0.16):
        box(f"{name}_限位锁扣_{height:.1f}", (0, depth - 0.08, height),
            (width + 0.14, 0.045, 0.11), ACCENT, parent, (3, 5))


fixed = bpy.data.objects.new("FixedUpper_固定上段", None)
moving = bpy.data.objects.new("LowerVisual_滑动下段", None)
bpy.context.collection.objects.link(fixed)
bpy.context.collection.objects.link(moving)
fixed["asset_part"] = "fixed_upper"
moving["asset_part"] = "telescopic_lower"
section("上段", 2.5, 6.0, 0.72, 0.0, 11, fixed)
section("下段", 0.0, 3.5, 0.62, -0.16, 11, moving)
for i, height in enumerate((2.6, 5.85)):
    box(f"固定墙距支架_{i}", (0, 0.25, height), (0.88, 0.47, 0.11), FRAME, fixed, (10, 5))
    box(f"展开状态灯_{i}", (0, -0.025, height), (0.14, 0.03, 0.07), GLOW, fixed, (5, 7))

# Source action is deliberately an authored object transform, not mesh morphing.
moving.location.z = 2.5
moving.keyframe_insert(data_path="location", frame=1, group="Deploy_LowerSection")
moving.location.z = 0.0
moving.keyframe_insert(data_path="location", frame=26, group="Deploy_LowerSection")
action = moving.animation_data.action
action.name = "Deploy_LowerSection"
action.use_fake_user = True
moving.location.z = 2.5
bpy.context.scene.frame_end = 26
bpy.context.scene.render.fps = 30

SOURCE.parent.mkdir(parents=True, exist_ok=True)
COMPONENT.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))

def export(part, target):
    bpy.ops.object.select_all(action="DESELECT")
    part.select_set(True)
    for child in part.children:
        child.select_set(True)
    bpy.context.view_layer.objects.active = part
    bpy.ops.export_scene.gltf(
        filepath=str(target), export_format="GLB", use_selection=True,
        export_yup=True, export_apply=True, export_texcoords=True,
        export_normals=True, export_materials="EXPORT", export_image_format="NONE",
        export_extras=True, export_cameras=False, export_lights=False,
        export_animations=False,
    )

export(fixed, COMPONENT / "prp_base99_telescopic_ladder_upper_visual_top3d.glb")
moving.animation_data_clear()
moving.location.z = 0.0
export(moving, COMPONENT / "prp_base99_telescopic_ladder_lower_visual_top3d.glb")
