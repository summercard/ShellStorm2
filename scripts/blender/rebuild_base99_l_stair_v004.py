"""Rebuild the Base99 L stair from the editable v002 source components.

The broken v003 revision edited connected components inside the already-joined
game mesh.  This revision deliberately rebuilds the output from the editable
source objects: only the four long handrails and their four corner-end posts are
replaced, while every stair tread, beam, landing and guide light is preserved.
"""

import bpy
import json
from pathlib import Path
from mathutils import Matrix, Vector


PROJECT_ROOT = Path("/Users/summercards/ShellStorm2")
ASSET_ROOT = PROJECT_ROOT / "assets/art/environments/base_facility_3d"
INPUT_BLEND = ASSET_ROOT / "source/env_base99_modular_room/env_base99_modular_room_assets_clean_v002.blend"
OUTPUT_BLEND = ASSET_ROOT / "source/env_base99_modular_room/env_base99_modular_room_assets_clean_v004.blend"
OUTPUT_GLB = ASSET_ROOT / "components/env_base99_stair_l_z5/env_base99_stair_l_z5_visual_top3d_v004.glb"
MANIFEST = ASSET_ROOT / "source/env_base99_modular_room/env_base99_stair_l_z5_v004_manifest.json"

ASSET_ID = "ENV-BASE99-STAIR-L-Z5"
VERSION = "v004"
RAIL_THICKNESS = 0.10


def remove_object(obj):
    bpy.data.objects.remove(obj, do_unlink=True)


def clone_editable_root(source_root):
    duplicate_root = source_root.copy()
    duplicate_root.data = None
    source_root.users_collection[0].objects.link(duplicate_root)
    duplicate_root.name = "%s_制作根节点_%s" % (ASSET_ID, VERSION)
    duplicate_root.matrix_world = source_root.matrix_world.copy()
    for source in source_root.children:
        duplicate = source.copy()
        duplicate.data = source.data.copy() if source.data is not None else None
        source.users_collection[0].objects.link(duplicate)
        duplicate.parent = duplicate_root
        duplicate.matrix_local = source.matrix_local.copy()
        duplicate.hide_viewport = False
        duplicate.hide_render = False
        duplicate.hide_select = False
        duplicate.hide_set(False)
    return duplicate_root


def create_beam(parent, name, start, end, material):
    direction = end - start
    mesh = bpy.data.meshes.new(name + "_mesh")
    transform = (
        Matrix.Translation((start + end) * 0.5)
        @ direction.to_track_quat("Z", "Y").to_matrix().to_4x4()
        @ Matrix.Diagonal((RAIL_THICKNESS, RAIL_THICKNESS, direction.length, 1.0))
    )
    unit_vertices = (
        (-0.5, -0.5, -0.5), (0.5, -0.5, -0.5),
        (0.5, 0.5, -0.5), (-0.5, 0.5, -0.5),
        (-0.5, -0.5, 0.5), (0.5, -0.5, 0.5),
        (0.5, 0.5, 0.5), (-0.5, 0.5, 0.5),
    )
    faces = (
        (0, 1, 2, 3), (4, 7, 6, 5),
        (0, 4, 5, 1), (1, 5, 6, 2),
        (2, 6, 7, 3), (4, 0, 3, 7),
    )
    mesh.from_pydata([transform @ Vector(vertex) for vertex in unit_vertices], [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    parent.users_collection[0].objects.link(obj)
    obj.parent = parent
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.matrix_local = Matrix.Identity(4)
    obj.data.materials.append(material)
    uv_layer = obj.data.uv_layers.new(name="PaletteUV")
    for loop_uv in uv_layer.data:
        loop_uv.uv = (0.25, 0.25)
    obj["semantic_component"] = "handrail"
    obj["palette_uv_contract"] = "PaletteUV"
    return obj


def replace_corner_rails(editable_root):
    old_rails = [obj for obj in editable_root.children if "连续扶手" in obj.name]
    if len(old_rails) != 4:
        raise RuntimeError("Expected four editable continuous rails, got %d" % len(old_rails))
    rail_material = old_rails[0].data.materials[0]
    for obj in old_rails:
        remove_object(obj)

    # Remove only the four posts located inside the landing turn.  The nearest
    # retained posts support each newly shortened rail without crossing the
    # platform-owned L guard.
    terminal_tokens = (
        "上段_北扶手柱_01",
        "上段_南扶手柱_01",
        "下段_东扶手柱_06",
        "下段_西扶手柱_06",
    )
    terminal_posts = [
        obj for obj in editable_root.children
        if any(token in obj.name for token in terminal_tokens)
    ]
    if len(terminal_posts) != 4:
        raise RuntimeError("Expected four corner-end posts, got %d" % len(terminal_posts))
    for obj in terminal_posts:
        remove_object(obj)

    segments = (
        ("L型楼梯_制作_下段东侧收口扶手", Vector((-1.421, -5.081, 0.731)), Vector((-1.421, 1.620, 2.825))),
        ("L型楼梯_制作_下段西侧收口扶手", Vector((-4.341, -5.081, 0.731)), Vector((-4.341, 1.620, 2.825))),
        ("L型楼梯_制作_上段北侧起步扶手", Vector((-1.050, 5.079, 3.375)), Vector((4.454, 5.079, 5.670))),
        ("L型楼梯_制作_上段南侧起步扶手", Vector((-1.050, 2.159, 3.375)), Vector((4.454, 2.159, 5.670))),
    )
    for name, start, end in segments:
        create_beam(editable_root, name, start, end, rail_material)


def duplicate_for_output(source_obj, output_root, output_collection):
    duplicate = source_obj.copy()
    duplicate.data = source_obj.data.copy()
    output_collection.objects.link(duplicate)
    duplicate.parent = output_root
    duplicate.matrix_local = source_obj.matrix_local.copy()
    duplicate.hide_viewport = False
    duplicate.hide_render = False
    duplicate.hide_select = False
    duplicate.hide_set(False)
    return duplicate


def join_group(objects, output_name):
    if not objects:
        raise RuntimeError("Cannot join empty output group %s" % output_name)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.hide_viewport = False
        obj.hide_select = False
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    with bpy.context.temp_override(
        active_object=objects[0],
        object=objects[0],
        selected_objects=objects,
        selected_editable_objects=objects,
    ):
        bpy.ops.object.join()
    joined = bpy.context.active_object
    joined.name = output_name
    with bpy.context.temp_override(
        active_object=joined,
        object=joined,
        selected_objects=[joined],
        selected_editable_objects=[joined],
    ):
        bpy.ops.object.material_slot_remove_unused()
    joined.select_set(False)
    return joined


def build_output_root(editable_root):
    collection = bpy.data.collections.new("基地99层_L型楼梯_Z5米_v004_游戏输出")
    bpy.context.scene.collection.children.link(collection)
    output_root = bpy.data.objects.new("%s_输出根节点_%s" % (ASSET_ID, VERSION), None)
    collection.objects.link(output_root)
    output_root.matrix_world = editable_root.matrix_world.copy()
    body_objects = []
    emissive_objects = []
    for source_obj in editable_root.children:
        if source_obj.type != "MESH":
            continue
        duplicate = duplicate_for_output(source_obj, output_root, collection)
        material_names = [material.name for material in duplicate.data.materials]
        if any("自发光" in material_name for material_name in material_names):
            emissive_objects.append(duplicate)
        else:
            body_objects.append(duplicate)
    body = join_group(body_objects, "L型楼梯_主体_金属哑光反光")
    emissive = join_group(emissive_objects, "L型楼梯_UI灯光_柔和自发光")
    body.parent = output_root
    emissive.parent = output_root
    return output_root


def descendants(root):
    result = []
    pending = list(root.children)
    while pending:
        child = pending.pop()
        result.append(child)
        pending.extend(child.children)
    return result


def root_bounds(root):
    points = []
    inverse = root.matrix_world.inverted()
    for obj in descendants(root):
        if obj.type != "MESH":
            continue
        points.extend(inverse @ obj.matrix_world @ vertex.co for vertex in obj.data.vertices)
    minimum = Vector(tuple(min(point[index] for point in points) for index in range(3)))
    maximum = Vector(tuple(max(point[index] for point in points) for index in range(3)))
    return minimum, maximum


def export_glb(root):
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in descendants(root):
        child.select_set(True)
    bpy.context.view_layer.objects.active = root
    OUTPUT_GLB.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT_GLB),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_tangents=True,
        export_materials="EXPORT",
        export_extras=True,
        export_cameras=False,
        export_lights=False,
        export_animations=False,
    )


if Path(bpy.data.filepath).resolve() != INPUT_BLEND.resolve():
    raise RuntimeError("Open %s first" % INPUT_BLEND)

source_root = next(
    obj for obj in bpy.data.objects
    if obj.get("asset_id") == ASSET_ID and "制作根节点" in obj.name
)
editable_root = clone_editable_root(source_root)
replace_corner_rails(editable_root)
output_root = build_output_root(editable_root)

for root in (editable_root, output_root):
    root["asset_id"] = ASSET_ID
    root["asset_version"] = VERSION
    root["revision_reason"] = "rebuild_from_editable_source_preserve_stair_body_and_clean_landing_turn"
    root["railing_corner_contract"] = "stair_run_rails_end_before_platform_owned_l_guard"

bpy.context.view_layer.update()
minimum, maximum = root_bounds(output_root)
output_root["local_bounds_min"] = list(minimum)
output_root["local_bounds_max"] = list(maximum)
output_root["local_dimensions"] = list(maximum - minimum)
export_glb(output_root)

MANIFEST.write_text(json.dumps({
    "asset_id": ASSET_ID,
    "version": VERSION,
    "source": str(INPUT_BLEND),
    "output_blend": str(OUTPUT_BLEND),
    "glb": str(OUTPUT_GLB),
    "rebuild_source_mesh_count": len([obj for obj in editable_root.children if obj.type == "MESH"]),
    "output_mesh_count": len([obj for obj in output_root.children if obj.type == "MESH"]),
    "railing_corner_contract": output_root["railing_corner_contract"],
    "local_bounds_min": [round(value, 5) for value in minimum],
    "local_bounds_max": [round(value, 5) for value in maximum],
}, ensure_ascii=False, indent=2), encoding="utf-8")

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND), compress=True)
print("BASE99_L_STAIR_V004_WRITTEN:%s" % OUTPUT_BLEND)
print("BASE99_L_STAIR_V004_GLB_WRITTEN:%s" % OUTPUT_GLB)
